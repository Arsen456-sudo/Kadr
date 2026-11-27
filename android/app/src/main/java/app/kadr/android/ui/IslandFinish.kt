package app.kadr.android.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.unit.dp

/** A crisp one-dp bevel; the owning Material surface draws it on its actual animated shape. */
internal fun islandRim(): BorderStroke = BorderStroke(1.dp, Brush.linearGradient(listOf(
    Color.White.copy(alpha = .26f), Color.White.copy(alpha = .07f),
    Color.Black.copy(alpha = .28f), Color.White.copy(alpha = .12f))))

private fun edgeStops(color: Color, top: Boolean): Array<Pair<Float, Color>> = Array(25) { index ->
    val t = index / 24f
    val s = t * t * (3f - 2f * t)
    t to lerp(color, Color.Black, .22f).copy(alpha = .95f * if (top) 1f - s else s)
}

@Composable internal fun TopIslandShade(modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.background) {
    val tint by animateColorAsState(color, MaterialTheme.motionScheme.defaultEffectsSpec(), label = "top-shade-color")
    val extent = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 54.dp
    Box(modifier.fillMaxWidth().wrapContentHeight(align = Alignment.Top, unbounded = true).height(extent).drawWithCache {
        val gradient = Brush.verticalGradient(*edgeStops(tint, true), endY = size.height)
        onDrawBehind { drawRect(gradient) }
    })
}

@Composable internal fun BottomIslandShade(modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.background, controlHeight: androidx.compose.ui.unit.Dp = 70.dp) {
    val tint by animateColorAsState(color, MaterialTheme.motionScheme.defaultEffectsSpec(), label = "bottom-shade-color")
    val extent = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + controlHeight
    Box(modifier.fillMaxWidth().height(extent).drawWithCache {
        val gradient = Brush.verticalGradient(*edgeStops(tint, false), endY = size.height)
        onDrawBehind { drawRect(gradient) }
    })
}

internal fun Modifier.composerShade(color: Color): Modifier = drawWithCache {
    val gradient = Brush.verticalGradient(*edgeStops(color, false), startY = 12.dp.toPx(), endY = size.height)
    onDrawBehind { drawRect(gradient, topLeft = Offset(0f, 12.dp.toPx()), size = androidx.compose.ui.geometry.Size(size.width, (size.height - 12.dp.toPx()).coerceAtLeast(0f))) }
}
