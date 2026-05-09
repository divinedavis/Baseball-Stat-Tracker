import XCTest

final class UndoRedoUITests: BarrelUITestCase {
    func testUndoButtonStartsDisabledThenEnablesAfterAtBat() {
        launch(extraArguments: ["-demoSeedEmpty"])
        waitForHittable(app.buttons["playerRow-Jordan Davis"], timeout: 12).tap()

        let undo = waitFor(app.buttons["undoButton"])
        XCTAssertFalse(undo.isEnabled, "Undo should be disabled with no history")

        atBatButton("single").tap()
        // Re-fetch and wait — `isEnabled` snapshots at query time and the
        // toolbar item flips enabled state asynchronously after the at-bat
        // is committed to the UndoHistory.
        let undoEnabled = NSPredicate(format: "isEnabled == true")
        expectation(for: undoEnabled, evaluatedWith: app.buttons["undoButton"])
        waitForExpectations(timeout: 6)
    }

    func testUndoReversesAtBat() {
        launch(extraArguments: ["-demoSeedEmpty"])
        waitForHittable(app.buttons["playerRow-Jordan Davis"], timeout: 12).tap()

        atBatButton("single").tap()
        let avg = app.staticTexts["statValue-AVG"]
        let after = NSPredicate(format: "label == %@", "1.000")
        expectation(for: after, evaluatedWith: avg)
        waitForExpectations(timeout: 6)

        waitFor(app.buttons["undoButton"]).tap()

        let reset = NSPredicate(format: "label == %@", ".000")
        expectation(for: reset, evaluatedWith: app.staticTexts["statValue-AVG"])
        waitForExpectations(timeout: 6)
    }

    func testRedoReplaysAtBat() {
        launch(extraArguments: ["-demoSeedEmpty"])
        waitForHittable(app.buttons["playerRow-Jordan Davis"], timeout: 12).tap()

        atBatButton("double").tap()
        waitFor(app.buttons["undoButton"]).tap()

        // After undo, redo should be enabled — wait for it asynchronously
        // because the toolbar item flips state after the UndoHistory
        // refresh hops to MainActor.
        let redo = app.buttons["redoButton"]
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: redo)
        waitForExpectations(timeout: 6)
        redo.tap()

        // Slugging after one 2B = 2.000
        let predicate = NSPredicate(format: "label == %@", "2.000")
        expectation(for: predicate, evaluatedWith: app.staticTexts["statValue-SLG"])
        waitForExpectations(timeout: 6)
    }
}
