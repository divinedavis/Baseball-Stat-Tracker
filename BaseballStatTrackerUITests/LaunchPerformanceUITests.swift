import XCTest

/// Tracks app cold-launch time over Xcode's baseline so a regression in the
/// startup path (e.g. blocking Supabase calls, heavy view init) shows up
/// as a measurable XCT metric failure.
final class LaunchPerformanceUITests: BarrelUITestCase {
    func testColdLaunchPerformance() throws {
        if #available(iOS 17, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = XCUIApplication()
                app.launchArguments = ["-uiTestSignedIn"]
                app.launch()
                app.terminate()
            }
        } else {
            throw XCTSkip("Launch metric requires iOS 17+")
        }
    }
}
