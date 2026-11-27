package app.kadr.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Native toggle surfaces include the complete destination inside their selected container. */
@Composable fun AppNavigation(selectedTab: Int, select: (Int) -> Unit, modifier: Modifier = Modifier, profileColor: Color? = null) {
    val ink = profileColor?.let { if (it.luminance() > .42f) Color.Black else Color.White } ?: MaterialTheme.colorScheme.onSurfaceVariant
    val container = profileColor?.let { lerp(it, ink, .10f) } ?: MaterialTheme.colorScheme.surfaceContainer
    val indicator = profileColor?.let { lerp(it, ink, .20f) } ?: MaterialTheme.colorScheme.secondaryContainer
    Surface(modifier.requiredHeight(60.dp).testTag("bottom-navigation"), shape = CircleShape, color = container, shadowElevation = 3.dp) {
        Row(Modifier.fillMaxWidth().padding(6.dp).selectableGroup(), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            val labels = listOf("Стрічка", "Додати", "Вхідні", "Профіль")
            val icons = listOf(Icons.Outlined.Home, Icons.Outlined.Add, Icons.Outlined.Inbox, Icons.Outlined.Person)
            labels.forEachIndexed { index, label ->
                FilledTonalToggleButton(
                    checked = selectedTab == index,
                    onCheckedChange = { select(index) },
                    modifier = Modifier.weight(1f).height(48.dp).testTag("tab:$index").semantics { role = Role.Tab; selected = selectedTab == index },
                    contentPadding = PaddingValues(horizontal = 2.dp, vertical = 2.dp),
                    shapes = ToggleButtonDefaults.shapesFor(48.dp).copy(shape = CircleShape, checkedShape = CircleShape, pressedShape = CircleShape),
                    colors = FilledTonalToggleButtonDefaults.colors(containerColor = Color.Transparent, contentColor = ink, checkedContainerColor = indicator, checkedContentColor = if (profileColor != null) ink else MaterialTheme.colorScheme.onSecondaryContainer)
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Icon(icons[index], null, Modifier.size(26.dp))
                        Text(label, maxLines = 1, softWrap = false, fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }
    }
}
