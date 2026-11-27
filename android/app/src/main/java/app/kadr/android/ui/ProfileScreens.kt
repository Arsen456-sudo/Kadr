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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.graphics.lerp
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
        Column(Modifier.heightIn(max = 440.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (!edit) Text("Локальний акаунт на цьому пристрої. Вхід Google / Apple буде доступний після підключення сервера.", style = MaterialTheme.typography.bodySmall)
            OutlinedTextField(name, { name = it }, label = { Text("Імʼя") }, singleLine = true)
            OutlinedTextField(handle, { handle = it }, label = { Text("Унікальний @нікнейм") }, prefix = { Text("@") }, singleLine = true)
            OutlinedTextField(bio, { bio = it }, label = { Text("Про себе") })
            if (name.isNotEmpty() && handle.isNotEmpty() && problem != null) Text(problem, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            OutlinedButton(onClick = { picker.launch("image/*") }, shapes = ButtonDefaults.shapes()) { Icon(Icons.Outlined.AddPhotoAlternate, null); Text(if (photo == null) "Фото профілю" else "Фото вибрано") }
            if (!edit && state.profiles.isNotEmpty()) {
                Text("Увійти в локальний акаунт", style = MaterialTheme.typography.labelLarge)
                state.profiles.forEach { profile -> TextButton(onClick = { vm.act { activate(profile.id); onClose() } }, shapes = ButtonDefaults.shapes()) { Text("@" + profile.handle) } }
            }
        }
    }, confirmButton = { Button(onClick = { focus.clearFocus(); keyboard?.hide(); vm.act { if (edit) editProfile(name, handle, bio) else createAccount(handle, name, bio = bio); photo?.let { setPhoto(it) }; onClose() } }, enabled = problem == null, shapes = ButtonDefaults.shapes()) { Text(if (edit) "Зберегти" else "Створити") } }, dismissButton = { TextButton(onClick = onClose, shapes = ButtonDefaults.shapes()) { Text("Скасувати") } })
}

private val profilePaletteCache = android.util.LruCache<String, Color>(16)

@Composable internal fun ProfilePalette(file: File?, fallback: Color): Color {
    if (file == null) return fallback
    val palette by produceState(profilePaletteCache[file.path] ?: fallback, file.path) {
        profilePaletteCache[file.path]?.let { value = it; return@produceState }
        value = withContext(Dispatchers.IO) {
            runCatching {
                val options = BitmapFactory.Options().apply { inSampleSize = 8 }
                val bitmap = BitmapFactory.decodeFile(file.path, options) ?: return@runCatching fallback
                var r = 0L; var g = 0L; var b = 0L; var count = 0
                val y = (bitmap.height * .95f).toInt().coerceIn(0, bitmap.height - 1)
                for (x in 0 until bitmap.width step 2) { val pixel = bitmap.getPixel(x, y); r += AndroidColor.red(pixel); g += AndroidColor.green(pixel); b += AndroidColor.blue(pixel); count++ }
                bitmap.recycle()
                if (count == 0) fallback else lerp(Color((r / count).toInt(), (g / count).toInt(), (b / count).toInt()), fallback, .65f)
            }.getOrDefault(fallback).also { profilePaletteCache.put(file.path, it) }
        }
    }
    return palette
}

@Composable fun AuthorAvatarButton(profile: Profile?, onClick: () -> Unit) {
    val bytes = remember(profile?.avatar) { profile?.avatar?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() } }
    FilledTonalIconButton(onClick = onClick, shapes = IconButtonDefaults.shapes(), modifier = Modifier.size(48.dp)) {
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
