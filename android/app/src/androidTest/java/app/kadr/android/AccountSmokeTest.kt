package app.kadr.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountSmokeTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    @Test fun guestGateAccountAndProcessRecreation() {
        compose.waitUntil(15000) { compose.onAllNodesWithText("Поки переглядатиму").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Поки переглядатиму").performClick()
        (0..3).forEach { compose.onNodeWithTag("tab:$it").assertIsDisplayed() }
        listOf("Для тебе", "Підписки", "Огляд").forEach { compose.onNodeWithText(it).assertIsDisplayed() }
        compose.onAllNodesWithContentDescription("Уподобати").onFirst().performClick()
        compose.onNodeWithText("Твій профіль у Кадрі").assertIsDisplayed()
        compose.onNodeWithText("Імʼя").performTextInput("Android Tester")
        compose.onNodeWithText("Унікальний @нікнейм").performTextInput("android_tester")
        compose.onNodeWithText("Створити").performClick()
        compose.waitUntil(10000) { compose.onAllNodesWithText("Твій профіль у Кадрі").fetchSemanticsNodes().isEmpty() }
        compose.waitUntil(10000) { compose.activity.filesDir.resolve("kadr-state.json").takeIf { it.exists() }?.readText()?.contains("android_tester") == true }
        compose.onNodeWithTag("tab:3").performClick()
        compose.waitForIdle()
        compose.waitUntil(15000) { compose.onAllNodesWithText("@android_tester").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("@android_tester").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("profile-category:0").performScrollTo()
        val initial = compose.onNodeWithTag("profile-categories").fetchSemanticsNode().boundsInRoot
        val destinations = (0..4).map { compose.onNodeWithTag("profile-category:$it").fetchSemanticsNode().boundsInRoot }
        destinations.zipWithNext().forEach { (left, right) ->
            assertTrue("Profile destinations must not overlap", left.right <= right.left + 1f)
            assertEquals(left.width, right.width, 1f)
            assertEquals(left.top, right.top, 1f)
        }
        compose.onNodeWithTag("profile-scroll").performTouchInput { swipeUp() }
        compose.waitForIdle()
        val scrolled = compose.onNodeWithTag("profile-categories").fetchSemanticsNode().boundsInRoot
        assertEquals("Category width must stay stable on scroll", initial.width, scrolled.width, 1f)
        compose.onNodeWithTag("profile-category:1").performClick()
        compose.onNodeWithText("Поки немає кадрів").assertIsDisplayed()
        compose.onNodeWithTag("profile-category:0").performClick()
        compose.waitUntil(10000) { compose.activity.filesDir.resolve("kadr-state.json").takeIf { it.exists() }?.readText()?.contains("android_tester") == true }
        compose.activityRule.scenario.recreate()
        compose.waitUntil(15000) { compose.onAllNodesWithText("Профіль").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("tab:3").performClick()
        compose.waitUntil(15000) { compose.onAllNodesWithText("@android_tester").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("@android_tester").performScrollTo().assertIsDisplayed()
    }
}
