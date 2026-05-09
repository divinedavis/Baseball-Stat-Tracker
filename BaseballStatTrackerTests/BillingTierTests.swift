import XCTest
@testable import BaseballStatTracker

final class AITierTests: XCTestCase {
    func testFreeTierLimits() {
        XCTAssertEqual(AITier.free.monthlySwings, 2)
        XCTAssertEqual(AITier.free.dailySwings, 2)
        XCTAssertEqual(AITier.free.monthlyQuestions, 5)
    }

    func testStandardTierLimits() {
        XCTAssertEqual(AITier.standard.monthlySwings, 15)
        XCTAssertEqual(AITier.standard.dailySwings, 5)
        XCTAssertEqual(AITier.standard.monthlyQuestions, 30)
    }

    func testProTierLimits() {
        XCTAssertEqual(AITier.pro.monthlySwings, 50)
        XCTAssertEqual(AITier.pro.dailySwings, 15)
        XCTAssertEqual(AITier.pro.monthlyQuestions, -1, "Pro is unlimited")
    }

    func testTierDisplayNames() {
        XCTAssertEqual(AITier.free.displayName, "Free")
        XCTAssertEqual(AITier.standard.displayName, "Barrel AI Standard")
        XCTAssertEqual(AITier.pro.displayName, "Barrel AI Pro")
    }

    func testRawValueRoundTrip() {
        XCTAssertEqual(AITier(rawValue: "free"), .free)
        XCTAssertEqual(AITier(rawValue: "standard"), .standard)
        XCTAssertEqual(AITier(rawValue: "pro"), .pro)
        XCTAssertNil(AITier(rawValue: "platinum"))
    }
}
