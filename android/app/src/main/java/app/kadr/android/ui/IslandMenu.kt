package app.kadr.android.ui

import androidx.compose.animation.*
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.rememberTransition
import androidx.compose.animation.core.animateDp
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties

internal data class IslandMenuAction(val title: String, val icon: ImageVector, val onClick: () -> Unit)

/** A native popup anchored to the button's top edge, expanding from that button. */
@Composable internal fun IslandMenu(expanded: Boolean, dismiss: () -> Unit, actions: List<IslandMenuAction>) {
    val visible = remember { MutableTransitionState(false) }
    visible.targetState = expanded
    val spatial = MaterialTheme.motionScheme.fastSpatialSpec<Dp>()
    val effects = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    val transition = rememberTransition(visible, label = "island-menu")
    val width by transition.animateDp(transitionSpec = { spatial }, label = "width") { if (it) 240.dp else 48.dp }
    val height by transition.animateDp(transitionSpec = { spatial }, label = "height") { if (it) (actions.size * 48).dp else 48.dp }
    val alpha by transition.animateFloat(transitionSpec = { effects }, label = "opacity") { if (it) 1f else 0f }
    if (visible.currentState || visible.targetState) {
        Popup(alignment = Alignment.TopEnd, onDismissRequest = dismiss, properties = PopupProperties(focusable = true)) {
                Surface(modifier = Modifier.width(width).height(height).graphicsLayer { this.alpha = alpha }, shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.onSurface, shadowElevation = 6.dp) {
                    Column(Modifier.fillMaxWidth()) {
                        actions.forEach { action ->
                            Surface(onClick = { dismiss(); action.onClick() }, shape = RoundedCornerShape(24.dp), color = androidx.compose.ui.graphics.Color.Transparent) {
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
