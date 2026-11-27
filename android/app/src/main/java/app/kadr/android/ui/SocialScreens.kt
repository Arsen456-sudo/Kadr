@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
package app.kadr.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.kadr.android.KadrViewModel
import app.kadr.android.data.*

@Composable fun SearchScreen(vm: KadrViewModel, state: AppState, back: () -> Unit, profile: (String) -> Unit, post: (Post) -> Unit, allowedIDs: Set<String>? = null, title: String = "Пошук") {
    var query by rememberSaveable { mutableStateOf("") }
    val term = query.trim().removePrefix("@").lowercase()
    val profiles = state.profiles.filter { (allowedIDs == null || it.id in allowedIDs) && it.id !in state.studio.preferences.blocked && (term.isBlank() || it.handle.contains(term) || it.name.contains(term, true)) }
    val posts = if (allowedIDs != null) emptyList() else (state.posts + AppState.samples).filter { !it.isDraft && (!it.options.onlyMe || it.authorID == state.activeID) && (it.caption.contains(query, true) || it.options.tags.contains(query, true)) }
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        ScreenHeader(title, back)
        OutlinedTextField(query, { query = it }, leadingIcon = { Icon(Icons.Outlined.Search, null) }, label = { Text("@нікнейм, відео або #тег") }, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp), singleLine = true)
        LazyColumn(contentPadding = PaddingValues(bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 24.dp)) {
            if (term.isEmpty() && state.studio.searches.isNotEmpty()) {
                item { Text("Недавні запити", Modifier.padding(20.dp), style = MaterialTheme.typography.titleSmall) }
                items(state.studio.searches.take(8)) { text -> ListItem(headlineContent = { Text(text) }, modifier = Modifier.clickable { query = text }, trailingContent = { IconButton(onClick = { vm.act { changeStudio { it.copy(searches = it.searches - text) } } }, shapes = IconButtonDefaults.shapes()) { Icon(Icons.Outlined.Close, "Прибрати") } }) }
            }
            item { Text("Користувачі", Modifier.padding(20.dp), style = MaterialTheme.typography.titleMedium) }
            items(profiles, key = { it.id }) { person -> ListItem(headlineContent = { Text(person.name) }, supportingContent = { Text("@" + person.handle) }, leadingContent = { Icon(Icons.Outlined.AccountCircle, null) }, modifier = Modifier.clickable { if (query.isNotBlank()) vm.act { changeStudio { it.copy(searches = (listOf(query) + it.searches).distinct().take(30)) } }; profile(person.id) }) }
            if (profiles.isEmpty()) item { Text("Нікого не знайдено", Modifier.padding(horizontal = 20.dp)) }
            item { Text("Кадри", Modifier.padding(20.dp), style = MaterialTheme.typography.titleMedium) }
            items(posts, key = { it.id }) { item -> ListItem(headlineContent = { Text(item.caption.ifBlank { "Публікація" }, maxLines = 2) }, supportingContent = { Text(item.options.tags) }, leadingContent = { MediaPoster(item.items.first(), vm.repository, Modifier.size(64.dp)) }, modifier = Modifier.clickable { post(item) }) }
        }
    }
}

@Composable fun CommentsSheet(vm: KadrViewModel, state: AppState, post: Post, close: () -> Unit, account: () -> Unit) {
    var input by rememberSaveable(post.id) { mutableStateOf("") }
    var reply by remember { mutableStateOf<Comment?>(null) }
    var selected by remember { mutableStateOf<Comment?>(null) }
    var editing by remember { mutableStateOf<Comment?>(null) }
    var editText by remember { mutableStateOf("") }
    var popular by rememberSaveable { mutableStateOf(false) }
    val comments = state.comments[post.id].orEmpty().filter { comment -> state.studio.preferences.mutedWords.none { it.isNotBlank() && comment.text.contains(it, true) } }.sortedWith(compareByDescending<Comment> { it.pinned }.thenByDescending { if (popular) it.likes.size.toDouble() else it.createdAt })
    ModalBottomSheet(onDismissRequest = close) {
        Column(Modifier.fillMaxWidth().imePadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) { Text("Коментарі · ${comments.size}", style = MaterialTheme.typography.titleLarge); Spacer(Modifier.weight(1f)); TextButton(onClick = { popular = !popular }, shapes = ButtonDefaults.shapes()) { Text(if (popular) "Популярні" else "Нові") } }
            LazyColumn(Modifier.fillMaxWidth().heightIn(min = 120.dp, max = 390.dp), contentPadding = PaddingValues(16.dp)) {
                if (comments.isEmpty()) item { EmptyMessage("Почни розмову", "Перший коментар може надихнути автора.") }
                items(comments, key = { it.id }) { comment ->
                    Column(Modifier.fillMaxWidth().combinedClickable(onClick = { reply = comment }, onLongClick = { selected = comment }).padding(vertical = 10.dp)) {
                        val author = state.profiles.find { it.id.equals(comment.authorID, true) }
                        Text((author?.let { "@" + it.handle } ?: "Користувач") + if (post.authorID == comment.authorID) " · автор" else "", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                        if (comment.pinned) Text("Закріплено автором", style = MaterialTheme.typography.labelSmall)
                        comment.parentID?.let { parent -> comments.find { it.id == parent }?.let { Text("↳ ${it.text.take(70)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                        Text(comment.text)
                        Row(verticalAlignment = Alignment.CenterVertically) { TextButton(onClick = { reply = comment }, shapes = ButtonDefaults.shapes()) { Text("Відповісти") }; Spacer(Modifier.weight(1f)); IconButton(onClick = { if (state.active == null) account() else vm.act { updateComment(post, comment) } }, shapes = IconButtonDefaults.shapes()) { Icon(if (state.activeID in comment.likes) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder, "Лайк коментаря") }; Text("${comment.likes.size}") }
                    }
                }
            }
            reply?.let { Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) { Text("Відповідь: ${it.text.take(55)}", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall); IconButton(onClick = { reply = null }, shapes = IconButtonDefaults.shapes()) { Icon(Icons.Outlined.Close, "Скасувати відповідь") } } }
            if (state.active == null) Button(onClick = account, modifier = Modifier.fillMaxWidth().padding(16.dp), shapes = ButtonDefaults.shapes(), border = islandRim()) { Text("Увійти, щоб коментувати") }
            else if (post.options.allowsComments) Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(input, { input = it }, modifier = Modifier.weight(1f), placeholder = { Text("Написати коментар…") }, shape = MaterialTheme.shapes.extraLarge, maxLines = 3)
                IconButton(onClick = { vm.act { addComment(post, input, reply?.id); input = ""; reply = null } }, enabled = input.isNotBlank(), shapes = IconButtonDefaults.shapes()) { Icon(Icons.AutoMirrored.Outlined.Send, "Надіслати") }
            } else Text("Автор вимкнув коментарі", Modifier.padding(24.dp))
        }
    }
    selected?.let { comment -> AlertDialog(onDismissRequest = { selected = null }, title = { Text("Коментар") }, text = { Column {
        TextButton(onClick = { reply = comment; selected = null }, shapes = ButtonDefaults.shapes()) { Text("Відповісти") }
        if (comment.authorID == state.activeID) {
            TextButton(onClick = { editing = comment; editText = comment.text; selected = null }, shapes = ButtonDefaults.shapes()) { Text("Редагувати") }
            TextButton(onClick = { vm.act { updateComment(post, comment, delete = true) }; selected = null }, shapes = ButtonDefaults.shapes()) { Text("Видалити") }
        }
        if (post.authorID == state.activeID) TextButton(onClick = { vm.act { updateComment(post, comment, pin = true) }; selected = null }, shapes = ButtonDefaults.shapes()) { Text(if (comment.pinned) "Відкріпити" else "Закріпити") }
    } }, confirmButton = { TextButton(onClick = { selected = null }, shapes = ButtonDefaults.shapes()) { Text("Закрити") } }) }
    editing?.let { comment -> AlertDialog(onDismissRequest = { editing = null }, title = { Text("Редагувати коментар") }, text = { OutlinedTextField(editText, { editText = it }) }, confirmButton = { TextButton(onClick = { vm.act { updateComment(post, comment, text = editText); editing = null } }, enabled = editText.isNotBlank(), shapes = ButtonDefaults.shapes()) { Text("Зберегти") } }, dismissButton = { TextButton(onClick = { editing = null }, shapes = ButtonDefaults.shapes()) { Text("Скасувати") } }) }
}

@Composable fun InboxScreen(vm: KadrViewModel, state: AppState, account: () -> Unit, chat: (String) -> Unit, search: () -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var mode by rememberSaveable { mutableIntStateOf(0) }
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        FloatingHeader("Вхідні", actions = { Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) { CircleAction(Icons.Outlined.PersonSearch, "Новий чат", search, visualSize = 44.dp) } })
        if (state.active == null) { EmptyMessage("Розмови, що залишаються з тобою", "Увійди, щоб надсилати повідомлення авторам.", "Увійти", account); return }
        Choices(listOf("Повідомлення", "Активність"), mode, { mode = it }, Modifier.padding(horizontal = 20.dp))
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(16.dp), label = { Text("Пошук розмов") }, singleLine = true)
        val peers = state.messages.filter { it.senderID == state.activeID || it.recipientID == state.activeID }.groupBy { if (it.senderID == state.activeID) it.recipientID else it.senderID }.entries.sortedWith(compareByDescending<Map.Entry<String, List<Message>>> { it.key in state.studio.pinnedChats }.thenByDescending { it.value.maxOfOrNull(Message::createdAt) ?: 0.0 })
        LazyColumn(contentPadding = PaddingValues(bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 96.dp)) {
            if (mode == 1) {
                val mine = state.posts.filter { it.authorID == state.activeID }
                mine.forEach { post ->
                    val count = state.likes[post.id].orEmpty().count { it != state.activeID }
                    if (count > 0) item(key = "like-${post.id}") { ListItem(headlineContent = { Text("$count користувачів уподобали кадр") }, supportingContent = { Text(post.caption) }, leadingContent = { Icon(Icons.Outlined.FavoriteBorder, null) }) }
                    state.comments[post.id].orEmpty().filter { it.authorID != state.activeID }.forEach { comment -> item(key = comment.id) { ListItem(headlineContent = { Text("Новий коментар") }, supportingContent = { Text(comment.text) }) } }
                }
                item { Text("Тут показано локальну активність", Modifier.padding(20.dp), style = MaterialTheme.typography.bodySmall) }
            } else {
                if (peers.isEmpty()) item { EmptyMessage("Почни нову розмову", "Знайди користувача, підпишись і натисни «Написати».", "Знайти автора", search) }
                peers.forEach { (id, messages) ->
                    val profile = state.profiles.find { it.id == id }
                    if (profile != null && (query.isEmpty() || profile.handle.contains(query, true) || messages.any { it.text.contains(query, true) })) item(key = id) { ListItem(headlineContent = { Text((if (id in state.studio.pinnedChats) "📌 " else "") + profile.name) }, supportingContent = { Text(messages.maxByOrNull(Message::createdAt)?.text.orEmpty(), maxLines = 2) }, leadingContent = { Icon(Icons.Outlined.AccountCircle, null) }, modifier = Modifier.clickable { chat(id) }) }
                }
            }
        }
    }
}

@Composable fun ChatScreen(vm: KadrViewModel, state: AppState, peer: String, back: () -> Unit, account: () -> Unit) {
    val profile = state.profiles.find { it.id == peer }
    var input by rememberSaveable(peer, state.activeID) { mutableStateOf(state.studio.chatDrafts[peer].orEmpty()) }
    var query by rememberSaveable(peer) { mutableStateOf("") }
    var reply by remember { mutableStateOf<Message?>(null) }
    var selected by remember { mutableStateOf<Message?>(null) }
    var editing by remember { mutableStateOf<Message?>(null) }
    var editText by remember { mutableStateOf("") }
    val owner = state.activeID
    val messages = state.messages.filter { (it.senderID == owner && it.recipientID == peer) || (it.senderID == peer && it.recipientID == owner) }.filter { query.isBlank() || it.text.contains(query, true) }.sortedBy(Message::createdAt)
    val list = rememberLazyListState()
    LaunchedEffect(messages.size) { if (messages.isNotEmpty()) list.animateScrollToItem(messages.lastIndex) }
    DisposableEffect(peer, owner) { onDispose { if (vm.repository.state.value.activeID == owner && vm.repository.ready.value) vm.repository.changeStudio { it.copy(chatDrafts = it.chatDrafts + (peer to input)) } } }
    Column(Modifier.fillMaxSize().statusBarsPadding().imePadding()) {
        ScreenHeader(profile?.name ?: "Повідомлення", back) { Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) { CircleAction(Icons.Outlined.PushPin, "Закріпити розмову", { vm.act { changeStudio { it.copy(pinnedChats = if (peer in it.pinnedChats) it.pinnedChats - peer else it.pinnedChats + peer) } } }, visualSize = 44.dp) } }
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(horizontal = 16.dp), placeholder = { Text("Знайти повідомлення") }, singleLine = true)
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), state = list, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(messages, key = Message::id) { message ->
                val mine = message.senderID == owner
                Row(Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
                    Surface(Modifier.widthIn(max = 290.dp).combinedClickable(onClick = {}, onLongClick = { selected = message }), shape = MaterialTheme.shapes.large, color = if (mine) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh) {
                        Column(Modifier.padding(14.dp)) { message.replyTo?.let { id -> state.messages.find { it.id == id }?.let { Text("↳ " + it.text.take(75), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary) } }; Text(message.text); if (message.reactions.isNotEmpty()) Text(message.reactions.values.joinToString(" "), style = MaterialTheme.typography.labelLarge) }
                    }
                }
            }
        }
        reply?.let { Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) { Text("↳ ${it.text.take(70)}", Modifier.weight(1f)); IconButton(onClick = { reply = null }, shapes = IconButtonDefaults.shapes()) { Icon(Icons.Outlined.Close, "Скасувати відповідь") } } }
        if (state.active == null) Button(onClick = account, shapes = ButtonDefaults.shapes(), border = islandRim()) { Text("Увійти") } else Row(Modifier.composerShade().navigationBarsPadding().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(input, { input = it }, Modifier.weight(1f), placeholder = { Text("Повідомлення…") }, shape = MaterialTheme.shapes.extraLarge, maxLines = 5)
            FilledIconButton({ vm.act { send(peer, input, reply?.id); input = ""; reply = null } }, enabled = input.isNotBlank()) { Icon(Icons.AutoMirrored.Outlined.Send, "Надіслати") }
        }
    }
    selected?.let { message -> AlertDialog(onDismissRequest = { selected = null }, title = { Text("Повідомлення") }, text = { Column {
        TextButton(onClick = { reply = message; selected = null }, shapes = ButtonDefaults.shapes()) { Text("Відповісти") }
        Row { listOf("❤️", "🔥", "😂", "👍").forEach { emoji -> TextButton(onClick = { vm.act { editMessage(message, emoji = emoji) }; selected = null }, shapes = ButtonDefaults.shapes()) { Text(emoji) } } }
        if (message.senderID == owner) {
            TextButton(onClick = { editing = message; editText = message.text; selected = null }, shapes = ButtonDefaults.shapes()) { Text("Редагувати") }
            TextButton(onClick = { vm.act { editMessage(message, delete = true) }; selected = null }, shapes = ButtonDefaults.shapes()) { Text("Видалити") }
        }
    } }, confirmButton = { TextButton(onClick = { selected = null }, shapes = ButtonDefaults.shapes()) { Text("Закрити") } }) }
    editing?.let { message -> AlertDialog(onDismissRequest = { editing = null }, title = { Text("Редагувати повідомлення") }, text = { OutlinedTextField(editText, { editText = it }) }, confirmButton = { TextButton(onClick = { vm.act { editMessage(message, text = editText); editing = null } }, enabled = editText.isNotBlank(), shapes = ButtonDefaults.shapes()) { Text("Зберегти") } }, dismissButton = { TextButton(onClick = { editing = null }, shapes = ButtonDefaults.shapes()) { Text("Скасувати") } }) }
}
