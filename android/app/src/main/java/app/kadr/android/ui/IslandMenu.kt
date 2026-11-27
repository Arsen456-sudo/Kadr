package app.kadr.android.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties

internal data class IslandMenuAction(val title: String, val icon: ImageVector, val onClick: () -> Unit)

/** The popup window and text layout stay fixed. Only its GPU clipping outline changes. */
@Composable internal fun ExpandingIslandAction(icon: ImageVector, label: String, actions: List<IslandMenuAction>, visualSize: Dp = 44.dp) {
    val visible = remember { MutableTransitionState(false) }
    val transition = rememberTransition(visible, label = "expanding-action")
    val progress = transition.animateFloat(transitionSpec = { tween(460, easing = FastOutSlowInEasing) }, label = "capsule") { if (it) 1f else 0f }
    val density = LocalDensity.current
    val popupOffset = with(density) { IntOffset(-((48.dp - visualSize) / 2).roundToPx(), ((48.dp - visualSize) / 2).roundToPx()) }
    val popupHeight = (actions.size * 48).dp
    Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
        CircleAction(icon, label, { visible.targetState = true }, visualSize = visualSize)
        if (visible.currentState || visible.targetState) Popup(alignment = Alignment.TopEnd, offset = popupOffset, onDismissRequest = { visible.targetState = false }, properties = PopupProperties(focusable = true)) {
            Box(Modifier.size(240.dp, popupHeight)) {
                Box(Modifier.matchParentSize().clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { visible.targetState = false })
                Surface(Modifier.fillMaxSize().graphicsLayer {
                    val fraction = progress.value
                    val visibleWidth = visualSize.toPx() + (size.width - visualSize.toPx()) * fraction
                    val visibleHeight = visualSize.toPx() + (size.height - visualSize.toPx()) * fraction
                    val radius = (visualSize / 2).toPx()
                    clip = true
                    shape = object : Shape {
                        override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
                            Outline.Rounded(RoundRect(size.width - visibleWidth, 0f, size.width, visibleHeight, CornerRadius(radius)))
                    }
                }.drawWithCache {
                    val stroke = 1.dp.toPx()
                    val brush = Brush.verticalGradient(listOf(Color.White.copy(alpha = .26f), Color.White.copy(alpha = .07f), Color.Black.copy(alpha = .28f), Color.White.copy(alpha = .12f)))
                    onDrawWithContent {
                        drawContent()
                        val fraction = progress.value
                        val width = visualSize.toPx() + (size.width - visualSize.toPx()) * fraction
                        val height = visualSize.toPx() + (size.height - visualSize.toPx()) * fraction
                        drawRoundRect(brush, topLeft = Offset(size.width - width + stroke / 2, stroke / 2), size = Size(width - stroke, height - stroke), cornerRadius = CornerRadius((visualSize / 2).toPx() - stroke / 2), style = Stroke(stroke))
                    }
                }, shape = RoundedCornerShape(visualSize / 2), color = MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.onSurface) {
                    Box {
                        Icon(icon, label, Modifier.align(Alignment.TopEnd).padding(11.dp).size(22.dp).graphicsLayer { alpha = 1f - progress.value })
                        Column(Modifier.fillMaxWidth().graphicsLayer { alpha = ((progress.value - .15f) / .85f).coerceIn(0f, 1f) }) {
                            actions.forEach { action ->
                                Surface(onClick = { if (visible.targetState && progress.value > .85f) { visible.targetState = false; action.onClick() } }, shape = RoundedCornerShape(visualSize / 2), color = Color.Transparent) {
                                    Row(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Icon(action.icon, null, Modifier.size(22.dp))
                                        Text(action.title, style = MaterialTheme.typography.labelLarge, maxLines = 1, softWrap = false)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
