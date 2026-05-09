import XCTest
@testable import BaseballStatTracker

final class StatFormatterTests: XCTestCase {
    func testZeroFormattedAsLeadingDot() {
        XCTAssertEqual(StatFormatter.avg(0), ".000")
    }

    func testFractionalAveragesDropLeadingZero() {
        XCTAssertEqual(StatFormatter.avg(0.250), ".250")
        XCTAssertEqual(StatFormatter.avg(0.333), ".333")
    }

    func testOneOrAboveKeepsLeadingDigit() {
        XCTAssertEqual(StatFormatter.avg(1.0), "1.000")
        XCTAssertEqual(StatFormatter.avg(1.234), "1.234")
        XCTAssertEqual(StatFormatter.avg(2.5), "2.500")
    }

    func testRoundsToThreeDecimals() {
        XCTAssertEqual(StatFormatter.avg(0.3333333), ".333")
    }
}
