package app.kadr.android

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.kadr.android.data.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class KadrViewModel(application: Application) : AndroidViewModel(application) {
    val repository = LocalRepository(application, viewModelScope)
    val state = repository.state
    val busy = MutableStateFlow(false)
    val notice = MutableStateFlow<String?>(null)
    private val vault = SessionVault(application)
    private var session: ApiSession? = null
    init { viewModelScope.launch { session = withContext(Dispatchers.IO) { vault.load() } } }
    fun act(operation: suspend LocalRepository.() -> Unit) {
        viewModelScope.launch {
            try { repository.operation() }
            catch (failure: Exception) { if (failure is kotlinx.coroutines.CancellationException) throw failure; notice.value = failure.localizedMessage ?: "Не вдалося виконати дію." }
        }
    }
    fun sync() {
        if (busy.value) return
        viewModelScope.launch {
            busy.value = true
            try { RemoteApi(checkNotNull(session) { "Спочатку налаштуй підключення до сервера." }).synchronize(repository); notice.value = "Дані синхронізовано" }
            catch (failure: Exception) { notice.value = failure.localizedMessage }
            finally { busy.value = false }
        }
    }
    fun connect(url: String, token: String) {
        viewModelScope.launch {
            try {
                val value = ApiSession(url.trim(), repository.requireAccount(), token.trim())
                RemoteApi(value)
                withContext(Dispatchers.IO) { vault.save(value) }; session = value; sync()
            } catch (failure: Exception) { notice.value = failure.localizedMessage }
        }
    }
    fun disconnect() { viewModelScope.launch { withContext(Dispatchers.IO) { vault.clear() }; session = null; notice.value = "Локальний режим" } }
}
