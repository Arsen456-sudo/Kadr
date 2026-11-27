package app.kadr.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/** 44 dp visual islands in independent 48 dp touch targets, without a bar surface. */
@Composable internal fun FloatingHeader(title: String, back: (() -> Unit)? = null, actions: @Composable RowScope.() -> Unit = {}) {
    Box(Modifier.fillMaxWidth().height(64.dp)) {
    TopIslandShade(Modifier.offset(y = -WindowInsets.statusBars.asPaddingValues().calculateTopPadding()))
    Row(Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
            if (back != null) CircleAction(Icons.AutoMirrored.Outlined.ArrowBack, "Назад", back, visualSize = 44.dp)
        }
        Text(title, Modifier.weight(1f), textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium)
        Row(Modifier.widthIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp), content = actions)
    }
    }
}

/** Full-size content scrolls beneath the transparent header and system navigation area. */
@Composable internal fun FloatingPage(title: String, back: () -> Unit, content: @Composable (PaddingValues) -> Unit) {
    val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 80.dp
    val bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 16.dp
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        content(PaddingValues(start = 16.dp, top = top, end = 16.dp, bottom = bottom))
        Box(Modifier.fillMaxWidth().statusBarsPadding()) { FloatingHeader(title, back) }
    }
}

/** Forward directly to the official expressive segmented list item, without a Card. */
@Composable internal fun IslandListItem(
    headlineContent: @Composable () -> Unit,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    supportingContent: (@Composable () -> Unit)? = null,
    leadingContent: (@Composable () -> Unit)? = null,
    trailingContent: (@Composable () -> Unit)? = null,
    index: Int = 0,
    count: Int = 1,
) {
    SegmentedListItem(onClick = onClick, shapes = ListItemDefaults.segmentedShapes(index, count), modifier = modifier.fillMaxWidth(), supportingContent = supportingContent, leadingContent = leadingContent, trailingContent = trailingContent,
        colors = ListItemDefaults.segmentedColors(contentColor = MaterialTheme.colorScheme.onSurface, leadingContentColor = MaterialTheme.colorScheme.onSurfaceVariant, trailingContentColor = MaterialTheme.colorScheme.onSurfaceVariant, supportingContentColor = MaterialTheme.colorScheme.onSurfaceVariant), content = headlineContent)
}
