package app.kadr.android.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

@Serializable data class ApiSession(val baseURL: String, val userID: String, val token: String)

class SessionVault(context: Context) {
    private val file = AtomicFile(File(context.filesDir, "session.enc"))
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (store.getKey("kadr-session", null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("kadr-session", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun save(session: ApiSession) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val data = cipher.iv + cipher.doFinal(Codec.encodeToString(session).toByteArray())
        val stream = file.startWrite()
        try { stream.write(data); file.finishWrite(stream) } catch (failure: Exception) { file.failWrite(stream); throw failure }
    }
    fun load(): ApiSession? = runCatching {
        if (!file.baseFile.exists()) return null
        val data = file.readFully()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(0, 12))) }
        Codec.decodeFromString<ApiSession>(cipher.doFinal(data.copyOfRange(12, data.size)).decodeToString())
    }.getOrNull()
    fun clear() = file.delete()
}

/** The same REST and resource synchronization contract used by the iOS client. */
class RemoteApi(private val session: ApiSession) {
    init {
        val uri = URI(session.baseURL)
        require(uri.scheme == "https" && uri.host != null && uri.userInfo == null && uri.query == null && uri.fragment == null) { "Вкажи коректну HTTPS-адресу сервера." }
        require(session.token.isNotBlank() && !session.token.contains('\n') && !session.token.contains('\r'))
    }
    private suspend fun request(path: String, method: String = "GET", body: ByteArray? = null): ByteArray = withContext(Dispatchers.IO) {
        val connection = URI(session.baseURL.trimEnd('/') + "/" + path).toURL().openConnection() as HttpURLConnection
        try {
            connection.instanceFollowRedirects = false
            connection.requestMethod = method; connection.connectTimeout = 15000; connection.readTimeout = 30000
            connection.setRequestProperty("Authorization", "Bearer ${session.token}")
            if (body != null) { connection.doOutput = true; connection.setRequestProperty("Content-Type", "application/json"); connection.outputStream.use { it.write(body) } }
            val code = connection.responseCode
            if (code !in 200..299) {
                val message = connection.errorStream?.use { it.readBytes().decodeToString() }.orEmpty()
                val readable = runCatching { Codec.parseToJsonElement(message).jsonObject["error"]?.jsonPrimitive?.content }.getOrNull()
                error(readable ?: "Сервер відповів HTTP $code")
            }
            connection.inputStream.use { it.readBytes() }
        } finally { connection.disconnect() }
    }
    suspend fun search(handle: String): List<Profile> {
        val payload = request("users?handle=" + URLEncoder.encode(handle.removePrefix("@"), "UTF-8"))
        return Codec.decodeFromString(payload.decodeToString())
    }
    suspend fun follow(id: String, following: Boolean) { request("users/$id/follow", if (following) "PUT" else "DELETE") }
    suspend fun messages(peer: String): List<Message> = Codec.decodeFromString(request("conversations/$peer/messages").decodeToString())
    suspend fun send(peer: String, message: Message): Message = Codec.decodeFromString(request("conversations/$peer/messages", "POST", Codec.encodeToString(buildJsonObject { put("id", message.id); put("text", message.text) }).toByteArray()).decodeToString())
    suspend fun synchronize(repository: LocalRepository) {
        val owner = repository.requireAccount()
        require(owner.equals(session.userID, true)) { "Сесія сервера належить іншому акаунту." }
        val snapshot = repository.state.value
        val mutations = snapshot.outbox.filter { it.owner == owner }
        val files = snapshot.posts.filter { it.authorID == owner }.flatMap { it.media.map(PostMedia::file) } + listOfNotNull(snapshot.active?.portraitFile)
        for (name in files.distinct()) {
            require(File(name).name == name && !name.contains(".."))
            val file = File(repository.mediaDirectory, name)
            if (file.exists()) withContext(Dispatchers.IO) {
                val head = URI(session.baseURL.trimEnd('/') + "/assets/" + name).toURL().openConnection() as HttpURLConnection
                val exists = try {
                    head.instanceFollowRedirects = false; head.requestMethod = "HEAD"; head.connectTimeout = 15000; head.readTimeout = 15000
                    head.setRequestProperty("Authorization", "Bearer ${session.token}")
                    val code = head.responseCode
                    require(code in 200..299 || code == 404) { "Сервер не підтвердив доступ до медіа: HTTP $code" }
                    code in 200..299 && head.contentLengthLong == file.length()
                } finally { head.disconnect() }
                if (exists) return@withContext
                val connection = URI(session.baseURL.trimEnd('/') + "/assets/" + name).toURL().openConnection() as HttpURLConnection
                try {
                    connection.instanceFollowRedirects = false; connection.requestMethod = "PUT"; connection.connectTimeout = 15000; connection.readTimeout = 60000
                    connection.setRequestProperty("Authorization", "Bearer ${session.token}"); connection.setRequestProperty("Content-Type", "application/octet-stream")
                    connection.doOutput = true; connection.setFixedLengthStreamingMode(file.length())
                    connection.outputStream.use { output -> file.inputStream().use { it.copyTo(output) } }
                    check(connection.responseCode in 200..299) { "Не вдалося надіслати оригінал медіа." }
                } finally { connection.disconnect() }
            }
        }
        for (batch in mutations.chunked(50)) { request("sync", "POST", Codec.encodeToString(batch).toByteArray()); repository.acknowledge(batch) }
        var cursor = snapshot.cursors[owner] ?: 0
        while (true) {
            val page = Codec.decodeFromString<SyncPage>(request("sync?after=$cursor").decodeToString())
            for (record in page.records) {
                val value = Codec.parseToJsonElement(Base64.decode(record.payload, Base64.DEFAULT).decodeToString()).jsonObject
                val referenced = buildList {
                    if (record.resource in setOf("post", "draft")) value["media"]?.jsonArray?.forEach { add(it.jsonObject["file"]?.jsonPrimitive?.content.orEmpty()) }
                    if (record.resource == "profile") listOf("portraitFile", "bannerFile").forEach { value[it]?.jsonPrimitive?.contentOrNull?.let(::add) }
                }
                for (name in referenced.filter { it.isNotBlank() }) {
                    require(File(name).name == name && !name.contains(".."))
                    val target = File(repository.mediaDirectory, name)
                    if (!target.exists()) {
                        downloadAsset(name, target)
                    }
                }
            }
            repository.importRemote(page.records, page.cursor, owner)
            if (page.cursor <= cursor) break
            cursor = page.cursor
        }
    }

    private suspend fun downloadAsset(name: String, target: File) = withContext(Dispatchers.IO) {
        val connection = URI(session.baseURL.trimEnd('/') + "/assets/" + name).toURL().openConnection() as HttpURLConnection
        val atomic = AtomicFile(target)
        var stream: java.io.FileOutputStream? = null
        try {
            connection.instanceFollowRedirects = false; connection.connectTimeout = 15000; connection.readTimeout = 60000
            connection.setRequestProperty("Authorization", "Bearer ${session.token}")
            check(connection.responseCode in 200..299) { "Не вдалося завантажити медіа: HTTP ${connection.responseCode}" }
            stream = atomic.startWrite(); connection.inputStream.use { it.copyTo(stream) }; atomic.finishWrite(stream)
        } catch (failure: Exception) { stream?.let(atomic::failWrite); throw failure }
        finally { connection.disconnect() }
    }
}
