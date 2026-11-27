package app.kadr.android.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties

internal data class IslandMenuAction(val title: String, val icon: ImageVector, val onClick: () -> Unit)

/** One opaque capsule throughout the transition, sharing the button's top and trailing edge. */
@Composable internal fun ExpandingIslandAction(icon: ImageVector, label: String, actions: List<IslandMenuAction>) {
    val visible = remember { MutableTransitionState(false) }
    val transition = rememberTransition(visible, label = "expanding-action")
    val width by transition.animateDp(transitionSpec = { tween(460, easing = FastOutSlowInEasing) }, label = "width") { if (it) 240.dp else 48.dp }
    val height by transition.animateDp(transitionSpec = { tween(460, easing = FastOutSlowInEasing) }, label = "height") { if (it) (actions.size * 48).dp else 48.dp }
    val progress by transition.animateFloat(transitionSpec = { tween(420, easing = FastOutSlowInEasing) }, label = "content") { if (it) 1f else 0f }
    val morphing = visible.currentState || visible.targetState
    Box(Modifier.size(48.dp)) {
        // The opaque expanding surface covers the anchor. Keeping it drawn underneath
        // avoids a blank frame while Android attaches or removes the popup window.
        CircleAction(icon, label, { visible.targetState = true })
        if (morphing) Popup(alignment = Alignment.TopEnd, onDismissRequest = { visible.targetState = false }, properties = PopupProperties(focusable = true)) {
            Surface(Modifier.width(width).height(height), shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.onSurface) {
                Box {
                    Icon(icon, label, Modifier.align(Alignment.TopEnd).padding(12.dp).size(24.dp).graphicsLayer { alpha = 1f - progress })
                    Column(Modifier.fillMaxWidth().graphicsLayer { alpha = ((progress - .15f) / .85f).coerceIn(0f, 1f) }) {
                        actions.forEach { action ->
                            Surface(onClick = { visible.targetState = false; action.onClick() }, shape = RoundedCornerShape(24.dp), color = Color.Transparent, enabled = visible.targetState && progress > .85f) {
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
