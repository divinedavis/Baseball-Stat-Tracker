import XCTest

final class AddPlayerUITests: BarrelUITestCase {
    func testAddPlayerFlow() {
        launch()
        openAddPlayerSheet()

        let nameField = nameTextField()
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Name field should appear in Add Player sheet")
        nameField.tap()
        nameField.typeText("Test Hitter")

        app.buttons["saveAddPlayerButton"].tap()

        XCTAssertTrue(
            app.buttons["playerRow-Test Hitter"].waitForExistence(timeout: 6),
            "New player should appear in the roster after Save"
        )
    }

    func testSaveDisabledWhenNameEmpty() {
        launch()
        openAddPlayerSheet()
        XCTAssertFalse(
            app.buttons["saveAddPlayerButton"].isEnabled,
            "Save must be disabled until a name is entered"
        )
    }

    func testCancelDoesNotAddPlayer() {
        launch()
        openAddPlayerSheet()

        let nameField = nameTextField()
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("Discarded")
        app.buttons["cancelAddPlayerButton"].tap()
        XCTAssertFalse(
            app.buttons["playerRow-Discarded"].waitForExistence(timeout: 2),
            "Cancel must not persist the player"
        )
    }

    /// Tap the toolbar + button and wait for the sheet to be fully
    /// presented. Retries the tap once if the sheet doesn't show within
    /// 4s — SwiftUI toolbar items occasionally swallow the very first
    /// tap right after a navigation transition.
    private func openAddPlayerSheet() {
        waitFor(app.staticTexts["No players yet"], timeout: 10)
        waitFor(app.navigationBars["Players"], timeout: 10)
        let plus = waitForHittable(app.buttons["addPlayerButton"], timeout: 10)
        plus.tap()
        let save = app.buttons["saveAddPlayerButton"]
        if !save.waitForExistence(timeout: 4) {
            // Retry once — toolbar tap was eaten.
            plus.tap()
            XCTAssertTrue(save.waitForExistence(timeout: 10),
                          "Add Player sheet failed to present after retry")
        }
    }

    /// SwiftUI TextField in a Form is exposed to XCUITest as a regular
    /// textField, but the accessibilityIdentifier sometimes lands on the
    /// containing cell. Look in both places.
    private func nameTextField() -> XCUIElement {
        let direct = app.textFields["playerNameField"]
        if direct.exists { return direct }
        return app.descendants(matching: .textField).matching(identifier: "playerNameField").firstMatch
    }
}
