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
        XCTAssertEqual(AITier.pro.monthlyQuestions, 1000, "matches tier_limits.pro on the server")
    }

    func testNoTierIsUnlimited() {
        for tier in [AITier.free, .standard, .pro] {
            XCTAssertGreaterThan(tier.monthlyQuestions, 0)
            XCTAssertFalse(tier.questionAllowance.lowercased().contains("unlimited"))
            XCTAssertFalse(tier.planSummary.lowercased().contains("unlimited"))
        }
    }

    func testAllowanceCopy() {
        XCTAssertEqual(AITier.pro.questionAllowance, "Up to 1,000 AI coach questions a month")
        XCTAssertEqual(AITier.standard.questionAllowance, "Up to 30 AI coach questions a month")
        XCTAssertEqual(AITier.pro.planSummary, "50 swing analyses + up to 1,000 AI questions a month")
        XCTAssertEqual(AITier.standard.planSummary, "15 swing analyses + up to 30 AI questions a month")
    }

    func testPerMinuteLimitsMatchServer() {
        XCTAssertEqual(AITier.questionsPerMinute, 10)
        XCTAssertEqual(AITier.swingsPerMinute, 3)
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
