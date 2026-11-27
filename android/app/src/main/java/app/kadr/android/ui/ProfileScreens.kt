@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
package app.kadr.android.ui

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color as AndroidColor
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.kadr.android.KadrViewModel
import app.kadr.android.data.*
import coil3.compose.AsyncImage
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

@Composable fun AccountDialog(vm: KadrViewModel, state: AppState, onClose: () -> Unit, edit: Boolean = false) {
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    var name by rememberSaveable { mutableStateOf(if (edit) state.active?.name.orEmpty() else "") }
    var handle by rememberSaveable { mutableStateOf(if (edit) state.active?.handle.orEmpty() else "") }
    var bio by rememberSaveable { mutableStateOf(if (edit) state.active?.bio.orEmpty() else "") }
    var photo by remember { mutableStateOf<Uri?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { photo = it }
    val problem = AccountRules.validate(handle, name, state.profiles, if (edit) state.activeID else null)
    AlertDialog(onDismissRequest = onClose, title = { Text(if (edit) "Редагувати профіль" else "Твій профіль у Кадрі") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (!edit) Text("Локальний акаунт на цьому пристрої. Вхід Google / Apple буде доступний після підключення сервера.", style = MaterialTheme.typography.bodySmall)
            OutlinedTextField(name, { name = it }, label = { Text("Імʼя") }, singleLine = true)
            OutlinedTextField(handle, { handle = it }, label = { Text("Унікальний @нікнейм") }, prefix = { Text("@") }, singleLine = true)
            OutlinedTextField(bio, { bio = it }, label = { Text("Про себе") })
            if (name.isNotEmpty() && handle.isNotEmpty() && problem != null) Text(problem, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            OutlinedButton({ picker.launch("image/*") }) { Icon(Icons.Outlined.AddPhotoAlternate, null); Text(if (photo == null) "Фото профілю" else "Фото вибрано") }
            if (!edit && state.profiles.isNotEmpty()) {
                Text("Увійти в локальний акаунт", style = MaterialTheme.typography.labelLarge)
                state.profiles.forEach { profile -> TextButton({ vm.act { activate(profile.id); onClose() } }) { Text("@" + profile.handle) } }
            }
        }
    }, confirmButton = { Button(onClick = { focus.clearFocus(); keyboard?.hide(); vm.act { if (edit) editProfile(name, handle, bio) else createAccount(handle, name, bio = bio); photo?.let { setPhoto(it) }; onClose() } }, enabled = problem == null) { Text(if (edit) "Зберегти" else "Створити") } }, dismissButton = { TextButton(onClose) { Text("Скасувати") } })
}

@Composable private fun ProfilePalette(file: File?, fallback: Color): Color {
    val palette by produceState(fallback, file?.path) {
        if (file != null) value = withContext(Dispatchers.IO) {
            runCatching {
                val options = BitmapFactory.Options().apply { inSampleSize = 8 }
                val bitmap = BitmapFactory.decodeFile(file.path, options) ?: return@runCatching fallback
                var r = 0L; var g = 0L; var b = 0L; var count = 0
                val y = (bitmap.height * .95f).toInt().coerceIn(0, bitmap.height - 1)
                for (x in 0 until bitmap.width step 2) { val pixel = bitmap.getPixel(x, y); r += AndroidColor.red(pixel); g += AndroidColor.green(pixel); b += AndroidColor.blue(pixel); count++ }
                bitmap.recycle()
                if (count == 0) fallback else Color((r / count).toInt(), (g / count).toInt(), (b / count).toInt())
            }.getOrDefault(fallback)
        }
    }
    return palette
}

@Composable fun ProfileScreen(vm: KadrViewModel, state: AppState, profileID: String?, onAccount: () -> Unit, open: (String) -> Unit, onPost: (Post) -> Unit, onBack: () -> Unit) {
    val profile = state.profiles.find { it.id == profileID }
    if (profile == null) {
        Column(Modifier.fillMaxSize().statusBarsPadding()) { Text("Профіль", Modifier.padding(24.dp), style = MaterialTheme.typography.headlineLarge); EmptyMessage("Твоя історія починається тут", "Створи профіль, щоб публікувати, зберігати та спілкуватися.", "Створити акаунт", onAccount) }; return
    }
    val own = profile.id == state.activeID
    val context = LocalContext.current
    var edit by remember { mutableStateOf(false) }
    var editMenu by remember { mutableStateOf(false) }
    var more by remember { mutableStateOf(false) }
    var category by rememberSaveable(profile.id) { mutableIntStateOf(0) }
    val photo = profile.portraitFile?.let { File(vm.repository.mediaDirectory, it) }
    val background = ProfilePalette(photo, MaterialTheme.colorScheme.background)
    val image: Any? = photo ?: remember(profile.avatar) { profile.avatar?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() } }
    val list = rememberLazyListState()
    val scroll by remember { derivedStateOf { if (list.firstVisibleItemIndex == 0) list.firstVisibleItemScrollOffset.toFloat() else 700f } }
    val pinned by remember { derivedStateOf { list.layoutInfo.visibleItemsInfo.firstOrNull { it.key == "profile-sections" }?.offset?.let { it <= list.layoutInfo.viewportStartOffset } ?: (list.firstVisibleItemIndex > 1) } }
    val appearance = state.studios[profile.id]?.appearance ?: Appearance()
    val mine = state.posts.filter { it.authorID == profile.id && !it.isDraft && (own || !it.options.onlyMe) }.sortedWith(compareBy<Post> { appearance.pinnedPosts.indexOf(it.id).takeIf { index -> index >= 0 } ?: Int.MAX_VALUE }.thenByDescending { it.createdAt })
    val posts = when (category) { 1 -> mine; 2 -> if (own) (state.posts + AppState.samples).filter { state.activeID in state.bookmarks[it.id].orEmpty() } else emptyList(); 3 -> if (own) (state.posts + AppState.samples).filter { state.activeID in state.likes[it.id].orEmpty() } else emptyList(); 4 -> if (own) (state.posts + AppState.samples).filter { state.comments[it.id].orEmpty().any { comment -> comment.authorID == state.activeID } } else emptyList(); else -> emptyList() }
    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> uri?.let { vm.act { setPhoto(it) } } }
    Box(Modifier.fillMaxSize().background(background)) {
        Box(Modifier.fillMaxWidth().height(540.dp).graphicsLayer { translationY = -scroll.coerceAtMost(700f) }) {
            if (image != null) AsyncImage(image, profile.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) else Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(MaterialTheme.colorScheme.primaryContainer, background))))
            if (image != null) Box(Modifier.fillMaxWidth().height(200.dp).align(Alignment.BottomCenter).clip(MaterialTheme.shapes.large)) { AsyncImage(image, null, Modifier.fillMaxWidth().height(540.dp).align(Alignment.BottomCenter).blur(15.dp), contentScale = ContentScale.Crop) }
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to Color.Transparent, .44f to Color.Transparent, .65f to background.copy(alpha = .2f), .82f to background.copy(alpha = .8f), 1f to background)))
        }
        LazyColumn(Modifier.fillMaxSize().statusBarsPadding().padding(top = 12.dp), state = list, contentPadding = PaddingValues(bottom = 120.dp)) {
            item(key = "identity") {
                Column(Modifier.fillMaxWidth().padding(top = 280.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(profile.name, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                    Text("@" + profile.handle, style = MaterialTheme.typography.titleLarge)
                    if (profile.bio.isNotBlank()) Text(profile.bio, Modifier.padding(horizontal = 36.dp, vertical = 10.dp), style = MaterialTheme.typography.bodyMedium)
                    if (appearance.introduction.isNotBlank()) Text(appearance.introduction, Modifier.padding(horizontal = 28.dp, vertical = 10.dp), style = MaterialTheme.typography.bodyLarge)
                    appearance.links.filter { it.startsWith("https://") }.forEach { link -> TextButton({ context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link))) }) { Text(link) } }
                    Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                        listOf("Публікації" to mine.size, "Підписники" to state.following.values.count { profile.id in it }, "Підписки" to state.following[profile.id].orEmpty().size).forEachIndexed { index, (label, count) -> TextButton({ if (index == 0) category = 1 else open((if (index == 1) "followers:" else "following:") + profile.id) }) { Column(horizontalAlignment = Alignment.CenterHorizontally) { Text("$count", style = MaterialTheme.typography.titleLarge); Text(label, style = MaterialTheme.typography.labelSmall) } } }
                    }
                    Row(Modifier.fillMaxWidth().padding(horizontal = 28.dp, vertical = 12.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                        if (own) ProfileAction(Icons.Outlined.Tune, "Студія", { open("studio") }) else {
                            val follows = profile.id in state.following[state.activeID].orEmpty()
                            ProfileAction(if (follows) Icons.Outlined.PersonRemove else Icons.Outlined.PersonAdd, if (follows) "Стежу" else "Стежити", { if (state.active == null) onAccount() else vm.act { follow(profile.id) } })
                            if (follows) ProfileAction(Icons.Outlined.ChatBubbleOutline, "Написати", { open("chat:${profile.id}") })
                        }
                        ProfileAction(Icons.Outlined.Share, "Поділитися", { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "kadr://profile/${profile.handle}"), "Поділитися")) })
                        Box { ProfileAction(Icons.Outlined.MoreHoriz, "Ще", { more = true }); DropdownMenu(more, { more = false }) {
                            if (own) DropdownMenuItem(text = { Text("Вийти з акаунта") }, onClick = { vm.act { activate(null) }; more = false })
                            else DropdownMenuItem(text = { Text("Заблокувати") }, onClick = { vm.act { requireAccount(); changeStudio { it.copy(preferences = it.preferences.copy(blocked = it.preferences.blocked + profile.id)) } }; more = false; onBack() })
                        } }
                    }
                    Spacer(Modifier.height(24.dp))
                }
            }
            stickyHeader(key = "profile-sections") {
                Box(Modifier.fillMaxWidth().padding(horizontal = if (pinned) 68.dp else 28.dp, vertical = 2.dp), contentAlignment = Alignment.Center) {
                    Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainer) {
                        Row {
                            listOf(Icons.Outlined.Person, Icons.Outlined.GridView, Icons.Outlined.BookmarkBorder, Icons.Outlined.FavoriteBorder, Icons.Outlined.ChatBubbleOutline).forEachIndexed { index, icon -> IconToggleButton(checked = category == index, onCheckedChange = { category = index }, modifier = Modifier.weight(1f)) { Icon(icon, listOf("Профіль", "Публікації", "Збережені", "Уподобання", "Коментарі")[index], Modifier.size(20.dp)) } }
                        }
                    }
                }
            }
            if (category == 0) {
                item { Spacer(Modifier.height(18.dp)) }
                val rows = buildList {
                    add(Triple("Публікації", "${mine.size} кадрів · ${mine.sumOf { state.likes[it.id]?.size ?: 0 }} уподобань", "posts"))
                    add(Triple("Спільнота", "${state.following.values.count { profile.id in it }} підписників", "people"))
                    if (own) { add(Triple("Бібліотека", "${state.bookmarks.values.count { state.activeID in it }} збережених", "saved")); add(Triple("Налаштування", "Приватність і відтворення", "settings")); add(Triple("Оформлення", "Кольори, фото та акценти", "studio")) }
                }
                items(rows, key = { it.third }) { row ->
                    OutlinedCard(onClick = { when (row.third) { "posts" -> category = 1; "saved" -> category = 2; "people" -> open("search"); else -> open(row.third) } }, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp), colors = CardDefaults.outlinedCardColors(containerColor = background)) {
                        ListItem(headlineContent = { Text(row.first) }, supportingContent = { Text(row.second) }, trailingContent = { Icon(Icons.Outlined.ChevronRight, null) }, colors = ListItemDefaults.colors(containerColor = background))
                    }
                }
            } else if (posts.isEmpty()) item { EmptyMessage("Поки немає кадрів", if (own) "Тут будуть твої публікації та добірки." else "Автор ще не додав публікацій.") }
            else items(posts.chunked(2), key = { it.first().id }) { row ->
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { post -> Box(Modifier.weight(1f).aspectRatio(.74f).clip(MaterialTheme.shapes.large).clickable { onPost(post) }) { MediaPoster(post.items[post.options.coverIndex.coerceIn(0, post.items.lastIndex)], vm.repository, Modifier.fillMaxSize(), atSeconds = post.extras.coverTime); Text(if (post.photo) "Фото · ${post.items.size}" else "Відео", Modifier.align(Alignment.BottomStart).padding(10.dp), color = Color.White, style = MaterialTheme.typography.labelMedium) } }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            if (own) CircleAction(Icons.Outlined.QrCode, "QR-код", { open("qr:${profile.id}") }) else CircleAction(Icons.AutoMirrored.Outlined.ArrowBack, "Назад", onBack)
            val progress = (scroll / 300f).coerceIn(0f, 1f)
            Text("Профіль", Modifier.graphicsLayer { translationY = -progress * 80; alpha = (1 - progress) * (1 - progress) }, style = MaterialTheme.typography.titleMedium)
            if (own) Box {
                CircleAction(Icons.Outlined.Edit, "Редагувати", { editMenu = true })
                DropdownMenu(editMenu, { editMenu = false }) {
                    DropdownMenuItem(text = { Text("Змінити фото") }, onClick = { editMenu = false; photoPicker.launch("image/*") })
                    DropdownMenuItem(text = { Text("Імʼя та @нікнейм") }, onClick = { editMenu = false; edit = true })
                }
            } else CircleAction(Icons.Outlined.QrCode, "QR-код", { open("qr:${profile.id}") })
        }
    }
    if (edit) AccountDialog(vm, state, { edit = false }, edit = true)
}

@Composable private fun ProfileAction(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, click: () -> Unit) { Column(horizontalAlignment = Alignment.CenterHorizontally) { CircleAction(icon, text, click); Spacer(Modifier.height(7.dp)); Text(text, style = MaterialTheme.typography.labelSmall) } }

@Composable fun AuthorAvatarButton(profile: Profile?, onClick: () -> Unit) {
    val bytes = remember(profile?.avatar) { profile?.avatar?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() } }
    FilledTonalIconButton(onClick, Modifier.size(48.dp)) {
        if (bytes == null) Icon(Icons.Outlined.AccountCircle, "Автор")
        else AsyncImage(bytes, "Відкрити профіль автора", Modifier.size(34.dp).clip(androidx.compose.foundation.shape.CircleShape), contentScale = ContentScale.Crop)
    }
}

@Composable fun QrScreen(profile: Profile?, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        ScreenHeader("QR-код профілю", onBack)
        if (profile != null) {
            val bitmap by produceState<Bitmap?>(null, profile.handle) { value = withContext(Dispatchers.Default) {
                val matrix = MultiFormatWriter().encode("kadr://profile/${profile.handle}", BarcodeFormat.QR_CODE, 768, 768)
                Bitmap.createBitmap(768, 768, Bitmap.Config.ARGB_8888).apply { for (y in 0 until 768) for (x in 0 until 768) setPixel(x, y, if (matrix[x, y]) AndroidColor.BLACK else AndroidColor.WHITE) }
            } }
            Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                bitmap?.let { Image(it.asImageBitmap(), "QR-код @${profile.handle}", Modifier.fillMaxWidth().aspectRatio(1f).clip(MaterialTheme.shapes.extraLarge)) }
                Spacer(Modifier.height(24.dp)); Text("@" + profile.handle, style = MaterialTheme.typography.headlineSmall)
            }
        }
    }
}
