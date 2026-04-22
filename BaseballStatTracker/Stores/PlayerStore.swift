import Foundation
import Combine

/// Start marker for a game on a given day. Up to 3 per player per day.
/// `startTime` is when the user opened the tracker for that game.
struct GameSession: Identifiable, Codable, Hashable {
    let id: UUID
    let playerID: UUID
    var startTime: Date
    var gameNumber: Int

    init(id: UUID = UUID(), playerID: UUID, startTime: Date = .now, gameNumber: Int) {
        self.id = id
        self.playerID = playerID
        self.startTime = startTime
        self.gameNumber = gameNumber
    }
}

/// Key identifying one recorded game: the calendar day plus the game number
/// within that day.
struct DayGameKey: Hashable, Identifiable {
    let day: Date
    let gameNumber: Int
    var id: String { "\(day.timeIntervalSince1970)-\(gameNumber)" }
}

@MainActor
final class PlayerStore: ObservableObject {
    static let maxGamesPerDay = 3

    @Published var players: [Player] = []
    @Published var atBats: [AtBatEntry] = []
    @Published var teams: [String] = []
    @Published var gameSessions: [GameSession] = []

    private let playersURL: URL
    private let atBatsURL: URL
    private let teamsURL: URL
    private let gameSessionsURL: URL
    private var saveTask: Task<Void, Never>?

    init(filenamePrefix: String = "bst") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.playersURL = dir.appendingPathComponent("\(filenamePrefix)-players.json")
        self.atBatsURL = dir.appendingPathComponent("\(filenamePrefix)-atbats.json")
        self.teamsURL = dir.appendingPathComponent("\(filenamePrefix)-teams.json")
        self.gameSessionsURL = dir.appendingPathComponent("\(filenamePrefix)-gamesessions.json")
        load()
    }

    /// Remember a team name so it shows up in the picker next time.
    /// Case-insensitive dedupe against existing entries; preserves the
    /// first-seen capitalization ("Yankees" wins over later "yankees").
    func rememberTeam(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !teams.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            teams.append(trimmed)
            teams.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            scheduleSave()
        }
    }

    // MARK: - Players

    func addPlayer(_ player: Player) {
        players.append(player)
        scheduleSave()
    }

    func update(_ player: Player) {
        guard let idx = players.firstIndex(where: { $0.id == player.id }) else { return }
        players[idx] = player
        scheduleSave()
    }

    func delete(at offsets: IndexSet) {
        let removed = offsets.map { players[$0].id }
        players.remove(atOffsets: offsets)
        atBats.removeAll { removed.contains($0.playerID) }
        gameSessions.removeAll { removed.contains($0.playerID) }
        scheduleSave()
    }

    // MARK: - At-bats

    @discardableResult
    func recordAtBat(
        for playerID: Player.ID,
        outcome: AtBatOutcome,
        contact: ContactQuality? = nil,
        at date: Date = .now,
        gameNumber: Int = 1
    ) -> AtBatEntry {
        let entry = AtBatEntry(
            playerID: playerID,
            date: date,
            outcome: outcome,
            contact: contact,
            gameNumber: gameNumber
        )
        atBats.append(entry)
        scheduleSave()
        return entry
    }

    /// Re-insert a previously removed entry (used by undo paths).
    func restore(_ entry: AtBatEntry) {
        atBats.append(entry)
        scheduleSave()
    }

    /// Bulk restore — single save after the batch.
    func restore(_ entries: [AtBatEntry]) {
        guard !entries.isEmpty else { return }
        atBats.append(contentsOf: entries)
        scheduleSave()
    }

    func deleteAtBat(id: AtBatEntry.ID) {
        atBats.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Wipes every roster, at-bat, team, and game-session entry — in memory and on disk.
    /// Used by the Delete Account flow; pairs with `AuthStore.deleteAccount()`.
    func deleteAllData() {
        saveTask?.cancel()
        saveTask = nil
        players.removeAll()
        atBats.removeAll()
        teams.removeAll()
        gameSessions.removeAll()
        for url in [playersURL, atBatsURL, teamsURL, gameSessionsURL] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Game sessions

    /// Sessions for a player on a given calendar day, sorted by gameNumber.
    func sessions(for playerID: Player.ID, on day: Date) -> [GameSession] {
        let cal = Calendar.current
        return gameSessions
            .filter { $0.playerID == playerID && cal.isDate($0.startTime, inSameDayAs: day) }
            .sorted { $0.gameNumber < $1.gameNumber }
    }

    /// Ensures a G1 session exists for `playerID` on `day`; returns all sessions.
    /// If at-bats already exist for that day, G1's start defaults to the earliest
    /// at-bat time so pre-existing data lines up with its implicit first game.
    @discardableResult
    func ensureG1Session(for playerID: Player.ID, on day: Date) -> [GameSession] {
        let existing = sessions(for: playerID, on: day)
        if !existing.isEmpty { return existing }
        let cal = Calendar.current
        let sameDayAtBats = atBats
            .filter { $0.playerID == playerID && cal.isDate($0.date, inSameDayAs: day) }
            .map { $0.date }
            .sorted()
        let start = sameDayAtBats.first ?? Date.now
        let session = GameSession(playerID: playerID, startTime: start, gameNumber: 1)
        gameSessions.append(session)
        scheduleSave()
        return [session]
    }

    /// Starts the next game of the day (G2 or G3). Returns nil if already at the
    /// per-day cap.
    @discardableResult
    func startNextGame(for playerID: Player.ID, on day: Date) -> GameSession? {
        let existing = sessions(for: playerID, on: day)
        let next = (existing.map { $0.gameNumber }.max() ?? 0) + 1
        guard next <= Self.maxGamesPerDay else { return nil }
        let session = GameSession(playerID: playerID, startTime: .now, gameNumber: next)
        gameSessions.append(session)
        scheduleSave()
        return session
    }

    func entries(for playerID: Player.ID) -> [AtBatEntry] {
        atBats
            .filter { $0.playerID == playerID }
            .sorted { $0.date > $1.date }
    }

    func entries(for playerID: Player.ID, on day: Date, gameNumber: Int) -> [AtBatEntry] {
        let cal = Calendar.current
        return atBats
            .filter {
                $0.playerID == playerID
                    && $0.gameNumber == gameNumber
                    && cal.isDate($0.date, inSameDayAs: day)
            }
            .sorted { $0.date > $1.date }
    }

    func stats(for playerID: Player.ID) -> PlayerStats {
        PlayerStats(entries: atBats.lazy.filter { $0.playerID == playerID })
    }

    func stats(for playerID: Player.ID, on day: Date, gameNumber: Int) -> PlayerStats {
        let cal = Calendar.current
        return PlayerStats(entries: atBats.lazy.filter {
            $0.playerID == playerID
                && $0.gameNumber == gameNumber
                && cal.isDate($0.date, inSameDayAs: day)
        })
    }

    /// One entry per (day, game) combination the player has started or recorded
    /// at-bats for. Sorted most-recent day first, then game number ascending.
    /// Sessions are included so a row appears immediately when "Add another game"
    /// is tapped, even before any at-bats land in it.
    func playerGames(for playerID: Player.ID) -> [DayGameKey] {
        let cal = Calendar.current
        var keys = Set<DayGameKey>()
        for ab in atBats where ab.playerID == playerID {
            keys.insert(DayGameKey(day: cal.startOfDay(for: ab.date), gameNumber: ab.gameNumber))
        }
        for s in gameSessions where s.playerID == playerID {
            keys.insert(DayGameKey(day: cal.startOfDay(for: s.startTime), gameNumber: s.gameNumber))
        }
        return Array(keys).sorted { a, b in
            if a.day != b.day { return a.day > b.day }
            return a.gameNumber < b.gameNumber
        }
    }

    // MARK: - Persistence

    private func load() {
        let decoder = jsonDecoder()
        if let data = try? Data(contentsOf: playersURL),
           let decoded = try? decoder.decode([Player].self, from: data) {
            players = decoded
        }
        if let data = try? Data(contentsOf: atBatsURL),
           let decoded = try? decoder.decode([AtBatEntry].self, from: data) {
            atBats = decoded
        }
        if let data = try? Data(contentsOf: teamsURL),
           let decoded = try? decoder.decode([String].self, from: data) {
            teams = decoded
        }
        if let data = try? Data(contentsOf: gameSessionsURL),
           let decoded = try? decoder.decode([GameSession].self, from: data) {
            gameSessions = decoded
        }
        // Back-fill teams from any existing players that pre-date the teams store.
        for player in players {
            if let t = player.team, !t.isEmpty {
                rememberTeam(t)
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self?.save()
        }
    }

    private func save() {
        let encoder = jsonEncoder()
        if let data = try? encoder.encode(players) {
            try? data.write(to: playersURL, options: [.atomic])
        }
        if let data = try? encoder.encode(atBats) {
            try? data.write(to: atBatsURL, options: [.atomic])
        }
        if let data = try? encoder.encode(teams) {
            try? data.write(to: teamsURL, options: [.atomic])
        }
        if let data = try? encoder.encode(gameSessions) {
            try? data.write(to: gameSessionsURL, options: [.atomic])
        }
    }

    private func jsonEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func jsonDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

enum AtBatOutcome: String, CaseIterable, Identifiable, Codable {
    case single, double, triple, homeRun
    case walk, strikeout
    case groundOut, flyOut, lineOut, out
    case stolenBase, rbi
    case reachedOnError, bunt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "+1B"
        case .double: return "+2B"
        case .triple: return "+3B"
        case .homeRun: return "+HR"
        case .walk: return "+BB"
        case .strikeout: return "K"
        case .groundOut: return "GO"
        case .flyOut: return "FO"
        case .lineOut: return "LO"
        case .out: return "OUT"
        case .stolenBase: return "+SB"
        case .rbi: return "+RBI"
        case .reachedOnError: return "+ROE"
        case .bunt: return "+BU"
        }
    }

    var isHit: Bool {
        switch self {
        case .single, .double, .triple, .homeRun: return true
        default: return false
        }
    }

    /// Whether this outcome counts as an official at-bat (AB).
    /// Walks, stolen bases, RBI-only adjustments, and bunts do not.
    var countsAsAtBat: Bool {
        switch self {
        case .walk, .stolenBase, .rbi, .bunt: return false
        default: return true
        }
    }
}
