import XCTest
@testable import BaseballStatTracker

@MainActor
final class PlayerStoreTests: XCTestCase {
    private var prefix: String = ""

    override func setUp() async throws {
        // Each test gets a unique prefix so the on-disk JSON files never
        // collide across tests, and we can wipe them in tearDown.
        prefix = "bst-test-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        wipeDocs(prefix: prefix)
    }

    private func wipeDocs(prefix: String) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        for kind in ["players", "atbats", "teams", "gamesessions"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(prefix)-\(kind).json"))
        }
    }

    private func makeStore() -> PlayerStore {
        PlayerStore(filenamePrefix: prefix)
    }

    private func samplePlayer(name: String = "Jordan") -> Player {
        Player(name: name, number: 7, position: "CF", age: 10, team: "Thunder")
    }

    // MARK: - Players CRUD

    func testAddPlayer() {
        let store = makeStore()
        store.addPlayer(samplePlayer())
        XCTAssertEqual(store.players.count, 1)
        XCTAssertEqual(store.players.first?.name, "Jordan")
    }

    func testUpdatePlayer() {
        let store = makeStore()
        var p = samplePlayer()
        store.addPlayer(p)
        p.name = "Jordan Davis"
        store.update(p)
        XCTAssertEqual(store.players.first?.name, "Jordan Davis")
    }

    func testUpdatePlayerNoOpsWhenIDMissing() {
        let store = makeStore()
        store.addPlayer(samplePlayer())
        let ghost = Player(id: UUID(), name: "Ghost", number: 0, position: "P")
        store.update(ghost)
        XCTAssertEqual(store.players.count, 1)
        XCTAssertEqual(store.players.first?.name, "Jordan")
    }

    func testDeletePlayerCascadesAtBatsAndSessions() {
        let store = makeStore()
        let jordan = samplePlayer(name: "Jordan")
        let ari = samplePlayer(name: "Ari")
        store.addPlayer(jordan)
        store.addPlayer(ari)
        store.recordAtBat(for: jordan.id, outcome: .single)
        store.recordAtBat(for: ari.id, outcome: .double)
        store.ensureG1Session(for: jordan.id, on: .now)

        store.delete(at: IndexSet(integer: 0))

        XCTAssertEqual(store.players.count, 1)
        XCTAssertEqual(store.players.first?.id, ari.id)
        XCTAssertTrue(store.atBats.allSatisfy { $0.playerID == ari.id })
        XCTAssertTrue(store.gameSessions.allSatisfy { $0.playerID == ari.id })
    }

    // MARK: - At-bats

    func testRecordAtBatAppends() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        let entry = store.recordAtBat(for: p.id, outcome: .homeRun, contact: .strong, hitLocation: .center, gameNumber: 1)
        XCTAssertEqual(store.atBats.count, 1)
        XCTAssertEqual(store.atBats.first?.id, entry.id)
        XCTAssertEqual(store.atBats.first?.contact, .strong)
        XCTAssertEqual(store.atBats.first?.hitLocation, .center)
        XCTAssertEqual(store.atBats.first?.gameNumber, 1)
    }

    func testDeleteAtBatRemovesByID() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        let entry = store.recordAtBat(for: p.id, outcome: .single)
        store.deleteAtBat(id: entry.id)
        XCTAssertTrue(store.atBats.isEmpty)
    }

    func testRestoreReinsertsRemovedEntry() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        let entry = store.recordAtBat(for: p.id, outcome: .double)
        store.deleteAtBat(id: entry.id)
        store.restore(entry)
        XCTAssertEqual(store.atBats.count, 1)
        XCTAssertEqual(store.atBats.first?.id, entry.id)
    }

    func testBulkRestore() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        let entries = [
            store.recordAtBat(for: p.id, outcome: .single),
            store.recordAtBat(for: p.id, outcome: .double),
            store.recordAtBat(for: p.id, outcome: .homeRun),
        ]
        for e in entries { store.deleteAtBat(id: e.id) }
        XCTAssertTrue(store.atBats.isEmpty)
        store.restore(entries)
        XCTAssertEqual(store.atBats.count, 3)
    }

    func testUpdateAtBatReturnsPrevious() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        let entry = store.recordAtBat(for: p.id, outcome: .single)
        var edited = entry
        edited.outcome = .double
        let previous = store.updateAtBat(edited)
        XCTAssertEqual(previous?.outcome, .single)
        XCTAssertEqual(store.atBats.first?.outcome, .double)
    }

    func testUpdateAtBatReturnsNilForUnknownID() {
        let store = makeStore()
        let phantom = AtBatEntry(playerID: UUID(), outcome: .single)
        XCTAssertNil(store.updateAtBat(phantom))
    }

    func testDeleteAllDataWipesEverything() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        store.recordAtBat(for: p.id, outcome: .single)
        store.rememberTeam("Thunder")
        store.ensureG1Session(for: p.id, on: .now)

        store.deleteAllData()

        XCTAssertTrue(store.players.isEmpty)
        XCTAssertTrue(store.atBats.isEmpty)
        XCTAssertTrue(store.teams.isEmpty)
        XCTAssertTrue(store.gameSessions.isEmpty)
    }

    // MARK: - Stats

    func testStatsForPlayer() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        store.recordAtBat(for: p.id, outcome: .single)
        store.recordAtBat(for: p.id, outcome: .strikeout)
        let stats = store.stats(for: p.id)
        XCTAssertEqual(stats.atBats, 2)
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.battingAverage, 0.5)
    }

    func testStatsForGameOnDay() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        store.recordAtBat(for: p.id, outcome: .single, at: today, gameNumber: 1)
        store.recordAtBat(for: p.id, outcome: .strikeout, at: yesterday, gameNumber: 1)

        let todayStats = store.stats(for: p.id, on: today, gameNumber: 1)
        XCTAssertEqual(todayStats.atBats, 1)
        XCTAssertEqual(todayStats.hits, 1)

        let yesterdayStats = store.stats(for: p.id, on: yesterday, gameNumber: 1)
        XCTAssertEqual(yesterdayStats.atBats, 1)
        XCTAssertEqual(yesterdayStats.hits, 0)
    }

    // MARK: - Game sessions

    func testEnsureG1SessionCreatesOnce() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        let first = store.ensureG1Session(for: p.id, on: .now)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.gameNumber, 1)
        let second = store.ensureG1Session(for: p.id, on: .now)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.id, first.first?.id)
    }

    func testStartNextGameCapsAtThree() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        let day = Date.now
        store.ensureG1Session(for: p.id, on: day)
        let g2 = store.startNextGame(for: p.id, on: day)
        let g3 = store.startNextGame(for: p.id, on: day)
        let g4 = store.startNextGame(for: p.id, on: day)
        XCTAssertEqual(g2?.gameNumber, 2)
        XCTAssertEqual(g3?.gameNumber, 3)
        XCTAssertNil(g4, "PlayerStore.maxGamesPerDay must reject a 4th game")
    }

    func testTotalGamesLoggedDeduplicatesByDayAndNumber() {
        let store = makeStore()
        let jordan = samplePlayer(name: "Jordan")
        let ari = samplePlayer(name: "Ari")
        store.addPlayer(jordan)
        store.addPlayer(ari)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // Two players sharing the same (day, gameNumber) only counts once.
        store.recordAtBat(for: jordan.id, outcome: .single, at: today, gameNumber: 1)
        store.recordAtBat(for: ari.id, outcome: .single, at: today, gameNumber: 1)
        XCTAssertEqual(store.totalGamesLogged, 1)
        // Same day, different game number = 2.
        store.recordAtBat(for: jordan.id, outcome: .double, at: today, gameNumber: 2)
        XCTAssertEqual(store.totalGamesLogged, 2)
    }

    func testPlayerGamesSortedByDayThenGameNumber() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        store.recordAtBat(for: p.id, outcome: .single, at: today, gameNumber: 2)
        store.recordAtBat(for: p.id, outcome: .double, at: today, gameNumber: 1)
        store.recordAtBat(for: p.id, outcome: .triple, at: yesterday, gameNumber: 1)

        let games = store.playerGames(for: p.id)
        XCTAssertEqual(games.count, 3)
        XCTAssertEqual(games[0].day, cal.startOfDay(for: yesterday))
        XCTAssertEqual(games[0].gameNumber, 1)
        XCTAssertEqual(games[1].day, today)
        XCTAssertEqual(games[1].gameNumber, 1)
        XCTAssertEqual(games[2].day, today)
        XCTAssertEqual(games[2].gameNumber, 2)
    }

    // MARK: - Teams

    func testRememberTeamDedupesCaseInsensitively() {
        let store = makeStore()
        store.rememberTeam("Yankees")
        store.rememberTeam("yankees")
        store.rememberTeam("YANKEES")
        XCTAssertEqual(store.teams, ["Yankees"])
    }

    func testRememberTeamSortsAlphabetically() {
        let store = makeStore()
        store.rememberTeam("Yankees")
        store.rememberTeam("Athletics")
        store.rememberTeam("Mets")
        XCTAssertEqual(store.teams, ["Athletics", "Mets", "Yankees"])
    }

    func testRememberTeamIgnoresWhitespace() {
        let store = makeStore()
        store.rememberTeam("   ")
        store.rememberTeam("")
        XCTAssertTrue(store.teams.isEmpty)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() async throws {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        store.recordAtBat(for: p.id, outcome: .homeRun, contact: .strong, hitLocation: .right, gameNumber: 2)
        store.rememberTeam("Thunder")
        store.ensureG1Session(for: p.id, on: .now)
        // The store debounces saves by 200ms — wait long enough for the
        // background save Task to flush before re-reading from disk.
        try await Task.sleep(nanoseconds: 500_000_000)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.players.count, 1)
        XCTAssertEqual(reloaded.players.first?.name, "Jordan")
        XCTAssertEqual(reloaded.atBats.count, 1)
        XCTAssertEqual(reloaded.atBats.first?.outcome, .homeRun)
        XCTAssertEqual(reloaded.atBats.first?.contact, .strong)
        XCTAssertEqual(reloaded.atBats.first?.hitLocation, .right)
        XCTAssertEqual(reloaded.atBats.first?.gameNumber, 2)
        XCTAssertEqual(reloaded.teams, ["Thunder"])
        XCTAssertEqual(reloaded.gameSessions.count, 1)
    }

    func testEntriesForPlayerSortedNewestFirst() {
        let store = makeStore()
        let p = samplePlayer()
        store.addPlayer(p)
        let early = Date(timeIntervalSinceNow: -3600)
        let mid = Date(timeIntervalSinceNow: -1800)
        let late = Date.now
        store.recordAtBat(for: p.id, outcome: .single, at: mid)
        store.recordAtBat(for: p.id, outcome: .double, at: late)
        store.recordAtBat(for: p.id, outcome: .triple, at: early)
        let entries = store.entries(for: p.id)
        XCTAssertEqual(entries.map(\.outcome), [.double, .single, .triple])
    }
}
