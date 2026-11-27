@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package app.kadr.android.ui

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.kadr.android.KadrViewModel
import app.kadr.android.data.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable fun KadrApp(vm: KadrViewModel, initialHandle: String?) {
    val state by vm.state.collectAsStateWithLifecycle()
    val ready by vm.repository.ready.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var route by rememberSaveable { mutableStateOf("main") }
    var backStack by rememberSaveable { mutableStateOf(emptyList<String>()) }
    var returning by remember { mutableStateOf(false) }
    var immersive by rememberSaveable { mutableStateOf(false) }
    var auth by rememberSaveable { mutableStateOf(false) }
    var entryPrompt by rememberSaveable { mutableStateOf(true) }
    var comments by remember { mutableStateOf<Post?>(null) }
    var description by remember { mutableStateOf<Post?>(null) }
    var openedPost by remember { mutableStateOf<Post?>(null) }
    var menuPost by remember { mutableStateOf<Post?>(null) }
    val notices = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    fun open(target: String) { if (target != route) { returning = false; backStack = backStack + route; route = target } }
    fun goBack() { returning = true; route = backStack.lastOrNull() ?: "main"; backStack = backStack.dropLast(1) }
    fun account(action: () -> Unit) { if (state.active == null) auth = true else action() }
    KadrTheme(state.studio.appearance.accent) {
        // Load once while the feed is visible; entering Profile reuses the cached palette.
        val ownProfileColor = ProfilePalette(state.active?.portraitFile?.let { java.io.File(vm.repository.mediaDirectory, it) }, MaterialTheme.colorScheme.background)
        val activity = androidx.activity.compose.LocalActivity.current
        val view = LocalView.current
        SideEffect { view.isHapticFeedbackEnabled = state.studio.preferences.haptics }
        DisposableEffect(immersive, activity) {
            val bars = activity?.let { androidx.core.view.WindowCompat.getInsetsController(it.window, view) }
            if (immersive) { bars?.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE; bars?.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars()) }
            else bars?.show(androidx.core.view.WindowInsetsCompat.Type.systemBars())
            onDispose { bars?.show(androidx.core.view.WindowInsetsCompat.Type.systemBars()) }
        }
        val error by vm.repository.error.collectAsStateWithLifecycle()
        val notice by vm.notice.collectAsStateWithLifecycle()
        LaunchedEffect(error, notice) {
            (notice ?: error)?.let { notices.showSnackbar(it); vm.notice.value = null; vm.repository.error.value = null }
        }
        LaunchedEffect(ready, initialHandle) {
            if (ready && initialHandle != null) state.profiles.find { it.handle.equals(initialHandle, true) }?.let { route = "profile:${it.id}" }
        }
        BackHandler(route != "main") { goBack() }
        LaunchedEffect(tab, route) { if (tab != 0 || route != "main") immersive = false }
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            if (!ready) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            else {
                val spatial = MaterialTheme.motionScheme.defaultSpatialSpec<IntOffset>()
                val effects = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
                AnimatedContent(route, transitionSpec = { (slideInHorizontally(spatial) { if (returning) -it / 5 else it / 5 } + fadeIn(effects)) togetherWith (slideOutHorizontally(spatial) { if (returning) it / 5 else -it / 5 } + fadeOut(effects)) }, label = "navigation") { current ->
                    when {
                        current == "main" -> AnimatedContent(tab, transitionSpec = { fadeIn(effects) togetherWith fadeOut(effects) }, label = "tabs") { visibleTab ->
                            when (visibleTab) {
                                0 -> FeedScreen(vm, state, active = route == "main" && tab == 0, immersive = immersive, onImmersive = { immersive = it }, onSearch = { open("search") }, onAccount = { auth = true }, onComments = { comments = it }, onDescription = { description = it }, onProfile = { open("profile:$it") }, onMenu = { menuPost = it })
                                2 -> InboxScreen(vm, state, { auth = true }, { open("chat:$it") }, { open("search") })
                                else -> ProfileScreen(vm, state, state.activeID, { auth = true }, ::open, { openedPost = it }, { route = "main" })
                            }
                        }
                        current == "search" -> SearchScreen(vm, state, ::goBack, { open("profile:$it") }, { openedPost = it })
                        current.startsWith("profile:") -> ProfileScreen(vm, state, current.substringAfter(':'), { auth = true }, ::open, { openedPost = it }, ::goBack)
                        current.startsWith("followers:") -> { val id = current.substringAfter(':'); SearchScreen(vm, state, ::goBack, { open("profile:$it") }, { openedPost = it }, state.following.filterValues { id in it }.keys, "Підписники") }
                        current.startsWith("following:") -> { val id = current.substringAfter(':'); SearchScreen(vm, state, ::goBack, { open("profile:$it") }, { openedPost = it }, state.following[id].orEmpty(), "Підписки") }
                        current.startsWith("chat:") -> ChatScreen(vm, state, current.substringAfter(':'), ::goBack, { auth = true })
                        current.startsWith("publish") -> PublishScreen(vm, state, current.substringAfter(':', ""), ::goBack)
                        current.startsWith("qr:") -> QrScreen(state.profiles.find { it.id == current.substringAfter(':') }, ::goBack)
                        current == "studio" -> StudioScreen(vm, state, ::open, ::goBack, { openedPost = it })
                        current == "settings" -> SettingsScreen(vm, state, ::goBack)
                        else -> SettingsScreen(vm, state, ::goBack)
                    }
                }
                if (!route.startsWith("publish") && !route.startsWith("chat:") && !(route == "main" && tab == 0 && immersive)) {
                    val shadeColor = when {
                        route == "main" && tab == 3 -> ownProfileColor
                        route.startsWith("profile:") -> ProfilePalette(state.profiles.find { it.id == route.substringAfter(':') }?.portraitFile?.let { java.io.File(vm.repository.mediaDirectory, it) }, MaterialTheme.colorScheme.background)
                        else -> MaterialTheme.colorScheme.background
                    }
                    BottomIslandShade(Modifier.align(Alignment.BottomCenter), color = shadeColor)
                }
                if (route == "main" && !(tab == 0 && immersive)) {
                    val profileColor = if (tab == 3) ownProfileColor else null
                    AppNavigation(tab, { index -> if (index == 1) account { open("publish") } else tab = index }, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(horizontal = 24.dp, vertical = 10.dp).fillMaxWidth(), profileColor)
                }
            }
            SnackbarHost(notices, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 94.dp))
        }
        if (ready && !state.welcomed && entryPrompt) AlertDialog(onDismissRequest = { entryPrompt = false; vm.act { welcome() } }, title = { Text("Твій новий кадр") }, text = { Text("Дивись без акаунта. Для публікацій, реакцій і повідомлень створи свій локальний профіль.") }, confirmButton = { TextButton(onClick = { entryPrompt = false; auth = true; vm.act { welcome() } }, shapes = ButtonDefaults.shapes()) { Text("Створити профіль") } }, dismissButton = { TextButton(onClick = { entryPrompt = false; vm.act { welcome() } }, shapes = ButtonDefaults.shapes()) { Text("Поки переглядатиму") } })
        if (auth) AccountDialog(vm, state, onClose = { auth = false })
        comments?.let { post -> CommentsSheet(vm, state, post, { comments = null }, { auth = true }) }
        description?.let { post -> ModalBottomSheet(onDismissRequest = { description = null }) { Column(Modifier.padding(24.dp).navigationBarsPadding()) { Text("Повний опис", style = MaterialTheme.typography.titleLarge); Spacer(Modifier.height(16.dp)); Text(post.caption); if (post.options.tags.isNotBlank()) Text(post.options.tags, color = MaterialTheme.colorScheme.primary); if (post.options.location.isNotBlank()) Text(post.options.location); Text(post.credit, style = MaterialTheme.typography.labelSmall) } } }
        openedPost?.let { post -> androidx.compose.ui.window.Dialog(onDismissRequest = { openedPost = null }, properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
            Box(Modifier.fillMaxSize()) {
                var pause by remember(post.id) { mutableStateOf(false) }
                var mute by remember { mutableStateOf(!state.studio.preferences.autoSound) }
                PostMediaView(post, vm.repository, true, mute, pause, Modifier.fillMaxSize()) { pause = !pause }
                Row(Modifier.align(Alignment.TopStart).statusBarsPadding().padding(16.dp)) { CircleAction(Icons.AutoMirrored.Outlined.ArrowBack, "Назад", { openedPost = null }, visualSize = 44.dp); CircleAction(if (mute) Icons.Outlined.VolumeOff else Icons.AutoMirrored.Outlined.VolumeUp, "Звук", { mute = !mute }, visualSize = 44.dp) }
            }
        } }
        menuPost?.let { post -> PostActionsSheet(vm, state, post, { menuPost = null }, ::open, { auth = true }) }
    }
}

@Composable fun CircleAction(icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, selected: Boolean = false, visualSize: Dp = 48.dp, containerColor: Color? = null) {
    val view = LocalView.current
    OutlinedIconButton(onClick = { view.performHapticFeedback(android.view.HapticFeedbackConstants.CONTEXT_CLICK); onClick() }, shapes = IconButtonDefaults.shapes(), modifier = modifier.size(visualSize), border = islandRim(), colors = IconButtonDefaults.outlinedIconButtonColors(containerColor = containerColor ?: if (selected) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.onSurface)) { Icon(icon, label, Modifier.size(if (visualSize < 48.dp) 20.dp else 24.dp)) }
}
@Composable fun Choices(labels: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, compact: Boolean = false) {
    Row(modifier.heightIn(min = 48.dp).selectableGroup(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        labels.forEachIndexed { index, label -> ToggleButton(checked = selected == index, onCheckedChange = { onSelect(index) }, modifier = Modifier.weight(1f).height(if (compact) 40.dp else 48.dp), contentPadding = PaddingValues(horizontal = if (compact) 2.dp else 4.dp), shapes = when (index) { 0 -> ButtonGroupDefaults.connectedLeadingButtonShapes(); labels.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes(); else -> ButtonGroupDefaults.connectedMiddleButtonShapes() }, border = islandRim()) { Text(label, maxLines = 1, softWrap = false, style = if (compact) MaterialTheme.typography.labelMedium else MaterialTheme.typography.labelLarge) } }
    }
}
@Composable fun ScreenHeader(title: String, onBack: () -> Unit, actions: @Composable RowScope.() -> Unit = {}) {
    FloatingHeader(title, onBack, actions)
}
@Composable fun EmptyMessage(title: String, description: String, action: String? = null, onAction: () -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) { Icon(Icons.Outlined.AutoAwesome, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.primary); Text(title, style = MaterialTheme.typography.headlineSmall, textAlign = androidx.compose.ui.text.style.TextAlign.Center); Text(description, style = MaterialTheme.typography.bodyMedium, textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant); if (action != null) Button(onClick = onAction, shapes = ButtonDefaults.shapes(), border = islandRim()) { Text(action) } }
}

@Composable fun FeedScreen(vm: KadrViewModel, state: AppState, active: Boolean, immersive: Boolean, onImmersive: (Boolean) -> Unit, onSearch: () -> Unit, onAccount: () -> Unit, onComments: (Post) -> Unit, onDescription: (Post) -> Unit, onProfile: (String) -> Unit, onMenu: (Post) -> Unit) {
    var section by rememberSaveable { mutableIntStateOf(0) }
    val posts = remember(state.posts, state.activeID, state.following, state.studio.preferences, section) { vm.repository.feed(section) }
    val pager = rememberPagerState { posts.size }
    val context = LocalContext.current
    Box(Modifier.fillMaxSize()) {
        if (posts.isEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { EmptyMessage("Тут зʼявляться нові кадри", "Знайди авторів або опублікуй перший власний кадр.", "Пошук", onSearch) }
        else if (section == 2) {
            val list = androidx.compose.foundation.lazy.rememberLazyListState()
            val visible by remember { derivedStateOf { list.layoutInfo.visibleItemsInfo.maxByOrNull { minOf(it.offset + it.size, list.layoutInfo.viewportEndOffset) - maxOf(it.offset, list.layoutInfo.viewportStartOffset) }?.key } }
            LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(top = 116.dp, bottom = 116.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                items(posts, key = { it.id }) { post -> Column {
                    PostMediaView(post, vm.repository, active && visible == post.id, !state.studio.preferences.autoSound, false, Modifier.fillMaxWidth().heightIn(min = 240.dp, max = 560.dp).aspectRatio(if (post.photo) 1f else 0.8f))
                    Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = { if (state.active == null) onAccount() else vm.act { toggleReaction(post) } }, shapes = IconButtonDefaults.shapes()) { Icon(if (state.activeID in state.likes[post.id].orEmpty()) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder, "Уподобати") }
                        Text("${state.likes[post.id]?.size ?: 0}"); IconButton(onClick = { onComments(post) }, shapes = IconButtonDefaults.shapes()) { Icon(Icons.Outlined.ChatBubbleOutline, "Коментарі") }
                        IconButton(onClick = { onMenu(post) }, shapes = IconButtonDefaults.shapes()) { Icon(Icons.Outlined.MoreHoriz, "Дії з кадром") }
                        Spacer(Modifier.weight(1f)); IconButton(onClick = { if (state.active == null) onAccount() else vm.act { toggleReaction(post, true) } }, shapes = IconButtonDefaults.shapes()) { Icon(Icons.Outlined.BookmarkBorder, "Зберегти") }
                    }
                    if (post.caption.isNotBlank()) Text(post.caption, Modifier.padding(horizontal = 20.dp).clickable { onDescription(post) }, maxLines = 3, overflow = TextOverflow.Ellipsis)
                } }
            }
        } else VerticalPager(pager, Modifier.fillMaxSize(), beyondViewportPageCount = 1, key = { posts[it].id }) { index ->
            val post = posts[index]
            var paused by remember(post.id) { mutableStateOf(false) }
            var showPause by remember(post.id) { mutableStateOf(false) }
            var muted by remember { mutableStateOf(!state.studio.preferences.autoSound) }
            LaunchedEffect(showPause, paused) { if (showPause) { delay(2000); showPause = false } }
            Box(Modifier.fillMaxSize()) {
                PostMediaView(post, vm.repository, active && index == pager.currentPage, muted, paused, Modifier.fillMaxSize()) { paused = !paused; showPause = true }
                AnimatedVisibility(showPause, Modifier.align(Alignment.Center)) { FilledTonalIconButton(onClick = { paused = !paused; showPause = true }, modifier = Modifier.size(76.dp), shapes = IconButtonDefaults.shapes()) { Icon(if (paused) Icons.Outlined.PlayArrow else Icons.Outlined.Pause, "Пауза / відтворення", Modifier.size(38.dp)) } }
                if (!immersive) {
                    Column(Modifier.align(Alignment.BottomEnd).navigationBarsPadding().padding(end = 16.dp, bottom = 116.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        post.authorID?.let { id -> AuthorAvatarButton(state.profiles.find { it.id == id }, { onProfile(id) }) }
                        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerHigh) { Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            IconButton(onClick = { if (state.active == null) onAccount() else vm.act { toggleReaction(post) } }, shapes = IconButtonDefaults.shapes()) { Icon(if (state.activeID in state.likes[post.id].orEmpty()) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder, "Уподобати", tint = if (state.activeID in state.likes[post.id].orEmpty()) MaterialTheme.colorScheme.primary else LocalContentColor.current) }
                            if (!post.extras.hideLikeCount) Text("${state.likes[post.id]?.size ?: 0}", style = MaterialTheme.typography.labelSmall)
                            IconButton(onClick = { onComments(post) }, shapes = IconButtonDefaults.shapes()) { Icon(Icons.Outlined.ChatBubbleOutline, "Коментарі") }
                            Text("${state.comments[post.id]?.size ?: 0}", style = MaterialTheme.typography.labelSmall)
                            IconButton(onClick = { if (state.active == null) onAccount() else vm.act { toggleReaction(post, true) } }, shapes = IconButtonDefaults.shapes()) { Icon(if (state.activeID in state.bookmarks[post.id].orEmpty()) Icons.Outlined.Bookmark else Icons.Outlined.BookmarkBorder, "Зберегти") }
                        } }
                        CircleAction(if (muted) Icons.Outlined.VolumeOff else Icons.AutoMirrored.Outlined.VolumeUp, "Звук", { muted = !muted })
                        CircleAction(Icons.Outlined.MoreHoriz, "Дії з кадром", { onMenu(post) })
                    }
                    Column(Modifier.align(Alignment.BottomStart).navigationBarsPadding().padding(start = 20.dp, end = 88.dp, bottom = 122.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(post.authorID?.let { id -> state.profiles.find { it.id == id }?.let { "@" + it.handle } } ?: "Кадр · Blender Foundation", fontWeight = FontWeight.Bold, color = Color.White, modifier = Modifier.clickable { post.authorID?.let(onProfile) })
                        if (post.caption.isNotBlank()) Text(post.caption + "  ще", Modifier.clickable { onDescription(post) }, maxLines = 2, overflow = TextOverflow.Ellipsis, color = Color.White)
                        Text(post.options.tags, color = Color.White.copy(alpha = .8f), style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) { CircleAction(if (immersive) Icons.Outlined.FullscreenExit else Icons.Outlined.Fullscreen, "Повноекранний режим", { onImmersive(!immersive) }, visualSize = 44.dp, containerColor = ToggleButtonDefaults.colors().containerColor) }
            if (!immersive) { Choices(listOf("Для тебе", "Підписки", "Огляд"), section, { if (it == 1 && state.active == null) onAccount() else section = it }, Modifier.weight(1f), compact = true); Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) { CircleAction(Icons.Outlined.Search, "Пошук", onSearch, visualSize = 44.dp, containerColor = ToggleButtonDefaults.colors().containerColor) } }
        }
    }
}

@Composable fun PostActionsSheet(vm: KadrViewModel, state: AppState, post: Post, dismiss: () -> Unit, open: (String) -> Unit, account: () -> Unit) {
    val context = LocalContext.current
    var note by remember { mutableStateOf(state.studio.notes[post.id].orEmpty()) }
    ModalBottomSheet(onDismissRequest = dismiss) {
        Column(Modifier.padding(horizontal = 20.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Дії з кадром", style = MaterialTheme.typography.titleLarge)
            val scope = rememberCoroutineScope()
            ListItem(headlineContent = { Text("Поділитися") }, leadingContent = { Icon(Icons.Outlined.Share, null) }, modifier = Modifier.clickable { scope.launch { runCatching { sharePost(context, vm.repository, post) }.onFailure { vm.notice.value = "Не вдалося поділитися: ${it.localizedMessage}" }; dismiss() } })
            ListItem(headlineContent = { Text("Не цікаво") }, leadingContent = { Icon(Icons.Outlined.VisibilityOff, null) }, modifier = Modifier.clickable { vm.act { changeStudio { it.copy(preferences = it.preferences.copy(hiddenPosts = it.preferences.hiddenPosts + post.id)) } }; dismiss() })
            if (state.active != null) {
                OutlinedTextField(note, { note = it }, label = { Text("Приватна нотатка") }, modifier = Modifier.fillMaxWidth())
                TextButton(onClick = { vm.act { changeStudio { it.copy(notes = it.notes + (post.id to note)) } }; dismiss() }, shapes = ButtonDefaults.shapes()) { Text("Зберегти нотатку") }
                if (post.authorID == state.activeID) {
                    TextButton(onClick = { open("publish:${post.id}"); dismiss() }, shapes = ButtonDefaults.shapes()) { Text("Редагувати публікацію") }
                    TextButton(onClick = { vm.act { deletePost(post) }; dismiss() }, shapes = ButtonDefaults.shapes()) { Text("Видалити", color = MaterialTheme.colorScheme.error) }
                }
            } else Button(onClick = account, shapes = ButtonDefaults.shapes(), border = islandRim()) { Text("Увійти для інших дій") }
            Spacer(Modifier.height(16.dp))
        }
    }
}
