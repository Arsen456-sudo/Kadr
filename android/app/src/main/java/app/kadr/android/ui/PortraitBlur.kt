package app.kadr.android.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.*
import androidx.compose.ui.layout.ContentScale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** A small cached-in-composition bitmap gives Android 8–11 the same gradual portrait blur. */
@Composable internal fun PortraitBlur(file: File?, bytes: ByteArray?, modifier: Modifier = Modifier) {
    val bitmap by produceState<Bitmap?>(null, file?.path, bytes) {
        value = withContext(Dispatchers.Default) {
            runCatching {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                if (file != null) BitmapFactory.decodeFile(file.path, bounds) else if (bytes != null) BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth <= 0) return@runCatching null
                val options = BitmapFactory.Options().apply { inSampleSize = (maxOf(bounds.outWidth, bounds.outHeight) / 320).coerceAtLeast(1) }
                val source = if (file != null) BitmapFactory.decodeFile(file.path, options) else BitmapFactory.decodeByteArray(bytes!!, 0, bytes.size, options)
                source ?: return@runCatching null
                val width = source.width; val height = source.height
                var pixels = IntArray(width * height); source.getPixels(pixels, 0, width, 0, 0, width, height); source.recycle()
                val radius = 7
                repeat(3) {
                    for (horizontal in listOf(true, false)) {
                        val output = IntArray(pixels.size)
                        val lines = if (horizontal) height else width
                        val length = if (horizontal) width else height
                        fun index(line: Int, position: Int) = if (horizontal) line * width + position.coerceIn(0, length - 1) else position.coerceIn(0, length - 1) * width + line
                        for (line in 0 until lines) {
                            var red = 0; var green = 0; var blue = 0
                            fun add(position: Int, sign: Int) { val color = pixels[index(line, position)]; red += ((color shr 16) and 255) * sign; green += ((color shr 8) and 255) * sign; blue += (color and 255) * sign }
                            for (offset in -radius..radius) add(offset, 1)
                            for (position in 0 until length) {
                                val divisor = radius * 2 + 1
                                output[index(line, position)] = (255 shl 24) or ((red / divisor) shl 16) or ((green / divisor) shl 8) or (blue / divisor)
                                add(position - radius, -1); add(position + radius + 1, 1)
                            }
                        }
                        pixels = output
                    }
                }
                Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
            }.getOrNull()
        }
    }
    bitmap?.let { image ->
        Image(image.asImageBitmap(), null, modifier.fillMaxSize().graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.drawWithCache {
            val mask = Brush.verticalGradient(0f to Color.Transparent, .45f to Color.Transparent, .88f to Color.Black, 1f to Color.Black)
            onDrawWithContent { drawContent(); drawRect(mask, blendMode = BlendMode.DstIn) }
        }, contentScale = ContentScale.Crop)
    }
}
