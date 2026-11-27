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
@Composable internal fun ExpandingIslandAction(icon: ImageVector, label: String, actions: List<IslandMenuAction>) {
    val visible = remember { MutableTransitionState(false) }
    val transition = rememberTransition(visible, label = "expanding-action")
    val progress = transition.animateFloat(transitionSpec = { tween(460, easing = FastOutSlowInEasing) }, label = "capsule") { if (it) 1f else 0f }
    val density = LocalDensity.current
    val popupOffset = with(density) { IntOffset(-4.dp.roundToPx(), 4.dp.roundToPx()) }
    val popupHeight = (actions.size * 48).dp
    Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
        CircleAction(icon, label, { visible.targetState = true }, visualSize = 40.dp)
        if (visible.currentState || visible.targetState) Popup(alignment = Alignment.TopEnd, offset = popupOffset, onDismissRequest = { visible.targetState = false }, properties = PopupProperties(focusable = true)) {
            Box(Modifier.size(240.dp, popupHeight)) {
                Box(Modifier.matchParentSize().clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { visible.targetState = false })
                Surface(Modifier.fillMaxSize().graphicsLayer {
                    val fraction = progress.value
                    val visibleWidth = 40.dp.toPx() + (size.width - 40.dp.toPx()) * fraction
                    val visibleHeight = 40.dp.toPx() + (size.height - 40.dp.toPx()) * fraction
                    val radius = 20.dp.toPx()
                    clip = true
                    shape = object : Shape {
                        override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
                            Outline.Rounded(RoundRect(size.width - visibleWidth, 0f, size.width, visibleHeight, CornerRadius(radius)))
                    }
                }, shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.onSurface) {
                    Box {
                        Icon(icon, label, Modifier.align(Alignment.TopEnd).padding(10.dp).size(20.dp).graphicsLayer { alpha = 1f - progress.value })
                        Column(Modifier.fillMaxWidth().graphicsLayer { alpha = ((progress.value - .15f) / .85f).coerceIn(0f, 1f) }) {
                            actions.forEach { action ->
                                Surface(onClick = { if (visible.targetState && progress.value > .85f) { visible.targetState = false; action.onClick() } }, shape = RoundedCornerShape(20.dp), color = Color.Transparent) {
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
