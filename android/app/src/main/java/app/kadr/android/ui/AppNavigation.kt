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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Native toggle surfaces include the complete destination inside their selected container. */
@Composable fun AppNavigation(selectedTab: Int, select: (Int) -> Unit, modifier: Modifier = Modifier) {
    Surface(modifier.requiredHeight(68.dp).testTag("bottom-navigation"), shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainer, shadowElevation = 3.dp) {
        Row(Modifier.fillMaxWidth().padding(6.dp).selectableGroup(), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            val labels = listOf("Стрічка", "Додати", "Вхідні", "Профіль")
            val icons = listOf(Icons.Outlined.Home, Icons.Outlined.Add, Icons.Outlined.Inbox, Icons.Outlined.Person)
            labels.forEachIndexed { index, label ->
                FilledTonalToggleButton(
                    checked = selectedTab == index,
                    onCheckedChange = { select(index) },
                    modifier = Modifier.weight(1f).height(56.dp).testTag("tab:$index").semantics { role = Role.Tab; selected = selectedTab == index },
                    contentPadding = PaddingValues(horizontal = 2.dp, vertical = 4.dp),
                    shapes = ToggleButtonDefaults.shapesFor(56.dp).copy(shape = CircleShape, checkedShape = CircleShape, pressedShape = CircleShape),
                    colors = FilledTonalToggleButtonDefaults.colors(containerColor = Color.Transparent, contentColor = MaterialTheme.colorScheme.onSurfaceVariant, checkedContainerColor = MaterialTheme.colorScheme.secondaryContainer, checkedContentColor = MaterialTheme.colorScheme.onSecondaryContainer)
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Icon(icons[index], null, Modifier.size(28.dp))
                        Text(label, maxLines = 1, softWrap = false, fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }
    }
}
