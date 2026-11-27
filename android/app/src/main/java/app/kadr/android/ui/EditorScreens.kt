@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package app.kadr.android.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.kadr.android.KadrViewModel
import app.kadr.android.data.*
import app.kadr.android.data.Collection as SavedCollection
import kotlinx.coroutines.delay

@Composable fun PublishScreen(vm: KadrViewModel, state: AppState, postID: String, back: () -> Unit) {
    val existing = state.posts.find { it.id == postID }
    var draft by remember(postID) { mutableStateOf(existing ?: Post(authorID = state.activeID, isDraft = true)) }
    var published by remember { mutableStateOf(false) }
    var importing by remember { mutableStateOf(false) }
    var start by rememberSaveable { mutableStateOf(draft.extras.trimStart.toString()) }
    var end by rememberSaveable { mutableStateOf(draft.extras.trimEnd?.toString().orEmpty()) }
    var cover by rememberSaveable { mutableStateOf(draft.extras.coverTime.toString()) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
        if (uris.isNotEmpty()) { importing = true; vm.act { try { val added = importMedia(uris); draft = draft.copy(media = draft.media + added) } finally { importing = false } } }
    }
    LaunchedEffect(draft) { if (!published && draft.media.isNotEmpty() && existing?.isDraft != false) { delay(600); vm.act { if (!published) publish(draft.copy(isDraft = true)) } } }
    DisposableEffect(Unit) { onDispose { if (!published && draft.media.isNotEmpty() && existing?.isDraft != false && vm.repository.state.value.activeID == draft.authorID) vm.repository.publish(draft.copy(isDraft = true)) } }
    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding()) {
        ScreenHeader(if (existing?.isDraft == false) "Редагувати кадр" else "Новий кадр", back)
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                Text("Поділись своїм поглядом", style = MaterialTheme.typography.headlineMedium)
                Text("Фото, відео чи ціла історія — оригінали зберігаються без стискання.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            item { FilledTonalButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) }, modifier = Modifier.fillMaxWidth(), enabled = !importing, shapes = ButtonDefaults.shapes()) { Icon(Icons.Outlined.AddPhotoAlternate, null); Spacer(Modifier.width(8.dp)); Text(if (importing) "Додаю оригінали…" else "Додати фото або відео") } }
            itemsIndexed(draft.media, key = { _, media -> media.id }) { index, media ->
                OutlinedCard {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        MediaPoster(media, vm.repository, Modifier.size(76.dp))
                        Column(Modifier.weight(1f).padding(start = 12.dp)) {
                            Text("${index + 1}. ${if (media.kind == "photo") "Фото" else "Відео"}", style = MaterialTheme.typography.titleSmall)
                            TextButton(onClick = { draft = draft.copy(options = draft.options.copy(coverIndex = index)) }, shapes = ButtonDefaults.shapes()) { Text(if (draft.options.coverIndex == index) "✓ Обкладинка" else "Зробити обкладинкою") }
                        }
                        IconButton({ if (index > 0) { val items = draft.media.toMutableList(); java.util.Collections.swap(items, index, index - 1); draft = draft.copy(media = items) } }, enabled = index > 0) { Icon(Icons.Outlined.KeyboardArrowUp, "Перемістити вище") }
                        IconButton({ draft = draft.copy(media = draft.media.filterNot { it.id == media.id }, options = draft.options.copy(coverIndex = 0)) }) { Icon(Icons.Outlined.Close, "Прибрати") }
                    }
                    if (media.kind == "photo") OutlinedTextField(draft.extras.photoCaptions[index.toString()].orEmpty(), { text -> draft = draft.copy(extras = draft.extras.copy(photoCaptions = draft.extras.photoCaptions + (index.toString() to text))) }, Modifier.fillMaxWidth().padding(12.dp), label = { Text("Підпис до фото") })
                }
            }
            item { OutlinedTextField(draft.caption, { draft = draft.copy(caption = it) }, Modifier.fillMaxWidth(), label = { Text("Опис кадру") }, minLines = 3, maxLines = 8) }
            item { OutlinedTextField(draft.options.tags, { draft = draft.copy(options = draft.options.copy(tags = it)) }, Modifier.fillMaxWidth(), label = { Text("#Теги") }) }
            item { OutlinedTextField(draft.options.location, { draft = draft.copy(options = draft.options.copy(location = it)) }, Modifier.fillMaxWidth(), label = { Text("Місце") }) }
            if (draft.media.all { it.kind == "photo" } && draft.media.size > 1) item {
                Choices(listOf("Альбом", "Колаж"), if (draft.extras.albumLayout == "collage") 1 else 0, { draft = draft.copy(extras = draft.extras.copy(albumLayout = if (it == 1) "collage" else "pages")) }, Modifier.fillMaxWidth())
            }
            if (draft.media.firstOrNull()?.kind == "video") item {
                Text("Недеструктивне обрізання", style = MaterialTheme.typography.titleMedium)
                OutlinedTextField(start, { start = it }, Modifier.fillMaxWidth(), label = { Text("Початок, секунди") })
                OutlinedTextField(end, { end = it }, Modifier.fillMaxWidth(), label = { Text("Кінець, секунди (необовʼязково)") })
                OutlinedTextField(cover, { cover = it }, Modifier.fillMaxWidth(), label = { Text("Кадр обкладинки, секунди") })
            }
            item { SettingSwitch("Дозволити коментарі", draft.options.allowsComments) { draft = draft.copy(options = draft.options.copy(allowsComments = it)) } }
            item { SettingSwitch("Видно тільки мені", draft.options.onlyMe) { draft = draft.copy(options = draft.options.copy(onlyMe = it)) } }
            item { SettingSwitch("Приховати кількість уподобань", draft.extras.hideLikeCount) { draft = draft.copy(extras = draft.extras.copy(hideLikeCount = it)) } }
            item { Text("Чернетка зберігається автоматично на цьому пристрої.", style = MaterialTheme.typography.bodySmall) }
        }
        Button(onClick = { vm.act {
            val from = start.toDoubleOrNull() ?: error("Некоректний початок відео")
            val until = if (end.isBlank()) null else end.toDoubleOrNull() ?: error("Некоректний кінець відео")
            val poster = cover.toDoubleOrNull() ?: error("Некоректний час обкладинки")
            require(from.isFinite() && from >= 0 && poster.isFinite() && poster >= 0 && (until == null || (until.isFinite() && until > from))) { "Перевір діапазон відео." }
            publish(draft.copy(isDraft = false, extras = draft.extras.copy(trimStart = from, trimEnd = until, coverTime = poster)))
            published = true; back()
        } }, modifier = Modifier.fillMaxWidth().padding(16.dp), enabled = draft.media.isNotEmpty() && !importing, shapes = ButtonDefaults.shapes()) { Text(if (existing?.isDraft == false) "Зберегти зміни" else "Опублікувати") }
    }
}

@Composable fun SettingSwitch(title: String, checked: Boolean, changed: (Boolean) -> Unit) { ListItem(headlineContent = { Text(title) }, trailingContent = { Switch(checked, changed) }) }

@Composable fun StudioScreen(vm: KadrViewModel, state: AppState, open: (String) -> Unit, back: () -> Unit, post: (Post) -> Unit) {
    var page by rememberSaveable { mutableStateOf("home") }
    var value by rememberSaveable { mutableStateOf("") }
    var createCollection by remember { mutableStateOf(false) }
    var selectedCollection by remember { mutableStateOf<SavedCollection?>(null) }
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        ScreenHeader(if (page == "home") "Студія" else when (page) { "drafts" -> "Чернетки"; "history" -> "Історія"; "collections" -> "Колекції"; else -> "Оформлення" }, { if (page == "home") back() else page = "home" })
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (page == "home") {
                item { Text("Місце для твоїх ідей", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(12.dp)) }
                listOf("Оформлення профілю" to "appearance", "Чернетки" to "drafts", "Колекції" to "collections", "Історія переглядів" to "history").forEach { (title, route) -> item { ListItem(headlineContent = { Text(title) }, leadingContent = { Icon(when (route) { "appearance" -> Icons.Outlined.Palette; "drafts" -> Icons.Outlined.EditNote; "collections" -> Icons.Outlined.CollectionsBookmark; else -> Icons.Outlined.History }, null) }, modifier = Modifier.clickable { page = route }) } }
                item { ListItem(headlineContent = { Text("Налаштування") }, leadingContent = { Icon(Icons.Outlined.Settings, null) }, modifier = Modifier.clickable { open("settings") }) }
                item { ListItem(headlineContent = { Text("QR-код профілю") }, leadingContent = { Icon(Icons.Outlined.QrCode, null) }, modifier = Modifier.clickable { state.activeID?.let { open("qr:$it") } }) }
            } else if (page == "appearance") {
                item { Text("Акцентний колір", style = MaterialTheme.typography.titleMedium) }
                itemsIndexed(listOf("peach", "mint", "violet", "blue", "rose")) { _, accent -> FilterChip(selected = state.studio.appearance.accent == accent, onClick = { vm.act { changeStudio { it.copy(appearance = it.appearance.copy(accent = accent)) } } }, label = { Text(mapOf("peach" to "Персиковий", "mint" to "Мʼятний", "violet" to "Фіолетовий", "blue" to "Блакитний", "rose" to "Рожевий").getValue(accent)) }) }
                item {
                    var intro by remember { mutableStateOf(state.studio.appearance.introduction) }
                    OutlinedTextField(intro, { intro = it }, Modifier.fillMaxWidth(), label = { Text("Закріплене знайомство") })
                    TextButton(onClick = { vm.act { changeStudio { it.copy(appearance = it.appearance.copy(introduction = intro)) } } }, shapes = ButtonDefaults.shapes()) { Text("Зберегти знайомство") }
                }
                item {
                    var links by remember { mutableStateOf(state.studio.appearance.links.joinToString(" ")) }
                    OutlinedTextField(links, { links = it }, Modifier.fillMaxWidth(), label = { Text("HTTPS-посилання через пробіл") })
                    TextButton(onClick = { vm.act { val urls = links.split(Regex("\\s+")).filter { it.startsWith("https://") }; changeStudio { it.copy(appearance = it.appearance.copy(links = urls)) } } }, shapes = ButtonDefaults.shapes()) { Text("Зберегти посилання") }
                }
                item { Text("Закріпити до трьох публікацій", style = MaterialTheme.typography.titleMedium) }
                itemsIndexed(state.posts.filter { it.authorID == state.activeID && !it.isDraft }, key = { _, it -> it.id }) { _, item -> FilterChip(selected = item.id in state.studio.appearance.pinnedPosts, onClick = { vm.act { changeStudio { val pins = it.appearance.pinnedPosts; it.copy(appearance = it.appearance.copy(pinnedPosts = if (item.id in pins) pins - item.id else (pins + item.id).take(3))) } } }, label = { Text(item.caption.ifBlank { "Кадр" }.take(50)) }) }
            } else if (page == "drafts") {
                val drafts = state.posts.filter { it.authorID == state.activeID && it.isDraft }
                if (drafts.isEmpty()) item { EmptyMessage("Ідеї ще попереду", "Почни створювати кадр — він автоматично зʼявиться тут.") }
                itemsIndexed(drafts, key = { _, it -> it.id }) { _, draft -> ListItem(headlineContent = { Text(draft.caption.ifBlank { "Чернетка" }) }, supportingContent = { Text("${draft.media.size} медіафайлів") }, modifier = Modifier.clickable { open("publish:${draft.id}") }) }
            } else if (page == "history") {
                item { TextButton(onClick = { vm.act { changeStudio { it.copy(watches = emptyMap()) } } }, shapes = ButtonDefaults.shapes()) { Text("Очистити історію") } }
                itemsIndexed(state.studio.watches.values.sortedByDescending { it.updatedAt }) { _, watch -> (state.posts + AppState.samples).find { it.id == watch.postID }?.let { item -> ListItem(headlineContent = { Text(item.caption) }, supportingContent = { Text("${watch.seconds.toInt()} с переглянуто") }, modifier = Modifier.clickable { post(item) }) } }
            } else if (page == "collections") {
                item { Button(onClick = { value = ""; createCollection = true }, shapes = ButtonDefaults.shapes()) { Icon(Icons.Outlined.Add, null); Text("Створити колекцію") } }
                itemsIndexed(state.studio.collections, key = { _, it -> it.id }) { _, collection -> ListItem(headlineContent = { Text(collection.title) }, supportingContent = { Text("${collection.posts.size} кадрів") }, modifier = Modifier.clickable { selectedCollection = collection }) }
            }
        }
    }
    if (createCollection) AlertDialog(onDismissRequest = { createCollection = false }, title = { Text("Нова колекція") }, text = { OutlinedTextField(value, { value = it }, label = { Text("Назва") }) }, confirmButton = { TextButton(onClick = { vm.act { changeStudio { it.copy(collections = it.collections + SavedCollection(title = value.trim())) }; createCollection = false } }, enabled = value.isNotBlank(), shapes = ButtonDefaults.shapes()) { Text("Створити") } }, dismissButton = { TextButton(onClick = { createCollection = false }, shapes = ButtonDefaults.shapes()) { Text("Скасувати") } })
    selectedCollection?.let { collection -> ModalBottomSheet(onDismissRequest = { selectedCollection = null }) {
        LazyColumn(Modifier.padding(16.dp)) {
            item { Text(collection.title, style = MaterialTheme.typography.titleLarge); Text("Оберіть збережені кадри для колекції", style = MaterialTheme.typography.bodySmall) }
            itemsIndexed((state.posts + AppState.samples).filter { state.activeID in state.bookmarks[it.id].orEmpty() }) { _, item ->
                val checked = item.id in (state.studio.collections.find { it.id == collection.id }?.posts.orEmpty())
                ListItem(headlineContent = { Text(item.caption.ifBlank { "Кадр" }) }, trailingContent = { Checkbox(checked, { vm.act { changeStudio { it.copy(collections = it.collections.map { saved -> if (saved.id == collection.id) saved.copy(posts = if (checked) saved.posts - item.id else saved.posts + item.id) else saved }) } } }) }, modifier = Modifier.clickable { post(item) })
            }
            item { TextButton(onClick = { vm.act { changeStudio { it.copy(collections = it.collections.filterNot { it.id == collection.id }) } }; selectedCollection = null }, shapes = ButtonDefaults.shapes()) { Text("Видалити колекцію") } }
        }
    } }
}
