@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
package app.kadr.android.ui

import android.content.Intent
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.kadr.android.KadrViewModel
import app.kadr.android.data.*
import coil3.compose.AsyncImage
import java.io.File

/** One scrolling coordinate space. The native sticky header never swaps or changes width. */
@Composable fun ProfileScreen(vm: KadrViewModel, state: AppState, profileID: String?, onAccount: () -> Unit, open: (String) -> Unit, onPost: (Post) -> Unit, onBack: () -> Unit) {
    val profile = state.profiles.find { it.id == profileID }
    if (profile == null) {
        Scaffold(topBar = { CenterAlignedTopAppBar(title = { Text("Профіль") }) }) { padding ->
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                EmptyMessage("Твоя історія починається тут", "Створи профіль, щоб публікувати, зберігати та спілкуватися.", "Створити акаунт", onAccount)
            }
        }
        return
    }
    val own = profile.id == state.activeID
    val context = LocalContext.current
    var edit by remember(profile.id) { mutableStateOf(false) }
    var category by rememberSaveable(profile.id) { mutableIntStateOf(0) }
    val list = rememberLazyListState()
    val photo = profile.portraitFile?.let { File(vm.repository.mediaDirectory, it) }
    val background = ProfilePalette(photo, MaterialTheme.colorScheme.background)
    val ink = if (background.luminance() > .42f) Color.Black else Color.White
    val island = lerp(background, ink, .10f)
    val selectedIsland = lerp(background, ink, .20f)
    val islandScheme = MaterialTheme.colorScheme.copy(
        background = background, onBackground = ink, onSurface = ink, onSurfaceVariant = ink.copy(alpha = .78f),
        surface = background, surfaceContainerLow = lerp(background, ink, .05f),
        surfaceContainer = island, surfaceContainerHigh = island,
        primary = ink, onPrimary = background, primaryContainer = selectedIsland, onPrimaryContainer = ink,
        secondaryContainer = selectedIsland, onSecondaryContainer = ink)
    val image: Any? = photo ?: remember(profile.avatar) { profile.avatar?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() } }
    val appearance = state.studios[profile.id]?.appearance ?: Appearance()
    val mine = remember(state.posts, profile.id, own, appearance.pinnedPosts) {
        state.posts.filter { it.authorID == profile.id && !it.isDraft && (own || !it.options.onlyMe) }
            .sortedWith(compareBy<Post> { appearance.pinnedPosts.indexOf(it.id).takeIf { index -> index >= 0 } ?: Int.MAX_VALUE }.thenByDescending { it.createdAt })
    }
    val posts = remember(state.posts, state.bookmarks, state.likes, state.comments, state.activeID, category, mine) {
        val all = (state.posts + AppState.samples).filter { !it.isDraft && (!it.options.onlyMe || it.authorID == state.activeID) }
        when (category) {
            1 -> mine
            2 -> if (own) all.filter { state.activeID in state.bookmarks[it.id].orEmpty() } else emptyList()
            3 -> if (own) all.filter { state.activeID in state.likes[it.id].orEmpty() } else emptyList()
            4 -> if (own) all.filter { state.comments[it.id].orEmpty().any { comment -> comment.authorID == state.activeID } } else emptyList()
            else -> emptyList()
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> uri?.let { vm.act { setPhoto(it) } } }
    MaterialTheme(colorScheme = islandScheme) {
    val headerHeight = if (image == null) 224.dp else 360.dp
    val topInset = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 64.dp
    val headerPx = with(LocalDensity.current) { headerHeight.toPx() }
    val fullHeaderPx = with(LocalDensity.current) { (headerHeight + topInset).toPx() }
    Box(Modifier.fillMaxSize().background(background)) {
        Box(Modifier.fillMaxWidth().height(headerHeight + topInset).graphicsLayer {
            translationY = -when (list.firstVisibleItemIndex) {
                0 -> list.firstVisibleItemScrollOffset.toFloat()
                1 -> headerPx + list.firstVisibleItemScrollOffset
                else -> fullHeaderPx
            }
        }) {
            if (image != null) AsyncImage(image, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            else Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(MaterialTheme.colorScheme.primaryContainer, background))))
            if (image != null) PortraitBlur(photo, image as? ByteArray, Modifier.matchParentSize())
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to Color.Transparent, .4f to Color.Transparent, .72f to background.copy(alpha = .5f), 1f to background)))
        }
        LazyColumn(Modifier.fillMaxSize().padding(top = topInset).navigationBarsPadding().testTag("profile-scroll"), state = list, contentPadding = PaddingValues(bottom = 120.dp)) {
            item(key = "identity") {
                Box(Modifier.fillMaxWidth().height(headerHeight)) {
                    Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(profile.name, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text("@${profile.handle}", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            item(key = "about") {
                Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (profile.bio.isNotBlank()) Text(profile.bio, style = MaterialTheme.typography.bodyLarge)
                    if (appearance.introduction.isNotBlank()) Text(appearance.introduction, style = MaterialTheme.typography.bodyMedium)
                    appearance.links.filter { it.startsWith("https://") }.forEach { link ->
                        TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link))) }, contentPadding = PaddingValues(0.dp), shapes = ButtonDefaults.shapes()) { Icon(Icons.Outlined.Link, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text(link, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    }
                }
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    listOf("Публікації" to mine.size, "Підписники" to state.following.values.count { profile.id in it }, "Підписки" to state.following[profile.id].orEmpty().size).forEachIndexed { index, (label, count) ->
                        TextButton(onClick = { if (index == 0) category = 1 else open((if (index == 1) "followers:" else "following:") + profile.id) }, modifier = Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 4.dp, vertical = 12.dp), shapes = ButtonDefaults.shapes()) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) { Text("$count", style = MaterialTheme.typography.titleLarge); Text(label, maxLines = 1, softWrap = false, style = MaterialTheme.typography.labelMedium) }
                        }
                    }
                }
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (own) ProfilePill(Icons.Outlined.Tune, "Студія", { open("studio") }, Modifier.weight(1f))
                    else {
                        val follows = profile.id in state.following[state.activeID].orEmpty()
                        ProfilePill(if (follows) Icons.Outlined.PersonRemove else Icons.Outlined.PersonAdd, if (follows) "Стежу" else "Стежити", { if (state.active == null) onAccount() else vm.act { follow(profile.id) } }, Modifier.weight(1f))
                        if (follows) ProfilePill(Icons.Outlined.ChatBubbleOutline, "Написати", { open("chat:${profile.id}") }, Modifier.weight(1f))
                    }
                    CircleAction(Icons.Outlined.Share, "Поділитися", { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "kadr://profile/${profile.handle}"), "Поділитися")) })
                    ExpandingIslandAction(Icons.Outlined.MoreHoriz, "Ще", listOf(
                        if (own) IslandMenuAction("Вийти з акаунта", Icons.Outlined.Logout) { vm.act { activate(null) } }
                        else IslandMenuAction("Заблокувати", Icons.Outlined.Block) { vm.act { requireAccount(); changeStudio { it.copy(preferences = it.preferences.copy(blocked = it.preferences.blocked + profile.id)) } }; onBack() }))
                }
            }
            stickyHeader(key = "profile-sections") {
                Surface(color = background, modifier = Modifier.fillMaxWidth()) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).selectableGroup().testTag("profile-categories"), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        val icons = listOf(Icons.Outlined.Person, Icons.Outlined.GridView, Icons.Outlined.BookmarkBorder, Icons.Outlined.FavoriteBorder, Icons.Outlined.ChatBubbleOutline).take(if (own) 5 else 2)
                        icons.forEachIndexed { index, icon ->
                            ToggleButton(checked = category == index, onCheckedChange = { category = index }, modifier = Modifier.weight(1f).heightIn(min = 48.dp).testTag("profile-category:$index"), contentPadding = PaddingValues(0.dp), shapes = when (index) { 0 -> ButtonGroupDefaults.connectedLeadingButtonShapes(); icons.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes(); else -> ButtonGroupDefaults.connectedMiddleButtonShapes() }) {
                                Icon(icon, listOf("Профіль", "Публікації", "Збережені", "Уподобання", "Коментарі")[index], Modifier.size(24.dp))
                            }
                        }
                    }
                }
            }
            if (category == 0) {
                item(key = "dashboard") {
                    val rows = buildList {
                        add(Triple(Icons.Outlined.GridView, "Публікації" to "${mine.size} кадрів · ${mine.sumOf { state.likes[it.id]?.size ?: 0 }} уподобань", "posts"))
                        add(Triple(Icons.Outlined.PeopleOutline, "Спільнота" to "${state.following.values.count { profile.id in it }} підписників", "people"))
                        if (own) {
                            add(Triple(Icons.Outlined.BookmarkBorder, "Бібліотека" to "${state.bookmarks.values.count { state.activeID in it }} збережених", "saved"))
                            add(Triple(Icons.Outlined.Palette, "Оформлення" to "Фото та акценти", "studio"))
                            add(Triple(Icons.Outlined.Settings, "Налаштування" to "Приватність і відтворення", "settings"))
                        }
                    }
                    Card(Modifier.fillMaxWidth().padding(16.dp), shape = MaterialTheme.shapes.extraLarge, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                        rows.forEachIndexed { index, (icon, text, target) ->
                            ListItem(headlineContent = { Text(text.first) }, supportingContent = { Text(text.second) }, leadingContent = { Icon(icon, null) }, trailingContent = { Icon(Icons.Outlined.ChevronRight, null) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent), modifier = Modifier.clickable { when (target) { "posts" -> category = 1; "saved" -> category = 2; "people" -> open("followers:${profile.id}"); else -> open(target) } })
                            if (index < rows.lastIndex) HorizontalDivider(Modifier.padding(start = 56.dp, end = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .4f))
                        }
                    }
                }
            } else if (posts.isEmpty()) item { EmptyMessage("Поки немає кадрів", if (own) "Тут будуть твої публікації та добірки." else "Автор ще не додав публікацій.") }
            else items(posts.chunked(3), key = { it.first().id }) { row ->
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { post ->
                        Box(Modifier.weight(1f).aspectRatio(.74f).clip(MaterialTheme.shapes.medium).clickable { onPost(post) }) {
                            MediaPoster(post.items[post.options.coverIndex.coerceIn(0, post.items.lastIndex)], vm.repository, Modifier.fillMaxSize(), atSeconds = post.extras.coverTime)
                            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .5f)), startY = 140f)))
                            Icon(if (post.photo) Icons.Outlined.PhotoLibrary else Icons.Outlined.PlayArrow, if (post.photo) "Фото · ${post.items.size}" else "Відео", Modifier.align(Alignment.BottomStart).padding(8.dp).size(20.dp), tint = Color.White)
                        }
                    }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            CircleAction(if (own) Icons.Outlined.QrCode else Icons.AutoMirrored.Outlined.ArrowBack, if (own) "QR-код" else "Назад", { if (own) open("qr:${profile.id}") else onBack() })
            Text("Профіль", Modifier.weight(1f), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium, maxLines = 1)
            if (own) ExpandingIslandAction(Icons.Outlined.Edit, "Редагувати", listOf(
                IslandMenuAction("Змінити фото", Icons.Outlined.AddPhotoAlternate) { picker.launch("image/*") },
                IslandMenuAction("Імʼя та @нікнейм", Icons.Outlined.Person) { edit = true }))
            else CircleAction(Icons.Outlined.QrCode, "QR-код", { open("qr:${profile.id}") })
        }
    }
    if (edit) AccountDialog(vm, state, { edit = false }, edit = true)
    }
}

@Composable private fun ProfilePill(icon: ImageVector, text: String, click: () -> Unit, modifier: Modifier) {
    FilledTonalButton(onClick = click, modifier = modifier.heightIn(min = 48.dp), contentPadding = PaddingValues(horizontal = 12.dp), shapes = ButtonDefaults.shapes()) {
        Icon(icon, null, Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)); Text(text, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
