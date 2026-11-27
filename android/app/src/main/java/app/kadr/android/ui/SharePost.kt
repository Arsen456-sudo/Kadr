package app.kadr.android.ui

import android.content.ClipData
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import app.kadr.android.data.LocalRepository
import app.kadr.android.data.Post
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Share original files with temporary read grants, including bundled demo media. */
suspend fun sharePost(context: Context, repository: LocalRepository, post: Post) {
    val uris = withContext(Dispatchers.IO) {
        post.items.map { item ->
            val uri = repository.mediaUri(item)
            if (uri.scheme == "https") uri else {
                val file = if (uri.scheme == "asset") {
                    val folder = File(context.cacheDir, "exports").apply { mkdirs() }
                    File(folder, item.file.substringAfterLast('/')).also { target ->
                        context.assets.open(uri.path!!.trimStart('/')).use { input -> target.outputStream().use(input::copyTo) }
                    }
                } else File(requireNotNull(uri.path))
                require(file.isFile) { "Оригінал ще не завантажено" }
                FileProvider.getUriForFile(context, "${context.packageName}.files", file)
            }
        }
    }
    val mime = when {
        post.items.all { it.kind == "photo" } -> "image/*"
        post.items.all { it.kind == "video" } -> "video/*"
        else -> "*/*"
    }
    val intent = Intent(if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE).setType(mime)
        .putExtra(Intent.EXTRA_TEXT, post.caption).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    if (uris.size == 1) intent.putExtra(Intent.EXTRA_STREAM, uris.first()) else intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
    intent.clipData = ClipData.newRawUri("Кадр", uris.first()).apply { uris.drop(1).forEach { addItem(ClipData.Item(it)) } }
    context.startActivity(Intent.createChooser(intent, "Поділитися"))
}
