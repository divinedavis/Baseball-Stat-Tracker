import XCTest
@testable import BaseballStatTracker

@MainActor
final class AppIconSchedulerTests: XCTestCase {
    /// Helper — build a Date for a given hour in America/New_York.
    private func dateAt(hourET: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: hourET))!
    }

    func testIsNightAtMidnightET() {
        XCTAssertTrue(AppIconScheduler.isNight(now: dateAt(hourET: 0)))
    }

    func testIsNightAtFiveAMET() {
        XCTAssertTrue(AppIconScheduler.isNight(now: dateAt(hourET: 5)))
    }

    func testIsNotNightAtSixAMET() {
        XCTAssertFalse(AppIconScheduler.isNight(now: dateAt(hourET: 6)))
    }

    func testIsNotNightAtNoonET() {
        XCTAssertFalse(AppIconScheduler.isNight(now: dateAt(hourET: 12)))
    }

    func testIsNotNightAtSevenPMET() {
        XCTAssertFalse(AppIconScheduler.isNight(now: dateAt(hourET: 19)))
    }

    func testIsNightAtEightPMET() {
        XCTAssertTrue(AppIconScheduler.isNight(now: dateAt(hourET: 20)))
    }

    func testIsNightAtElevenPMET() {
        XCTAssertTrue(AppIconScheduler.isNight(now: dateAt(hourET: 23)))
    }
}
