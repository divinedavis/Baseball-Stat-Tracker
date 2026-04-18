import SwiftUI

struct PlayerDetailView: View {
    @EnvironmentObject private var store: PlayerStore
    let player: Player

    private var current: Player {
        store.players.first(where: { $0.id == player.id }) ?? player
    }

    var body: some View {
        List {
            Section("Slash line") {
                StatGrid(player: current)
            }
            Section("Counting stats") {
                CountingStatsGrid(player: current)
            }
            Section("Record an at-bat") {
                AtBatPad(playerID: current.id)
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatGrid: View {
    let player: Player
    var body: some View {
        HStack(spacing: 16) {
            StatCell(label: "AVG", value: StatFormatter.avg(player.battingAverage))
            StatCell(label: "OBP", value: StatFormatter.avg(player.onBasePercentage))
            StatCell(label: "SLG", value: StatFormatter.avg(player.sluggingPercentage))
            StatCell(label: "OPS", value: StatFormatter.avg(player.ops))
        }
        .padding(.vertical, 4)
    }
}

struct CountingStatsGrid: View {
    let player: Player
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            StatCell(label: "AB", value: "\(player.atBats)")
            StatCell(label: "H", value: "\(player.hits)")
            StatCell(label: "2B", value: "\(player.doubles)")
            StatCell(label: "3B", value: "\(player.triples)")
            StatCell(label: "HR", value: "\(player.homeRuns)")
            StatCell(label: "RBI", value: "\(player.runsBattedIn)")
            StatCell(label: "BB", value: "\(player.walks)")
            StatCell(label: "K", value: "\(player.strikeouts)")
        }
        .padding(.vertical, 4)
    }
}

struct StatCell: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AtBatPad: View {
    @EnvironmentObject private var store: PlayerStore
    let playerID: Player.ID

    private let outcomes: [AtBatOutcome] = [.single, .double, .triple, .homeRun, .walk, .strikeout, .out, .rbi]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
            ForEach(outcomes) { outcome in
                Button {
                    store.recordAtBat(for: playerID, outcome: outcome)
                } label: {
                    Text(outcome.label)
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.tint.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
