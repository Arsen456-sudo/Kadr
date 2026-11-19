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
        XCTAssertTrue(app.buttons["Для тебе"].exists)
        XCTAssertEqual(header.label, "Пошук")
        let searchWidth = header.frame.width
        XCTAssertTrue(app.staticTexts["Big Buck Bunny"].waitForExistence(timeout: 5))
        let playbackArea = app.buttons["video.playbackArea"].firstMatch
        XCTAssertTrue(playbackArea.waitForExistence(timeout: 5))
        playbackArea.tap()
        let play = app.buttons["Відтворити"]
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        play.tap()
        let pause = app.buttons["Призупинити"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        XCTAssertTrue(pause.waitForNonExistence(timeout: 4))
        capture(app, named: "Kadr-Portrait")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Sintel"].waitForExistence(timeout: 7))
        let sound = app.buttons["feed.sound"]
        let like = app.buttons["feed.like"]
        XCTAssertEqual(sound.frame.midX, like.frame.midX, accuracy: 1)
        XCTAssertEqual(sound.frame.width, like.frame.width + 6, accuracy: 1)
        capture(app, named: "Kadr-Landscape")

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
        XCTAssertGreaterThan(header.frame.width, searchWidth)
        XCTAssertTrue(app.buttons["Змінити банер"].exists)
        let sections = app.segmentedControls["profile.sections"]
        XCTAssertTrue(sections.waitForExistence(timeout: 5))
        let likesSection = sections.buttons["Уподобання"]
        XCTAssertTrue(likesSection.exists)
        likesSection.tap()
        XCTAssertTrue(likesSection.isSelected)
        capture(app, named: "Kadr-Profile-Likes")
        sections.buttons["Публікації"].tap()
        capture(app, named: "Kadr-Profile")

        feed.tap()
        let following = app.buttons["Підписки"]
        XCTAssertTrue(following.waitForExistence(timeout: 5))
        XCTAssertEqual(header.label, "Пошук")
        XCTAssertEqual(header.frame.width, searchWidth, accuracy: 1)
        following.tap()
        XCTAssertTrue(app.staticTexts["У підписках поки немає відео"].waitForExistence(timeout: 5))
        app.buttons["Для тебе"].tap()
        XCTAssertTrue(app.buttons["feed.sound"].exists)
        XCTAssertTrue(tabs.buttons["Додати"].exists)
        app.buttons["feed.comments"].tap()
        XCTAssertTrue(app.textFields["Написати коментар"].waitForExistence(timeout: 5))
        app.buttons["sheet.close"].tap()
        let bookmark = app.buttons["feed.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()
        XCTAssertEqual(bookmark.label, "Прибрати зі збереженого")

        saved.tap()
        let clip = app.cells.firstMatch
        XCTAssertTrue(clip.waitForExistence(timeout: 5))
        XCTAssertTrue(profile.isHittable)
        clip.tap()
        let previewArea = app.buttons["video.playbackArea"].firstMatch
        XCTAssertTrue(previewArea.waitForExistence(timeout: 5))
        previewArea.tap()
        XCTAssertTrue(app.buttons["Відтворити"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
