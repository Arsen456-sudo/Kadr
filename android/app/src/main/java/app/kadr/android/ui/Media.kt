package app.kadr.android.ui

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import app.kadr.android.data.*
import coil3.compose.AsyncImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object Posters {
    private val cache = object : LruCache<String, Bitmap>(24 * 1024 * 1024) { override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount }
    suspend fun load(context: Context, uri: Uri, atSeconds: Double = .5): Bitmap? = withContext(Dispatchers.IO) {
        val key = "$uri#${(atSeconds * 1000000).toLong()}"
        cache[key]?.let { return@withContext it }
        runCatching {
            val reader = MediaMetadataRetriever()
            try {
                if (uri.scheme == "asset") context.assets.openFd(uri.path!!.trimStart('/')).use { reader.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                else reader.setDataSource(context, uri)
                val poster = if (android.os.Build.VERSION.SDK_INT >= 27) reader.getScaledFrameAtTime((atSeconds * 1000000).toLong(), MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 640, 640)
                    else reader.getFrameAtTime((atSeconds * 1000000).toLong(), MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.let { source -> val scale = minOf(1f, 640f / maxOf(source.width, source.height)); Bitmap.createScaledBitmap(source, (source.width * scale).toInt().coerceAtLeast(1), (source.height * scale).toInt().coerceAtLeast(1), true).also { if (it !== source) source.recycle() } }
                poster?.also { cache.put(key, it) }
            } finally { reader.release() }
        }.getOrNull()
    }
}

@Composable fun MediaPoster(item: PostMedia, repository: LocalRepository, modifier: Modifier = Modifier, scale: ContentScale = ContentScale.Crop, atSeconds: Double = .5) {
    val uri = repository.mediaUri(item)
    if (item.kind == "photo") AsyncImage(model = uri, contentDescription = null, modifier = modifier, contentScale = scale)
    else {
        val context = LocalContext.current
        val bitmap by produceState<Bitmap?>(null, uri, atSeconds) { value = Posters.load(context, uri, atSeconds) }
        bitmap?.let { Image(it.asImageBitmap(), null, modifier, contentScale = scale) } ?: Box(modifier.background(MaterialTheme.colorScheme.surfaceContainerHigh))
    }
}

@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
@Composable fun Video(item: PostMedia, post: Post, repository: LocalRepository, active: Boolean, muted: Boolean, paused: Boolean, modifier: Modifier = Modifier, onTap: () -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val uri = repository.mediaUri(item)
    // Only the current visible page creates a decoder. Adjacent pages show a poster.
    if (!active) { MediaPoster(item, repository, modifier, ContentScale.Fit); return }
    val player = remember(uri) { ExoPlayer.Builder(context).build().apply {
        val media = MediaItem.Builder().setUri(uri).apply {
            if (post.extras.trimStart > 0 || post.extras.trimEnd != null) setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setStartPositionMs((post.extras.trimStart * 1000).toLong()).apply { post.extras.trimEnd?.let { setEndPositionMs((it * 1000).toLong()) } }.build())
        }.build()
        setMediaItem(media); repeatMode = Player.REPEAT_MODE_ONE; prepare()
        repository.state.value.studio.watches[post.id]?.let { seekTo((it.seconds * 1000).toLong()) }
    } }
    val state by repository.state.collectAsStateWithLifecycle()
    val latestPaused by rememberUpdatedState(paused)
    LaunchedEffect(player, muted, paused, state.studio.preferences.playbackRate) { player.volume = if (muted) 0f else 1f; player.setPlaybackSpeed(state.studio.preferences.playbackRate); player.playWhenReady = !paused && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) }
    DisposableEffect(player, lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE) player.pause()
            if (event == Lifecycle.Event.ON_RESUME && !latestPaused) player.play()
        }
        lifecycle.addObserver(observer)
        onDispose {
            val seconds = player.currentPosition / 1000.0; val duration = (player.duration / 1000.0).coerceAtLeast(0.0)
            player.release(); lifecycle.removeObserver(observer)
            if (repository.ready.value) repository.changeStudio { it.copy(watches = it.watches + (post.id to Watch(post.id, seconds, duration))) }
        }
    }
    AndroidView(factory = { PlayerView(it).apply { useController = false; resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT; setBackgroundColor(android.graphics.Color.TRANSPARENT); setShutterBackgroundColor(android.graphics.Color.TRANSPARENT); this.player = player; setOnClickListener { onTap() } } }, modifier = modifier, update = { it.player = player; it.setOnClickListener { onTap() } })
}

@Composable fun PostMediaView(post: Post, repository: LocalRepository, active: Boolean, muted: Boolean, paused: Boolean, modifier: Modifier = Modifier, onTap: () -> Unit = {}) {
    val collage = post.extras.albumLayout == "collage" && post.items.all { it.kind == "photo" }
    val count = if (collage) (post.items.size + 3) / 4 else post.items.size
    val pages = androidx.compose.foundation.pager.rememberPagerState { count }
    Box(modifier.background(Color.Black)) {
        MediaPoster(post.items[(if (collage) pages.currentPage * 4 else pages.currentPage).coerceIn(post.items.indices)], repository, Modifier.matchParentSize().blur(22.dp))
        Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = 0.30f)))
        androidx.compose.foundation.pager.HorizontalPager(pages, Modifier.fillMaxSize(), userScrollEnabled = count > 1) { page ->
            if (collage) {
                val items = post.items.drop(page * 4).take(4)
                Column(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(post.extras.collageGap.dp)) {
                    items.chunked(2).forEach { row -> Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(post.extras.collageGap.dp)) {
                        row.forEach { item -> AsyncImage(repository.mediaUri(item), post.caption, Modifier.weight(1f).fillMaxHeight(), contentScale = ContentScale.Crop) }
                        if (row.size == 1) Spacer(Modifier.weight(1f))
                    } }
                }
            } else {
                val item = post.items[page]
                if (item.kind == "photo") AsyncImage(model = repository.mediaUri(item), contentDescription = post.extras.photoCaptions[page.toString()] ?: post.caption, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize().clickable(onClick = onTap))
                else Video(item, post, repository, active && page == pages.currentPage, muted, paused, Modifier.fillMaxSize(), onTap)
            }
        }
        if (count > 1) Surface(Modifier.align(androidx.compose.ui.Alignment.TopEnd).padding(16.dp), shape = MaterialTheme.shapes.large, color = Color.Black.copy(alpha = .5f)) { Text("${pages.currentPage + 1}/$count", Modifier.padding(horizontal = 12.dp, vertical = 6.dp), color = Color.White) }
    }
}
