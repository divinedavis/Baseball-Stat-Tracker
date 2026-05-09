import XCTest

/// Smoke tests that just confirm the app launches into the right surface
/// based on its launch arguments. These run fast and catch the
/// "everything's broken" regression class.
final class AppLaunchUITests: BarrelUITestCase {
    func testSignedOutLaunchShowsAuthScreen() {
        // -uiTestSignedOut wipes Documents/ + UserDefaults + the cached
        // session from the Keychain so we land on AuthView for sure.
        let unauth = XCUIApplication()
        unauth.launchArguments = ["-uiTestSignedOut"]
        unauth.launch()
        XCTAssertTrue(unauth.buttons["Continue with email"].waitForExistence(timeout: 8))
        unauth.terminate()
    }

    func testUITestResetSignsIntoEmptyRoster() {
        launch()
        XCTAssertTrue(app.staticTexts["No players yet"].waitForExistence(timeout: 8))
    }

    func testDemoSeedFullProducesPopulatedRoster() {
        launch(extraArguments: ["-demoSeed"])
        let row = waitForHittable(app.buttons["playerRow-Jordan Davis"], timeout: 12)
        row.tap()
        let avg = waitFor(app.staticTexts["statValue-AVG"], timeout: 12)
        XCTAssertNotEqual(avg.label, ".000", "Seeded Jordan should already have hits")
    }
}
