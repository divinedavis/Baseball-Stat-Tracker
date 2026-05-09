import XCTest

final class RosterUITests: BarrelUITestCase {
    func testEmptyStateShowsAddPrompt() {
        launch()
        XCTAssertTrue(app.staticTexts["No players yet"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["addPlayerButton"].exists)
    }

    func testSeededRosterShowsThreePlayers() {
        launch(extraArguments: ["-demoSeedEmpty"])
        for name in ["Jordan Davis", "Micah Lee", "Ari Chen"] {
            XCTAssertTrue(
                app.buttons["playerRow-\(name)"].waitForExistence(timeout: 6),
                "Expected \(name) row in roster"
            )
        }
    }

    func testTappingPlayerOpensDetailView() {
        launch(extraArguments: ["-demoSeedEmpty"])
        let row = app.buttons["playerRow-Jordan Davis"]
        waitFor(row).tap()
        XCTAssertTrue(app.staticTexts["Slash line"].waitForExistence(timeout: 6))
    }

    func testSwipeToDeletePlayer() {
        launch(extraArguments: ["-demoSeedEmpty"])
        let row = waitForHittable(app.buttons["playerRow-Ari Chen"])
        row.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        if deleteButton.waitForExistence(timeout: 3) {
            deleteButton.tap()
        }
        XCTAssertFalse(
            app.buttons["playerRow-Ari Chen"].waitForExistence(timeout: 2),
            "Ari Chen should be removed from the roster"
        )
    }
}
