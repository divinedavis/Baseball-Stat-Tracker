import XCTest

/// Shared base class for Barrel XCUITests. Each test launches a fresh app
/// instance with a known starting state so runs are deterministic.
class BarrelUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Launch with `-uiTestReset` plus optional extras (e.g. `-demoSeedEmpty`
    /// for a 3-player roster, `-demoSeed` for a roster with at-bats).
    @discardableResult
    func launch(extraArguments extras: [String] = []) -> XCUIApplication {
        app.launchArguments = ["-uiTestReset"] + extras
        app.launch()
        return app
    }

    /// Wait for an element to appear; XCTFail if it never does. Returns the
    /// element so callers can chain a tap.
    @discardableResult
    func waitFor(_ element: XCUIElement, timeout: TimeInterval = 6, file: StaticString = #file, line: UInt = #line) -> XCUIElement {
        if !element.waitForExistence(timeout: timeout) {
            XCTFail("Element \(element) never appeared within \(timeout)s", file: file, line: line)
        }
        return element
    }

    /// Wait until the element is hittable (laid out, on-screen, accepts taps).
    /// Use this before tapping toolbar buttons that might not be ready
    /// immediately after a navigation transition.
    @discardableResult
    func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #file, line: UInt = #line) -> XCUIElement {
        let predicate = NSPredicate(format: "exists == true && hittable == true")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: element)
        if XCTWaiter().wait(for: [exp], timeout: timeout) != .completed {
            XCTFail("Element \(element) never became hittable within \(timeout)s", file: file, line: line)
        }
        return element
    }

    /// Scroll the at-bat pad into view if needed and return the button for
    /// the given outcome. Up to six swipes — the pad is always reachable
    /// from the detail view.
    @discardableResult
    func atBatButton(_ outcome: String, file: StaticString = #file, line: UInt = #line) -> XCUIElement {
        let button = app.buttons["atBat-\(outcome)"]
        // First wait for it to exist in the hierarchy at all — SwiftUI lazy
        // sections only realize children once their cell is near the
        // visible window.
        for attempt in 0..<6 {
            if button.exists && button.isHittable { return button }
            if attempt == 0 && button.waitForExistence(timeout: 2) {
                if button.isHittable { return button }
            }
            app.swipeUp()
        }
        if !button.waitForExistence(timeout: 4) {
            XCTFail("atBat-\(outcome) never came into view", file: file, line: line)
        }
        return button
    }
}
