import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testProfileAndSavedAreTabsAndHeaderChangesAction() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES"]
        app.launch()

        let tabs = app.tabBars.firstMatch
        let feed = tabs.buttons["Стрічка"]
        let saved = tabs.buttons["Збережене"]
        let profile = tabs.buttons["Профіль"]
        let inbox = tabs.buttons["Вхідні"]
        let header = app.buttons["header.action"]
        XCTAssertTrue(feed.waitForExistence(timeout: 8))
        XCTAssertTrue(app.segmentedControls.buttons["Для тебе"].exists)
        XCTAssertEqual(header.label, "Пошук")

        inbox.tap()
        XCTAssertTrue(app.staticTexts["Вхідні порожні"].waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.staticTexts["Збережені відео"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saved.isSelected)
        XCTAssertTrue(profile.isHittable)
        profile.tap()
        XCTAssertTrue(app.staticTexts["Твій профіль"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(profile.isSelected)
        XCTAssertTrue(feed.isHittable)

        app.buttons["Увійти або створити акаунт"].tap()
        let register = app.buttons["Створити локальний акаунт"]
        XCTAssertTrue(register.waitForExistence(timeout: 5))
        register.tap()
        app.buttons["Пропустити фото"].tap()
        let nickname = app.textFields["account.handle"]
        XCTAssertTrue(nickname.waitForExistence(timeout: 5))
        nickname.tap()
        nickname.typeText("kadr" + UUID().uuidString.prefix(8).lowercased())
        app.buttons["Далі"].tap()
        let name = app.textFields["account.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Kadr Test")
        app.buttons["Завершити"].tap()
        XCTAssertTrue(app.staticTexts["Kadr Test"].waitForExistence(timeout: 5))
        XCTAssertEqual(header.label, "Вийти")
        XCTAssertGreaterThan(header.frame.width, 70)
        XCTAssertTrue(app.buttons["Змінити банер"].exists)

        feed.tap()
        let following = app.segmentedControls.buttons["Підписки"]
        XCTAssertTrue(following.waitForExistence(timeout: 5))
        XCTAssertEqual(header.label, "Пошук")
        XCTAssertLessThan(header.frame.width, 50)
        following.tap()
        XCTAssertTrue(app.staticTexts["У підписках поки немає відео"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Для тебе"].tap()
        let bookmark = app.buttons["Зберегти"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()
        XCTAssertTrue(app.buttons["Прибрати зі збереженого"].exists)

        saved.tap()
        let clip = app.cells.firstMatch
        XCTAssertTrue(clip.waitForExistence(timeout: 5))
        XCTAssertTrue(profile.isHittable)
        clip.tap()
        XCTAssertTrue(app.buttons["Призупинити"].waitForExistence(timeout: 5))
    }
}
