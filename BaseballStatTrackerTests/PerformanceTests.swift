import XCTest
@testable import BaseballStatTracker

@MainActor
final class PerformanceTests: XCTestCase {
    func testStatsComputationOverLargeEntrySet() {
        let pid = UUID()
        let outcomes: [AtBatOutcome] = [.single, .double, .triple, .homeRun, .walk, .strikeout, .groundOut, .flyOut]
        let entries = (0..<10_000).map {
            AtBatEntry(playerID: pid, outcome: outcomes[$0 % outcomes.count])
        }
        measure {
            _ = PlayerStats(entries: entries)
        }
    }

    func testPlayerStorePersistenceWith1000AtBats() async throws {
        let prefix = "bst-perf-\(UUID().uuidString)"
        defer { wipe(prefix: prefix) }

        let store = PlayerStore(filenamePrefix: prefix)
        let player = Player(name: "Perf", number: 1, position: "CF")
        store.addPlayer(player)
        for i in 0..<1_000 {
            store.recordAtBat(for: player.id, outcome: i % 3 == 0 ? .single : .strikeout)
        }
        try await Task.sleep(nanoseconds: 600_000_000) // let debounced save flush

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            // Re-loading a populated store is the user-visible cold-start cost.
            _ = PlayerStore(filenamePrefix: prefix)
        }
    }

    func testUndoStackPushAndPopThroughput() {
        let history = UndoHistory()
        measure {
            for _ in 0..<5_000 {
                history.register(undo: {}, redo: {})
            }
            for _ in 0..<5_000 {
                history.undo()
            }
            history.clear()
        }
    }

    private func wipe(prefix: String) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        for kind in ["players", "atbats", "teams", "gamesessions"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(prefix)-\(kind).json"))
        }
    }
}
