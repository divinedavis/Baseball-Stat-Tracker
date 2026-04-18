import SwiftUI

struct PlayerDetailView: View {
    @EnvironmentObject private var store: PlayerStore
    @StateObject private var history = UndoHistory()

    let player: Player

    @State private var entryDate: Date = .now

    private var current: Player {
        store.players.first(where: { $0.id == player.id }) ?? player
    }

    private var stats: PlayerStats { store.stats(for: current.id) }
    private var activeDays: [Date] { store.activeDays(for: current.id) }
    private var recentEntries: [AtBatEntry] {
        Array(store.entries(for: current.id).prefix(5))
    }

    var body: some View {
        List {
            Section("Slash line") {
                StatGrid(stats: stats)
            }
            Section("Counting stats") {
                CountingStatsGrid(stats: stats)
            }
            if !recentEntries.isEmpty {
                Section("Last 5 at-bats") {
                    ForEach(recentEntries) { entry in
                        RecentAtBatRow(entry: entry)
                    }
                }
            }
            Section {
                DatePicker("Date", selection: $entryDate, displayedComponents: [.date, .hourAndMinute])
                AtBatPad(playerID: current.id, date: entryDate, history: history)
            } header: {
                Text("Record an at-bat")
            } footer: {
                Text("Each tap creates a dated entry. Use Undo to reverse.")
                    .font(.caption)
            }
            if !activeDays.isEmpty {
                Section("Game log") {
                    ForEach(activeDays, id: \.self) { day in
                        DayLogRow(
                            playerID: current.id,
                            day: day,
                            history: history
                        )
                    }
                }
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    history.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!history.canUndo)

                Button {
                    history.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!history.canRedo)

                Menu {
                    Button(role: .destructive) {
                        resetAll()
                    } label: {
                        Label("Reset all stats", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func resetAll() {
        let removed = store.entries(for: current.id)
        guard !removed.isEmpty else { return }
        for entry in removed {
            store.deleteAtBat(id: entry.id)
        }
        history.register(
            undo: { [weak store] in
                guard let store else { return }
                for entry in removed {
                    store.atBats.append(entry)
                }
            },
            redo: { [weak store] in
                guard let store else { return }
                for entry in removed {
                    store.deleteAtBat(id: entry.id)
                }
            }
        )
    }
}

// MARK: - Stat grids

struct StatGrid: View {
    let stats: PlayerStats
    var body: some View {
        HStack(spacing: 16) {
            StatCell(label: "AVG", value: StatFormatter.avg(stats.battingAverage))
            StatCell(label: "OBP", value: StatFormatter.avg(stats.onBasePercentage))
            StatCell(label: "SLG", value: StatFormatter.avg(stats.sluggingPercentage))
            StatCell(label: "OPS", value: StatFormatter.avg(stats.ops))
        }
        .padding(.vertical, 4)
    }
}

struct CountingStatsGrid: View {
    let stats: PlayerStats
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            StatCell(label: "AB", value: "\(stats.atBats)")
            StatCell(label: "H", value: "\(stats.hits)")
            StatCell(label: "2B", value: "\(stats.doubles)")
            StatCell(label: "3B", value: "\(stats.triples)")
            StatCell(label: "HR", value: "\(stats.homeRuns)")
            StatCell(label: "RBI", value: "\(stats.runsBattedIn)")
            StatCell(label: "BB", value: "\(stats.walks)")
            StatCell(label: "K", value: "\(stats.strikeouts)")
        }
        .padding(.vertical, 4)
    }
}

struct RecentAtBatRow: View {
    let entry: AtBatEntry

    var body: some View {
        HStack(spacing: 12) {
            OutcomeBadge(outcome: entry.outcome)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.subheadline.weight(.medium))
                Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct OutcomeBadge: View {
    let outcome: AtBatOutcome

    var body: some View {
        Text(outcome.label)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(tint)
            .frame(minWidth: 46, minHeight: 28)
            .padding(.horizontal, 8)
            .background(
                Capsule().fill(tint.opacity(0.18))
            )
    }

    private var tint: Color {
        switch outcome {
        case .single, .double, .triple: return .green
        case .homeRun: return .orange
        case .walk, .rbi: return .blue
        case .strikeout: return .red
        case .out: return .gray
        }
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

// MARK: - At-bat pad

struct AtBatPad: View {
    @EnvironmentObject private var store: PlayerStore
    let playerID: Player.ID
    let date: Date
    @ObservedObject var history: UndoHistory

    private let outcomes: [AtBatOutcome] = [.single, .double, .triple, .homeRun, .walk, .strikeout, .out, .rbi]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
            ForEach(outcomes) { outcome in
                Button {
                    record(outcome)
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

    private func record(_ outcome: AtBatOutcome) {
        let entry = AtBatEntry(playerID: playerID, date: date, outcome: outcome)
        store.atBats.append(entry)
        history.register(
            undo: { [weak store] in store?.deleteAtBat(id: entry.id) },
            redo: { [weak store] in store?.atBats.append(entry) }
        )
    }
}

// MARK: - Game log row

struct DayLogRow: View {
    @EnvironmentObject private var store: PlayerStore
    let playerID: Player.ID
    let day: Date
    @ObservedObject var history: UndoHistory

    private var entries: [AtBatEntry] { store.entries(for: playerID, on: day) }
    private var dayStats: PlayerStats { store.stats(for: playerID, on: day) }

    var body: some View {
        DisclosureGroup {
            ForEach(entries) { entry in
                HStack {
                    Text(entry.outcome.label)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .frame(minWidth: 44, alignment: .leading)
                    Text(entry.date, style: .time)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        remove(entry)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day, format: .dateTime.weekday(.wide).month().day())
                        .font(.subheadline.weight(.semibold))
                    Text("\(entries.count) AB • \(StatFormatter.avg(dayStats.battingAverage)) AVG")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func remove(_ entry: AtBatEntry) {
        store.deleteAtBat(id: entry.id)
        history.register(
            undo: { [weak store] in store?.atBats.append(entry) },
            redo: { [weak store] in store?.deleteAtBat(id: entry.id) }
        )
    }
}
