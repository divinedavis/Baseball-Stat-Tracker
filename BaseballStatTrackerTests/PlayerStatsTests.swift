import XCTest
@testable import BaseballStatTracker

final class PlayerStatsTests: XCTestCase {
    private let pid = UUID()

    private func entry(_ outcome: AtBatOutcome) -> AtBatEntry {
        AtBatEntry(playerID: pid, outcome: outcome)
    }

    func testEmptyStatsAreZero() {
        let stats = PlayerStats(entries: [AtBatEntry]())
        XCTAssertEqual(stats.atBats, 0)
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.battingAverage, 0)
        XCTAssertEqual(stats.onBasePercentage, 0)
        XCTAssertEqual(stats.sluggingPercentage, 0)
        XCTAssertEqual(stats.ops, 0)
    }

    func testSingleHit() {
        let stats = PlayerStats(entries: [entry(.single)])
        XCTAssertEqual(stats.atBats, 1)
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.singles, 1)
        XCTAssertEqual(stats.battingAverage, 1.0)
        XCTAssertEqual(stats.onBasePercentage, 1.0)
        XCTAssertEqual(stats.sluggingPercentage, 1.0)
        XCTAssertEqual(stats.ops, 2.0)
    }

    func testHomeRunIncrementsRBIAndSlug() {
        let stats = PlayerStats(entries: [entry(.homeRun)])
        XCTAssertEqual(stats.atBats, 1)
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.homeRuns, 1)
        XCTAssertEqual(stats.runsBattedIn, 1)
        XCTAssertEqual(stats.singles, 0)
        XCTAssertEqual(stats.battingAverage, 1.0)
        XCTAssertEqual(stats.sluggingPercentage, 4.0)
        XCTAssertEqual(stats.ops, 5.0)
    }

    func testWalkDoesNotCountAsAtBat() {
        let stats = PlayerStats(entries: [entry(.walk)])
        XCTAssertEqual(stats.atBats, 0)
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.walks, 1)
        XCTAssertEqual(stats.battingAverage, 0)
        XCTAssertEqual(stats.onBasePercentage, 1.0)
        XCTAssertEqual(stats.sluggingPercentage, 0)
        XCTAssertEqual(stats.ops, 1.0)
    }

    func testStrikeoutCountsAsAtBatNoHit() {
        let stats = PlayerStats(entries: [entry(.strikeout)])
        XCTAssertEqual(stats.atBats, 1)
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.strikeouts, 1)
        XCTAssertEqual(stats.battingAverage, 0)
        XCTAssertEqual(stats.onBasePercentage, 0)
    }

    func testStolenBaseDoesNotCountAsAtBat() {
        let stats = PlayerStats(entries: [entry(.stolenBase)])
        XCTAssertEqual(stats.atBats, 0)
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.stolenBases, 1)
        XCTAssertEqual(stats.battingAverage, 0)
    }

    func testRBIOnlyEntry() {
        let stats = PlayerStats(entries: [entry(.rbi)])
        XCTAssertEqual(stats.atBats, 0)
        XCTAssertEqual(stats.runsBattedIn, 1)
    }

    func testBuntDoesNotCountAsAtBat() {
        let stats = PlayerStats(entries: [entry(.bunt)])
        XCTAssertEqual(stats.atBats, 0)
        XCTAssertEqual(stats.bunts, 1)
    }

    func testReachedOnErrorCountsAsAtBatNoHit() {
        let stats = PlayerStats(entries: [entry(.reachedOnError)])
        XCTAssertEqual(stats.atBats, 1)
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.reachedOnErrors, 1)
        XCTAssertEqual(stats.battingAverage, 0)
    }

    func testGroundFlyLineOuts() {
        let stats = PlayerStats(entries: [entry(.groundOut), entry(.flyOut), entry(.lineOut), entry(.out)])
        XCTAssertEqual(stats.atBats, 4)
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.groundOuts, 1)
        XCTAssertEqual(stats.flyOuts, 1)
        XCTAssertEqual(stats.lineOuts, 1)
    }

    func testMixedSeasonAverages() {
        // 1B, 2B, 3B, HR plus 6 strikeouts = 4 hits in 10 AB → .400
        let outcomes: [AtBatOutcome] = [.single, .double, .triple, .homeRun] + Array(repeating: .strikeout, count: 6)
        let stats = PlayerStats(entries: outcomes.map(entry))
        XCTAssertEqual(stats.atBats, 10)
        XCTAssertEqual(stats.hits, 4)
        XCTAssertEqual(stats.singles, 1)
        XCTAssertEqual(stats.doubles, 1)
        XCTAssertEqual(stats.triples, 1)
        XCTAssertEqual(stats.homeRuns, 1)
        XCTAssertEqual(stats.battingAverage, 0.4, accuracy: 0.0001)
        // Total bases = 1 + 2 + 3 + 4 = 10; SLG = 1.000
        XCTAssertEqual(stats.sluggingPercentage, 1.0, accuracy: 0.0001)
        // OBP = (hits + walks) / (AB + walks) = 4/10 = 0.400
        XCTAssertEqual(stats.onBasePercentage, 0.4, accuracy: 0.0001)
        XCTAssertEqual(stats.ops, 1.4, accuracy: 0.0001)
    }

    func testWalksCountInOBPDenominator() {
        // 1 hit in 4 AB, plus 2 walks
        let outcomes: [AtBatOutcome] = [.single, .strikeout, .strikeout, .strikeout, .walk, .walk]
        let stats = PlayerStats(entries: outcomes.map(entry))
        XCTAssertEqual(stats.atBats, 4)
        XCTAssertEqual(stats.walks, 2)
        XCTAssertEqual(stats.battingAverage, 0.25, accuracy: 0.0001)
        // OBP = (1 + 2) / (4 + 2) = 0.500
        XCTAssertEqual(stats.onBasePercentage, 0.5, accuracy: 0.0001)
    }

    func testSinglesIsNeverNegative() {
        // Defensive: even with weird inputs, singles stays >= 0.
        var stats = PlayerStats(entries: [AtBatEntry]())
        stats.apply(.double)
        XCTAssertEqual(stats.singles, 0)
    }

    func testApplyMutatesInPlace() {
        var stats = PlayerStats(entries: [AtBatEntry]())
        stats.apply(.single)
        stats.apply(.homeRun)
        XCTAssertEqual(stats.atBats, 2)
        XCTAssertEqual(stats.hits, 2)
        XCTAssertEqual(stats.homeRuns, 1)
        XCTAssertEqual(stats.runsBattedIn, 1)
    }
}
