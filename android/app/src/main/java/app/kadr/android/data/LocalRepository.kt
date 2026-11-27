package app.kadr.android.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.AtomicFile
import android.util.Base64
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.io.File

class LocalRepository(val context: Context, private val scope: CoroutineScope) {
    private val mutable = MutableStateFlow(AppState())
    val state = mutable.asStateFlow()
    val ready = MutableStateFlow(false)
    val error = MutableStateFlow<String?>(null)
    private val writer = Channel<AppState>(Channel.CONFLATED)
    private val disk = AtomicFile(File(context.filesDir, "kadr-state.json"))
    val mediaDirectory = File(context.filesDir, "media").apply { mkdirs() }
    private var writable = true
    init {
        scope.launch {
            val loaded = withContext(Dispatchers.IO) {
                if (!disk.baseFile.exists()) AppState() else runCatching { Codec.decodeFromString<AppState>(disk.readFully().decodeToString()) }.getOrElse {
                    writable = false; error.value = "Не вдалося прочитати збережені дані. Файл збережено без змін."; AppState()
                }
            }
            mutable.value = loaded; ready.value = true
            for (next in writer) withContext(Dispatchers.IO) {
                var stream: java.io.FileOutputStream? = null
                try { stream = disk.startWrite(); stream.write(Codec.encodeToString(next).toByteArray()); disk.finishWrite(stream) }
                catch (failure: Exception) { stream?.let(disk::failWrite); error.value = "Не вдалося зберегти зміни: ${failure.localizedMessage}" }
            }
        }
    }
    private fun commit(next: AppState) {
        check(ready.value && writable) { "Локальні дані ще не готові або доступні лише для читання." }
        mutable.value = next; writer.trySend(next)
    }
    private inline fun <reified T> record(state: AppState, owner: String, kind: String, key: String, value: T): AppState {
        val payload = Base64.encodeToString(Codec.encodeToString(value).toByteArray(), Base64.NO_WRAP)
        val mutation = ResourceRecord(owner, kind, key, payload)
        return state.copy(outbox = state.outbox.filterNot { it.owner == owner && it.resource == kind && it.entityID == key } + mutation)
    }
    fun requireAccount(): String = state.value.activeID ?: error("Увійди або створи акаунт, щоб виконати цю дію.")
    fun welcome() = commit(state.value.copy(welcomed = true))
    fun activate(id: String?) { require(id == null || state.value.profiles.any { it.id == id }); commit(state.value.copy(activeID = id, welcomed = true)) }
    fun createAccount(handle: String, name: String, avatar: String? = null, bio: String = "") {
        val current = state.value
        AccountRules.validate(handle, name, current.profiles)?.let { error(it) }
        val profile = Profile(handle = AccountRules.normalize(handle), name = name.trim(), avatar = avatar, bio = bio.trim().take(4000))
        var next = current.copy(profiles = current.profiles + profile, activeID = profile.id, welcomed = true)
        next = record(next, profile.id, "profile", profile.id, profile)
        commit(next)
    }
    fun editProfile(name: String, handle: String, bio: String) {
        val id = requireAccount(); val current = state.value
        AccountRules.validate(handle, name, current.profiles, id)?.let { error(it) }
        val profile = current.active!!.copy(name = name.trim(), handle = AccountRules.normalize(handle), bio = bio.trim().take(4000))
        commit(record(current.copy(profiles = current.profiles.map { if (it.id == id) profile else it }), id, "profile", id, profile))
    }
    suspend fun setPhoto(uri: Uri) {
        val owner = requireAccount()
        val media = importMedia(listOf(uri)).single()
        val avatar = withContext(Dispatchers.IO) {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(File(mediaDirectory, media.file).path, options)
            options.inJustDecodeBounds = false; options.inSampleSize = (maxOf(options.outWidth, options.outHeight) / 512).coerceAtLeast(1)
            val image = checkNotNull(BitmapFactory.decodeFile(File(mediaDirectory, media.file).path, options)) { "Фото не підтримується." }
            java.io.ByteArrayOutputStream().use { output -> image.compress(Bitmap.CompressFormat.JPEG, 90, output); image.recycle(); Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP) }
        }
        check(state.value.activeID == owner) { "Акаунт змінився." }
        val current = state.value; val profile = current.active!!.copy(portraitFile = media.file, avatar = avatar)
        commit(record(current.copy(profiles = current.profiles.map { if (it.id == owner) profile else it }), owner, "profile", owner, profile))
    }
    fun changeStudio(transform: (Studio) -> Studio) {
        val current = state.value; val key = current.activeID ?: "guest"; val account = transform(current.studio)
        var next = current.copy(studios = current.studios + (key to account))
        if (current.activeID != null) {
            next = record(next, key, "preferences", key, account)
            next = record(next, key, "appearance", key, account.appearance)
        }
        commit(next)
    }
    fun toggleReaction(post: Post, saved: Boolean = false) {
        val owner = requireAccount(); val current = state.value
        val source = if (saved) current.bookmarks else current.likes
        val before = source[post.id].orEmpty(); val after = if (owner in before) before - owner else before + owner
        var next = if (saved) current.copy(bookmarks = source + (post.id to after)) else current.copy(likes = source + (post.id to after))
        next = record(next, owner, "reaction", post.id, buildJsonObject {
            put("postID", post.id); put("liked", owner in next.likes[post.id].orEmpty()); put("bookmarked", owner in next.bookmarks[post.id].orEmpty())
        }); commit(next)
    }
    fun follow(peer: String) {
        val owner = requireAccount(); require(peer != owner)
        val current = state.value; val ids = current.following[owner].orEmpty()
        val updated = if (peer in ids) ids - peer else ids + peer
        commit(record(current.copy(following = current.following + (owner to updated)), owner, "following", owner, buildJsonObject { put("ids", JsonArray(updated.map(::JsonPrimitive))) }))
    }
    fun addComment(post: Post, text: String, parent: String? = null) {
        val owner = requireAccount(); require(post.options.allowsComments) { "Автор вимкнув коментарі." }
        require(text.isNotBlank() && text.length <= 4000) { "Коментар має містити 1–4000 символів." }
        val comment = Comment(authorID = owner, text = text.trim(), parentID = parent)
        val current = state.value
        commit(record(current.copy(comments = current.comments + (post.id to (current.comments[post.id].orEmpty() + comment))), owner, "comment", comment.id, buildJsonObject { put("postID", post.id); put("comment", Codec.encodeToJsonElement(comment)) }))
    }
    fun updateComment(post: Post, comment: Comment, text: String? = null, delete: Boolean = false, pin: Boolean = false) {
        val owner = requireAccount(); val current = state.value
        val list = current.comments[post.id].orEmpty()
        if (pin) {
            require(post.authorID == owner) { "Закріплювати може автор публікації." }
            val updated = list.map { it.copy(pinned = it.id == comment.id && !comment.pinned) }
            commit(record(current.copy(comments = current.comments + (post.id to updated)), owner, "commentPin", post.id, buildJsonObject { put("postID", post.id); put("commentID", if (comment.pinned) JsonNull else JsonPrimitive(comment.id)) })); return
        }
        if (delete || text != null) {
            require(comment.authorID == owner); require(text == null || text.isNotBlank())
            val value = comment.copy(text = text?.trim() ?: comment.text)
            val updated = if (delete) list.filterNot { it.id == comment.id } else list.map { if (it.id == comment.id) value else it }
            val payload = buildJsonObject { if (delete) put("deleted", true) else { put("postID", post.id); put("comment", Codec.encodeToJsonElement(value)) } }
            commit(record(current.copy(comments = current.comments + (post.id to updated)), owner, "comment", comment.id, payload)); return
        }
        val liked = owner !in comment.likes
        val updated = list.map { if (it.id == comment.id) it.copy(likes = if (liked) it.likes + owner else it.likes - owner) else it }
        commit(record(current.copy(comments = current.comments + (post.id to updated)), owner, "commentReaction", comment.id, buildJsonObject { put("postID", post.id); put("commentID", comment.id); put("liked", liked) }))
    }
    fun send(peer: String, text: String, reply: String? = null) {
        val owner = requireAccount(); val current = state.value
        require(text.isNotBlank() && text.length <= 4000) { "Повідомлення має містити 1–4000 символів." }
        val prior = current.messages.any { setOf(it.senderID, it.recipientID) == setOf(owner, peer) }
        require(prior || peer in current.following[owner].orEmpty()) { "Спочатку підпишись на користувача." }
        val target = current.studios[peer]?.preferences ?: Preferences()
        require(owner !in target.blocked && peer !in current.studio.preferences.blocked && target.messagePermission != "nobody") { "Повідомлення для цього користувача недоступні." }
        val message = Message(senderID = owner, recipientID = peer, text = text.trim(), replyTo = reply)
        commit(record(current.copy(messages = current.messages + message), owner, "message", message.id, Codec.encodeToJsonElement(message).jsonObject.toMutableMap().apply { reply?.let { put("replyTo", JsonPrimitive(it)) } }.let(::JsonObject)))
        changeStudio { it.copy(chatDrafts = it.chatDrafts - peer) }
    }
    fun editMessage(message: Message, text: String? = null, delete: Boolean = false, emoji: String? = null) {
        val owner = requireAccount(); val current = state.value
        if (emoji != null) {
            val payload = buildJsonObject { put("messageID", message.id); put("emoji", if (message.reactions[owner] == emoji) "" else emoji) }
            val updated = message.copy(reactions = if (message.reactions[owner] == emoji) message.reactions - owner else message.reactions + (owner to emoji))
            commit(record(current.copy(messages = current.messages.map { if (it.id == message.id) updated else it }), owner, "messageReaction", message.id, payload)); return
        }
        require(message.senderID == owner)
        val updated = message.copy(text = text?.trim()?.also { require(it.isNotBlank()) } ?: message.text, edited = true)
        val messages = if (delete) current.messages.filterNot { it.id == message.id } else current.messages.map { if (it.id == message.id) updated else it }
        val payload = if (delete) buildJsonObject { put("deleted", true) } else Codec.encodeToJsonElement(updated)
        commit(record(current.copy(messages = messages), owner, "message", message.id, payload))
    }
    suspend fun importMedia(uris: List<Uri>): List<PostMedia> = withContext(Dispatchers.IO) {
        uris.map { uri ->
            val type = context.contentResolver.getType(uri).orEmpty()
            require(type.startsWith("image/") || type.startsWith("video/")) { "Оберіть фото або відео." }
            val extension = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(type) ?: if (type.startsWith("video")) "mp4" else "jpg"
            val name = "media-${newId()}.$extension"
            val target = File(mediaDirectory, name)
            try { context.contentResolver.openInputStream(uri).use { input -> requireNotNull(input); target.outputStream().use { input.copyTo(it) } }; require(target.length() > 0) }
            catch (failure: Exception) { target.delete(); throw failure }
            PostMedia(kind = if (type.startsWith("video")) "video" else "photo", file = name)
        }
    }
    fun publish(post: Post) {
        val owner = requireAccount(); require(post.media.isNotEmpty()) { "Додай фото або відео." }
        require(post.authorID == null || post.authorID == owner)
        val value = post.copy(authorID = owner, file = post.items.first().file)
        val current = state.value
        val next = current.copy(posts = current.posts.filterNot { it.id == value.id } + value)
        commit(record(next, owner, if (value.isDraft) "draft" else "post", value.id, value))
    }
    fun deletePost(post: Post) {
        val owner = requireAccount(); require(post.authorID == owner)
        val current = state.value
        commit(record(current.copy(posts = current.posts.filterNot { it.id == post.id }), owner, if (post.isDraft) "draft" else "post", post.id, buildJsonObject { put("deleted", true) }))
    }
    fun mediaUri(item: PostMedia): Uri = item.remoteURL?.let(Uri::parse) ?: if (item.file in setOf("bunny.mp4", "sintel.mp4")) Uri.parse("asset:///${item.file}") else Uri.fromFile(File(mediaDirectory, item.file))
    fun feed(section: Int): List<Post> {
        val current = state.value; val me = current.activeID; val preferences = current.studio.preferences
        return (AppState.samples + current.posts).filter { post ->
            !post.isDraft && (!post.options.onlyMe || post.authorID == me) &&
                post.id !in preferences.hiddenPosts && post.authorID !in preferences.blocked && post.authorID !in preferences.hiddenAuthors &&
                preferences.mutedWords.none { post.caption.contains(it, true) } &&
                (preferences.mediaFilter == "all" || post.photo == (preferences.mediaFilter == "photo")) &&
                (section != 1 || (me != null && post.authorID in current.following[me].orEmpty()))
        }.sortedByDescending { post ->
            (if (post.authorID in current.following[me].orEmpty()) 1000 else 0) +
                preferences.preferredTags.count { post.options.tags.contains(it, true) } * 100 +
                ((post.id + (me ?: "guest")).hashCode().toLong().and(0x7fffffff) % 97).toInt()
        }
    }
    fun importRemote(records: List<ResourceRecord>, cursor: Int, owner: String) {
        if (state.value.activeID != owner) return
        var next = state.value
        for (record in records) {
            if (next.outbox.any { it.owner.equals(record.owner, true) && it.resource == record.resource && it.entityID.equals(record.entityID, true) }) continue
            val payload = WireIds.normalize(Codec.parseToJsonElement(Base64.decode(record.payload, Base64.DEFAULT).decodeToString())).jsonObject
            val deleted = payload["deleted"]?.jsonPrimitive?.booleanOrNull == true
            val key = WireIds.canonical(record.entityID)
            when (record.resource) {
                "profile" -> if (!deleted) { val value = Codec.decodeFromJsonElement<Profile>(payload); next = next.copy(profiles = next.profiles.filterNot { it.id.equals(value.id, true) } + value) }
                "post", "draft" -> { next = next.copy(posts = next.posts.filterNot { it.id == key && it.isDraft == (record.resource == "draft") }); if (!deleted) next = next.copy(posts = next.posts.filterNot { it.id == key } + Codec.decodeFromJsonElement<Post>(payload).copy(isDraft = record.resource == "draft")) }
                "appearance" -> if (!deleted) { val studio = next.studios[record.owner] ?: Studio(); next = next.copy(studios = next.studios + (record.owner to studio.copy(appearance = Codec.decodeFromJsonElement(payload)))) }
                "comment" -> { val values = next.comments.mapValues { (_, list) -> list.filterNot { it.id == key } }; next = next.copy(comments = values); if (!deleted) { val post = payload.getValue("postID").jsonPrimitive.content; next = next.copy(comments = next.comments + (post to (next.comments[post].orEmpty() + Codec.decodeFromJsonElement<Comment>(payload.getValue("comment"))))) } }
                "reaction" -> if (!deleted) { val post = payload.getValue("postID").jsonPrimitive.content; val liked = payload["liked"]?.jsonPrimitive?.booleanOrNull == true; val saved = payload["bookmarked"]?.jsonPrimitive?.booleanOrNull == true; next = next.copy(likes = next.likes + (post to if (liked) next.likes[post].orEmpty() + record.owner else next.likes[post].orEmpty() - record.owner), bookmarks = next.bookmarks + (post to if (saved) next.bookmarks[post].orEmpty() + record.owner else next.bookmarks[post].orEmpty() - record.owner)) }
                "following" -> if (!deleted) next = next.copy(following = next.following + (record.owner to payload.getValue("ids").jsonArray.map { it.jsonPrimitive.content }.toSet()))
                "message" -> { next = next.copy(messages = next.messages.filterNot { it.id == key }); if (!deleted) next = next.copy(messages = next.messages + Codec.decodeFromJsonElement<Message>(payload)) }
                "messageReaction" -> if (!deleted) { val id = payload.getValue("messageID").jsonPrimitive.content; val emoji = payload["emoji"]?.jsonPrimitive?.content.orEmpty(); next = next.copy(messages = next.messages.map { if (it.id == id) it.copy(reactions = if (emoji.isEmpty()) it.reactions - record.owner else it.reactions + (record.owner to emoji)) else it }) }
                "commentReaction" -> if (!deleted) { val post = payload.getValue("postID").jsonPrimitive.content; val id = payload.getValue("commentID").jsonPrimitive.content; val liked = payload["liked"]?.jsonPrimitive?.booleanOrNull == true; next = next.copy(comments = next.comments + (post to next.comments[post].orEmpty().map { if (it.id == id) it.copy(likes = if (liked) it.likes + record.owner else it.likes - record.owner) else it })) }
                "commentPin" -> if (!deleted) { val post = payload.getValue("postID").jsonPrimitive.content; val id = payload["commentID"]?.jsonPrimitive?.contentOrNull; next = next.copy(comments = next.comments + (post to next.comments[post].orEmpty().map { it.copy(pinned = it.id == id) })) }
                "preferences" -> if (!deleted && record.owner == owner) next = next.copy(studios = next.studios + (owner to Codec.decodeFromJsonElement<Studio>(payload)))
            }
        }
        commit(next.copy(cursors = next.cursors + (owner to cursor)))
    }
    fun acknowledge(sent: List<ResourceRecord>) { val set = sent.toSet(); commit(state.value.copy(outbox = state.value.outbox.filterNot { it in set })) }
    suspend fun export(): ByteArray = withContext(Dispatchers.IO) { Codec.encodeToString(state.value.copy(outbox = emptyList())).toByteArray() }

    fun writeBackup(output: java.io.OutputStream) {
        val snapshot = state.value
        java.util.zip.ZipOutputStream(output).use { zip ->
            zip.putNextEntry(java.util.zip.ZipEntry("state.json")); zip.write(Codec.encodeToString(snapshot.copy(outbox = emptyList(), cursors = emptyMap())).toByteArray()); zip.closeEntry()
            mediaDirectory.listFiles().orEmpty().filter { it.isFile }.forEach { file ->
                zip.putNextEntry(java.util.zip.ZipEntry("media/${file.name}")); file.inputStream().use { it.copyTo(zip) }; zip.closeEntry()
            }
        }
    }

    suspend fun restoreBackup(input: java.io.InputStream) {
        val ownerBefore = state.value.activeID
        val restored = withContext(Dispatchers.IO) {
            val staging = File(context.cacheDir, "restore-${newId()}").apply { mkdirs() }
            val added = mutableListOf<File>()
            try {
                var total = 0L; var entries = 0
                val maximum = (context.filesDir.usableSpace - 32L * 1024 * 1024).coerceAtLeast(0)
                java.util.zip.ZipInputStream(input).use { zip ->
                    while (true) {
                        val entry = zip.nextEntry ?: break
                        require(++entries <= 10000) { "Забагато файлів у копії." }
                        val name = entry.name
                        require(name == "state.json" || (name.startsWith("media/") && name.removePrefix("media/").let { it.isNotBlank() && File(it).name == it && !it.contains("..") && !it.contains('\\') })) { "Некоректний шлях у копії." }
                        val target = File(staging, name); target.parentFile?.mkdirs()
                        target.outputStream().use { output ->
                            val buffer = ByteArray(65536)
                            while (true) { val read = zip.read(buffer); if (read < 0) break; total += read; require(total <= maximum) { "Недостатньо місця для відновлення." }; output.write(buffer, 0, read) }
                        }
                        zip.closeEntry()
                    }
                }
                val stateFile = File(staging, "state.json"); require(stateFile.isFile && stateFile.length() <= 32 * 1024 * 1024) { "Некоректна копія стану." }
                val backup = Codec.decodeFromString<AppState>(stateFile.readText())
                require(backup.schema == 1 && backup.profiles.map { it.id }.distinct().size == backup.profiles.size && backup.profiles.map { it.handle.lowercase() }.distinct().size == backup.profiles.size)
                require(backup.activeID == null || backup.profiles.any { it.id == backup.activeID })
                val names = File(staging, "media").listFiles().orEmpty().associate { it.name to "restored-${newId()}.${it.extension}" }
                fun mapped(name: String): String = names[name] ?: name.also { require(it in setOf("bunny", "sintel", "bunny.mp4", "sintel.mp4")) { "У копії відсутній медіафайл." } }
                val result = backup.copy(
                    profiles = backup.profiles.map { it.copy(portraitFile = it.portraitFile?.let(::mapped), bannerFile = it.bannerFile?.let(::mapped)) },
                    posts = backup.posts.map { it.copy(file = mapped(it.file), media = it.media.map { media -> media.copy(file = mapped(media.file), remoteURL = null) }) },
                    messages = backup.messages.map { it.copy(attachmentFile = it.attachmentFile?.let(::mapped)) },
                    outbox = emptyList(), cursors = emptyMap()
                )
                names.forEach { (old, fresh) -> val target = File(mediaDirectory, fresh); File(staging, "media/$old").copyTo(target); added += target }
                result
            } catch (failure: Exception) { added.forEach(File::delete); throw failure }
            finally { staging.deleteRecursively() }
        }
        check(state.value.activeID == ownerBefore) { "Акаунт змінився під час відновлення." }
        writable = true; commit(restored)
    }
}
