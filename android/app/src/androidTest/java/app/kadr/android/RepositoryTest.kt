package app.kadr.android

import android.content.Context
import android.content.ContextWrapper
import androidx.test.platform.app.InstrumentationRegistry
import app.kadr.android.data.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class RepositoryTest {
    @Test fun reactionsPrivacyAndChatGateAreAccountScoped() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "repository-test-${newId()}").apply { mkdirs() }
        val isolated = object : ContextWrapper(context) { override fun getFilesDir(): File = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        try {
            val repository = LocalRepository(isolated, scope)
            withTimeout(10000) { repository.ready.first { it } }
            withContext(Dispatchers.Main) {
                repository.createAccount("first_user", "Перший")
                val first = repository.requireAccount()
                repository.toggleReaction(AppState.samples.first())
                repository.createAccount("second_user", "Другий")
                val second = repository.requireAccount()
                assertFalse(second in repository.state.value.likes["bunny"].orEmpty())
                assertTrue(runCatching { repository.send(first, "До підписки") }.isFailure)
                repository.follow(first)
                repository.send(first, "Привіт")
                assertEquals(second, repository.state.value.messages.single().senderID)
                repository.activate(first)
                assertTrue(first in repository.state.value.likes["bunny"].orEmpty())
                repository.send(second, "Відповідь в існуючому чаті")
                assertEquals(2, repository.state.value.messages.size)
                repository.changeStudio { it.copy(preferences = it.preferences.copy(blocked = setOf(second))) }
                repository.activate(second)
                assertTrue(runCatching { repository.send(first, "Після блокування") }.isFailure)
            }
        } finally { scope.cancel(); directory.deleteRecursively() }
    }
}
