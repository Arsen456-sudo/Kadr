@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package app.kadr.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.kadr.android.KadrViewModel
import app.kadr.android.data.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable fun SettingsScreen(vm: KadrViewModel, state: AppState, back: () -> Unit) {
    val context = LocalContext.current
    var network by remember { mutableStateOf(false) }
    var url by remember { mutableStateOf("") }
    var token by remember { mutableStateOf("") }
    var words by remember { mutableStateOf(state.studio.preferences.mutedWords.joinToString(", ")) }
    var restore by remember { mutableStateOf<android.net.Uri?>(null) }
    val busy by vm.busy.collectAsStateWithLifecycle()
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri -> if (uri != null) vm.act { withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { writeBackup(it) } ?: error("Файл недоступний") }; vm.notice.value = "Резервну копію збережено" } }
    val import = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { restore = it }
    FloatingPage("Налаштування", back) { pageInsets ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = pageInsets, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Text("Взаємодія", style = MaterialTheme.typography.titleLarge) }
            item { SettingSwitch("Автоматично вмикати звук", state.studio.preferences.autoSound) { value -> vm.act { changeStudio { it.copy(preferences = it.preferences.copy(autoSound = value)) } } } }
            item { SettingSwitch("Тактильний відгук", state.studio.preferences.haptics) { value -> vm.act { changeStudio { it.copy(preferences = it.preferences.copy(haptics = value)) } } } }
            item { Text("Швидкість відео", style = MaterialTheme.typography.titleSmall); Choices(listOf("0.5×", "1×", "1.5×", "2×"), listOf(.5f, 1f, 1.5f, 2f).indexOf(state.studio.preferences.playbackRate).coerceAtLeast(0), { index -> vm.act { changeStudio { it.copy(preferences = it.preferences.copy(playbackRate = listOf(.5f, 1f, 1.5f, 2f)[index])) } } }, Modifier.fillMaxWidth()) }
            item { Text("Тип публікацій", style = MaterialTheme.typography.titleSmall); Choices(listOf("Усі", "Відео", "Фото"), listOf("all", "video", "photo").indexOf(state.studio.preferences.mediaFilter).coerceAtLeast(0), { index -> vm.act { changeStudio { it.copy(preferences = it.preferences.copy(mediaFilter = listOf("all", "video", "photo")[index])) } } }, Modifier.fillMaxWidth()) }
            item { Text("Приватність", style = MaterialTheme.typography.titleLarge) }
            item { Text("Хто може починати розмову", style = MaterialTheme.typography.titleSmall); Choices(listOf("Підписки", "Усі", "Ніхто"), listOf("following", "everyone", "nobody").indexOf(state.studio.preferences.messagePermission).coerceAtLeast(0), { index -> vm.act { changeStudio { it.copy(preferences = it.preferences.copy(messagePermission = listOf("following", "everyone", "nobody")[index])) } } }, Modifier.fillMaxWidth()) }
            item { OutlinedTextField(words, { words = it }, Modifier.fillMaxWidth(), label = { Text("Слова для приховування коментарів") }); TextButton(onClick = { vm.act { changeStudio { it.copy(preferences = it.preferences.copy(mutedWords = words.split(',').map(String::trim).filter(String::isNotBlank))) } } }, shapes = ButtonDefaults.shapes()) { Text("Зберегти фільтр") } }
            state.profiles.filter { it.id in state.studio.preferences.blocked }.forEach { person -> item(key = person.id) { ListItem(headlineContent = { Text("@" + person.handle) }, trailingContent = { TextButton(onClick = { vm.act { changeStudio { it.copy(preferences = it.preferences.copy(blocked = it.preferences.blocked - person.id)) } } }, shapes = ButtonDefaults.shapes()) { Text("Розблокувати") } }) } }
            item { Text("Твої дані", style = MaterialTheme.typography.titleLarge) }
            item { OutlinedButton(onClick = { export.launch("Kadr-backup.zip") }, modifier = Modifier.fillMaxWidth(), shapes = ButtonDefaults.shapes()) { Icon(Icons.Outlined.SaveAlt, null); Text("Резервна копія з медіа") } }
            item { OutlinedButton(onClick = { import.launch(arrayOf("application/zip", "application/octet-stream")) }, modifier = Modifier.fillMaxWidth(), shapes = ButtonDefaults.shapes()) { Text("Відновити копію") } }
            item { Text("Сервер", style = MaterialTheme.typography.titleLarge); Text("Зараз усе працює локально. За наявності власного API можна підʼєднати цей акаунт до спільного сервера iOS та Android.", style = MaterialTheme.typography.bodySmall) }
            item { Button(onClick = { network = true }, enabled = state.active != null, modifier = Modifier.fillMaxWidth(), shapes = ButtonDefaults.shapes()) { Text("Підключити HTTPS-сервер") } }
            item { OutlinedButton(onClick = { vm.sync() }, enabled = !busy && state.active != null, modifier = Modifier.fillMaxWidth(), shapes = ButtonDefaults.shapes()) { if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Text("Синхронізувати") } }
            item { TextButton(onClick = { vm.disconnect() }, shapes = ButtonDefaults.shapes()) { Text("Повернути локальний режим") } }
            item { Text("Кадр · Android 0.1.0", style = MaterialTheme.typography.labelSmall); Text("Демо: Big Buck Bunny та Sintel — Blender Foundation, CC BY 3.0. Повні авторські відомості у файлі VideoCredits.txt у складі застосунку.", style = MaterialTheme.typography.bodySmall) }
        }
    }
    if (network) AlertDialog(onDismissRequest = { network = false }, title = { Text("Спільний сервер Кадру") }, text = { Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Сесія має належати ID поточного акаунта. Токен зберігається зашифрованим Android Keystore.", style = MaterialTheme.typography.bodySmall)
        TextButton(onClick = { (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Kadr account ID", state.activeID)); vm.notice.value = "ID скопійовано" }, shapes = ButtonDefaults.shapes()) { Text("Скопіювати ID акаунта") }
        OutlinedTextField(url, { url = it }, label = { Text("https://…") }, singleLine = true)
        OutlinedTextField(token, { token = it }, label = { Text("Токен сесії") }, visualTransformation = PasswordVisualTransformation(), singleLine = true)
    } }, confirmButton = { TextButton(onClick = { vm.connect(url, token); token = ""; network = false }, enabled = url.startsWith("https://") && token.isNotBlank(), shapes = ButtonDefaults.shapes()) { Text("Підключити") } }, dismissButton = { TextButton(onClick = { network = false; token = "" }, shapes = ButtonDefaults.shapes()) { Text("Скасувати") } })
    restore?.let { uri -> AlertDialog(onDismissRequest = { restore = null }, title = { Text("Відновити резервну копію?") }, text = { Text("Локальні профілі й дані будуть замінені вмістом вибраної копії. Спочатку можна експортувати поточні дані.") }, confirmButton = { TextButton(onClick = { restore = null; vm.act { context.contentResolver.openInputStream(uri)?.use { restoreBackup(it) } ?: error("Копія недоступна"); vm.notice.value = "Копію відновлено" } }, shapes = ButtonDefaults.shapes()) { Text("Відновити") } }, dismissButton = { TextButton(onClick = { restore = null }, shapes = ButtonDefaults.shapes()) { Text("Скасувати") } }) }
}
