import XCTest
@testable import BaseballStatTracker

final class AtBatOutcomeTests: XCTestCase {
    func testIsHit() {
        let hits: [AtBatOutcome] = [.single, .double, .triple, .homeRun]
        for o in hits { XCTAssertTrue(o.isHit, "\(o) should be a hit") }
        let nonHits: [AtBatOutcome] = [.walk, .strikeout, .groundOut, .flyOut, .lineOut, .out, .stolenBase, .rbi, .reachedOnError, .bunt]
        for o in nonHits { XCTAssertFalse(o.isHit, "\(o) should not be a hit") }
    }

    func testCountsAsAtBat() {
        let nonAB: [AtBatOutcome] = [.walk, .stolenBase, .rbi, .bunt]
        for o in nonAB { XCTAssertFalse(o.countsAsAtBat, "\(o) should not count as AB") }
        let countsAB: [AtBatOutcome] = [.single, .double, .triple, .homeRun, .strikeout, .groundOut, .flyOut, .lineOut, .out, .reachedOnError]
        for o in countsAB { XCTAssertTrue(o.countsAsAtBat, "\(o) should count as AB") }
    }

    func testEveryCaseHasNonEmptyLabel() {
        for outcome in AtBatOutcome.allCases {
            XCTAssertFalse(outcome.label.isEmpty, "\(outcome) needs a label")
        }
    }

    func testRawValueRoundTrip() {
        for outcome in AtBatOutcome.allCases {
            XCTAssertEqual(AtBatOutcome(rawValue: outcome.rawValue), outcome)
        }
    }

    func testIDMatchesRawValue() {
        for outcome in AtBatOutcome.allCases {
            XCTAssertEqual(outcome.id, outcome.rawValue)
        }
    }
}

final class ContactQualityHitLocationTests: XCTestCase {
    func testContactQualityCases() {
        XCTAssertEqual(Set(ContactQuality.allCases), [.strong, .weak])
        XCTAssertEqual(ContactQuality.strong.label, "Strong")
        XCTAssertEqual(ContactQuality.weak.label, "Weak")
    }

    func testHitLocationCases() {
        XCTAssertEqual(Set(HitLocation.allCases), [.left, .center, .right])
        XCTAssertEqual(HitLocation.left.label, "Left")
        XCTAssertEqual(HitLocation.center.label, "Center")
        XCTAssertEqual(HitLocation.right.label, "Right")
    }
}
