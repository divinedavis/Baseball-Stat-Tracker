import Foundation
import Combine

@MainActor
final class PlayerStore: ObservableObject {
    @Published var players: [Player] = []
    @Published var atBats: [AtBatEntry] = []
    @Published var teams: [String] = []

    private let playersURL: URL
    private let atBatsURL: URL
    private let teamsURL: URL
    private var saveTask: Task<Void, Never>?

    init(filenamePrefix: String = "bst") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.playersURL = dir.appendingPathComponent("\(filenamePrefix)-players.json")
        self.atBatsURL = dir.appendingPathComponent("\(filenamePrefix)-atbats.json")
        self.teamsURL = dir.appendingPathComponent("\(filenamePrefix)-teams.json")
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
        scheduleSave()
    }

    // MARK: - At-bats

    func recordAtBat(
        for playerID: Player.ID,
        outcome: AtBatOutcome,
        contact: ContactQuality? = nil,
        at date: Date = .now
    ) {
        atBats.append(AtBatEntry(
            playerID: playerID,
            date: date,
            outcome: outcome,
            contact: contact
        ))
        scheduleSave()
    }

    func deleteAtBat(id: AtBatEntry.ID) {
        atBats.removeAll { $0.id == id }
        scheduleSave()
    }

    func entries(for playerID: Player.ID) -> [AtBatEntry] {
        atBats
            .filter { $0.playerID == playerID }
            .sorted { $0.date > $1.date }
    }

    func entries(for playerID: Player.ID, on day: Date) -> [AtBatEntry] {
        let cal = Calendar.current
        return atBats
            .filter { $0.playerID == playerID && cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    func stats(for playerID: Player.ID) -> PlayerStats {
        PlayerStats(entries: atBats.lazy.filter { $0.playerID == playerID })
    }

    func stats(for playerID: Player.ID, on day: Date) -> PlayerStats {
        let cal = Calendar.current
        return PlayerStats(entries: atBats.lazy.filter {
            $0.playerID == playerID && cal.isDate($0.date, inSameDayAs: day)
        })
    }

    /// Days on which this player has at least one entry, sorted most-recent first.
    func activeDays(for playerID: Player.ID) -> [Date] {
        let cal = Calendar.current
        let starts = atBats
            .filter { $0.playerID == playerID }
            .map { cal.startOfDay(for: $0.date) }
        return Array(Set(starts)).sorted(by: >)
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: playersURL),
           let decoded = try? JSONDecoder().decode([Player].self, from: data) {
            players = decoded
        }
        if let data = try? Data(contentsOf: atBatsURL),
           let decoded = try? jsonDecoder().decode([AtBatEntry].self, from: data) {
            atBats = decoded
        }
        if let data = try? Data(contentsOf: teamsURL),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            teams = decoded
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
        if let data = try? JSONEncoder().encode(players) {
            try? data.write(to: playersURL, options: [.atomic])
        }
        if let data = try? jsonEncoder().encode(atBats) {
            try? data.write(to: atBatsURL, options: [.atomic])
        }
        if let data = try? JSONEncoder().encode(teams) {
            try? data.write(to: teamsURL, options: [.atomic])
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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "1B"
        case .double: return "2B"
        case .triple: return "3B"
        case .homeRun: return "HR"
        case .walk: return "BB"
        case .strikeout: return "K"
        case .groundOut: return "GO"
        case .flyOut: return "FO"
        case .lineOut: return "LO"
        case .out: return "OUT"
        case .stolenBase: return "SB"
        case .rbi: return "+RBI"
        }
    }

    var isHit: Bool {
        switch self {
        case .single, .double, .triple, .homeRun: return true
        default: return false
        }
    }

    /// Whether this outcome counts as an official at-bat (AB).
    /// Walks, stolen bases, and RBI-only adjustments do not.
    var countsAsAtBat: Bool {
        switch self {
        case .walk, .stolenBase, .rbi: return false
        default: return true
        }
    }
}
