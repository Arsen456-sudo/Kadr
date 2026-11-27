package app.kadr.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountSmokeTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    @Test fun guestGateAccountAndProcessRecreation() {
        compose.waitUntil(15000) { compose.onAllNodesWithText("Поки переглядатиму").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Поки переглядатиму").performClick()
        compose.onAllNodesWithContentDescription("Уподобати").onFirst().performClick()
        compose.onNodeWithText("Твій профіль у Кадрі").assertIsDisplayed()
        compose.onNodeWithText("Імʼя").performTextInput("Android Tester")
        compose.onNodeWithText("Унікальний @нікнейм").performTextInput("android_tester")
        compose.onNodeWithText("Створити").performClick()
        compose.waitUntil(10000) { compose.onAllNodesWithText("Твій профіль у Кадрі").fetchSemanticsNodes().isEmpty() }
        compose.waitUntil(10000) { compose.activity.filesDir.resolve("kadr-state.json").takeIf { it.exists() }?.readText()?.contains("android_tester") == true }
        compose.onNodeWithTag("tab:3").performClick()
        compose.waitForIdle()
        compose.onRoot().printToLog("KadrSmoke")
        compose.waitUntil(15000) { compose.onAllNodesWithText("@android_tester").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("@android_tester").performScrollTo().assertIsDisplayed()
        compose.waitUntil(10000) { compose.activity.filesDir.resolve("kadr-state.json").takeIf { it.exists() }?.readText()?.contains("android_tester") == true }
        compose.activityRule.scenario.recreate()
        compose.waitUntil(15000) { compose.onAllNodesWithText("Профіль").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("tab:3").performClick()
        compose.waitUntil(15000) { compose.onAllNodesWithText("@android_tester").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("@android_tester").performScrollTo().assertIsDisplayed()
    }
}
