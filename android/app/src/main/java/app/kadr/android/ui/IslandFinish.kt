package app.kadr.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.unit.dp

/** Vertical coordinates keep lighting identical on narrow circles and wide capsules. */
internal fun islandRimBrush(surface: Color, height: Float = Float.POSITIVE_INFINITY): Brush = Brush.verticalGradient(listOf(
    lerp(Color.White, surface, .04f).copy(alpha = .20f),
    lerp(Color.White, surface, .04f).copy(alpha = .035f),
    lerp(Color.Black, surface, .04f).copy(alpha = .20f),
    lerp(Color.White, surface, .04f).copy(alpha = .075f)), endY = height)

@Composable internal fun islandRim(surface: Color = MaterialTheme.colorScheme.surfaceContainerHigh): BorderStroke =
    BorderStroke(.9.dp, islandRimBrush(surface))

/** Neutral transparency shades the actual pixels underneath, retaining their live hue. */
private fun edgeStops(top: Boolean): Array<Pair<Float, Color>> = Array(41) { index ->
    val t = index / 40f
    val u = if (top) 1f - t else t
    t to Color.Black.copy(alpha = .48f * u * u * (2f - u))
}

@Composable internal fun TopIslandShade(modifier: Modifier = Modifier) {
    val extent = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 54.dp
    Box(modifier.fillMaxWidth().wrapContentHeight(align = Alignment.Top, unbounded = true).height(extent).drawWithCache {
        val gradient = Brush.verticalGradient(*edgeStops(true), endY = size.height)
        onDrawBehind { drawRect(gradient) }
    })
}

@Composable internal fun BottomIslandShade(modifier: Modifier = Modifier, controlHeight: androidx.compose.ui.unit.Dp = 70.dp) {
    val extent = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + controlHeight
    Box(modifier.fillMaxWidth().height(extent).drawWithCache {
        val gradient = Brush.verticalGradient(*edgeStops(false), endY = size.height)
        onDrawBehind { drawRect(gradient) }
    })
}

internal fun Modifier.composerShade(): Modifier = drawWithCache {
    val gradient = Brush.verticalGradient(*edgeStops(false), startY = 12.dp.toPx(), endY = size.height)
    onDrawBehind { drawRect(gradient, topLeft = Offset(0f, 12.dp.toPx()), size = androidx.compose.ui.geometry.Size(size.width, (size.height - 12.dp.toPx()).coerceAtLeast(0f))) }
}
