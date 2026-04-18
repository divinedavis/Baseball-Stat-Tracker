import Foundation
import Combine

@MainActor
final class PlayerStore: ObservableObject {
    @Published var players: [Player] = []

    private let storageURL: URL
    private var saveTask: Task<Void, Never>?

    init(filename: String = "players.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.storageURL = dir.appendingPathComponent(filename)
        load()
        if players.isEmpty {
            players = Player.sampleRoster
            scheduleSave()
        }
    }

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
        players.remove(atOffsets: offsets)
        scheduleSave()
    }

    func recordAtBat(for playerID: Player.ID, outcome: AtBatOutcome) {
        guard let idx = players.firstIndex(where: { $0.id == playerID }) else { return }
        var p = players[idx]
        switch outcome {
        case .single:
            p.atBats += 1; p.hits += 1
        case .double:
            p.atBats += 1; p.hits += 1; p.doubles += 1
        case .triple:
            p.atBats += 1; p.hits += 1; p.triples += 1
        case .homeRun:
            p.atBats += 1; p.hits += 1; p.homeRuns += 1; p.runsBattedIn += 1
        case .walk:
            p.walks += 1
        case .strikeout:
            p.atBats += 1; p.strikeouts += 1
        case .out:
            p.atBats += 1
        case .rbi:
            p.runsBattedIn += 1
        }
        players[idx] = p
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let decoded = try? JSONDecoder().decode([Player].self, from: data) {
            players = decoded
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
        guard let data = try? JSONEncoder().encode(players) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}

enum AtBatOutcome: String, CaseIterable, Identifiable {
    case single, double, triple, homeRun, walk, strikeout, out, rbi
    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "1B"
        case .double: return "2B"
        case .triple: return "3B"
        case .homeRun: return "HR"
        case .walk: return "BB"
        case .strikeout: return "K"
        case .out: return "OUT"
        case .rbi: return "+RBI"
        }
    }
}

extension Player {
    static let sampleRoster: [Player] = [
        Player(name: "Sample Slugger", number: 24, position: "CF",
               atBats: 120, hits: 42, doubles: 9, triples: 1, homeRuns: 7,
               runsBattedIn: 28, walks: 18, strikeouts: 26)
    ]
}
