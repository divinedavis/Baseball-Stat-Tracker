import XCTest

final class AtBatPadUITests: BarrelUITestCase {
    func testRecordSingleUpdatesSlashLine() {
        launch(extraArguments: ["-demoSeedEmpty"])
        waitForHittable(app.buttons["playerRow-Jordan Davis"]).tap()

        let avgValue = waitFor(app.staticTexts["statValue-AVG"])
        XCTAssertEqual(avgValue.label, ".000", "AVG should be .000 before any AB")

        atBatButton("single").tap()

        // After 1 H / 1 AB, AVG = 1.000
        let updatedAvg = app.staticTexts["statValue-AVG"]
        let predicate = NSPredicate(format: "label == %@", "1.000")
        expectation(for: predicate, evaluatedWith: updatedAvg)
        waitForExpectations(timeout: 4)
    }

    func testRecordHomeRunIncrementsCountingStats() {
        launch(extraArguments: ["-demoSeedEmpty"])
        waitForHittable(app.buttons["playerRow-Micah Lee"]).tap()

        // Expand counting stats so HR cell is visible.
        waitFor(app.buttons["toggleCountingStats"], timeout: 10).tap()

        atBatButton("homeRun").tap()

        let hrValue = app.staticTexts["statValue-HR"]
        let predicate = NSPredicate(format: "label == %@", "1")
        expectation(for: predicate, evaluatedWith: hrValue)
        waitForExpectations(timeout: 4)
    }

    func testWalkDoesNotAdvanceAtBatCount() {
        launch(extraArguments: ["-demoSeedEmpty"])
        waitForHittable(app.buttons["playerRow-Ari Chen"]).tap()

        // Slash header shows "<n> AB" — verify AB count starts at 0.
        XCTAssertTrue(app.staticTexts["0 AB"].waitForExistence(timeout: 4))

        atBatButton("walk").tap()

        // BB doesn't increment AB.
        XCTAssertTrue(app.staticTexts["0 AB"].waitForExistence(timeout: 4))
    }

    func testEveryOutcomeButtonExistsAndIsHittable() {
        launch(extraArguments: ["-demoSeedEmpty"])
        waitForHittable(app.buttons["playerRow-Jordan Davis"]).tap()

        let outcomes = [
            "single", "double", "triple", "homeRun",
            "walk", "strikeout", "stolenBase", "rbi",
            "groundOut", "reachedOnError", "lineOut", "bunt",
        ]
        // Scroll the at-bat pad into view first.
        if !app.buttons["atBat-single"].isHittable { app.swipeUp() }

        for o in outcomes {
            let button = app.buttons["atBat-\(o)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing at-bat button for \(o)")
            XCTAssertTrue(button.exists, "atBat-\(o) should exist in hierarchy")
        }
    }
}
