import SwiftUI

struct PlayerDetailView: View {
    @EnvironmentObject private var store: PlayerStore
    @StateObject private var history = UndoHistory()

    let player: Player

    @State private var entryDate: Date = .now
    @AppStorage("playerDetail.showCountingStats") private var showCountingStats: Bool = false

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
            Section {
                if showCountingStats {
                    CountingStatsGrid(stats: stats)
                } else {
                    MinimizedStats(values: [
                        ("AB", "\(stats.atBats)"),
                        ("H", "\(stats.hits)"),
                        ("HR", "\(stats.homeRuns)"),
                        ("RBI", "\(stats.runsBattedIn)"),
                        ("SB", "\(stats.stolenBases)")
                    ])
                }
            } header: {
                CollapsibleHeader(title: "Counting stats", isExpanded: $showCountingStats)
            }
            Section("Record an at-bat") {
                AtBatPad(playerID: current.id, date: entryDate, history: history)
            }
            Section {
                DatePicker("Date", selection: $entryDate, displayedComponents: [.date, .hourAndMinute])
            }
            if !recentEntries.isEmpty {
                let recentStats = PlayerStats(entries: recentEntries)
                Section("Recent form") {
                    RecentFormMeter(stats: recentStats)
                }
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
            StatCell(label: "SB", value: "\(stats.stolenBases)")
            StatCell(label: "GO", value: "\(stats.groundOuts)")
            StatCell(label: "FO", value: "\(stats.flyOuts)")
            StatCell(label: "LO", value: "\(stats.lineOuts)")
        }
        .padding(.vertical, 4)
    }
}

struct CollapsibleHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Minimize" : "Expand")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .textCase(nil)
            }
            .buttonStyle(.plain)
        }
    }
}

struct MinimizedStats: View {
    let values: [(label: String, value: String)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(values, id: \.label) { pair in
                HStack(spacing: 4) {
                    Text(pair.value)
                        .font(.system(.subheadline, design: .rounded).monospacedDigit())
                        .fontWeight(.semibold)
                    Text(pair.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct RecentFormMeter: View {
    let stats: PlayerStats

    private var avg: Double { stats.battingAverage }
    private var hasAtBats: Bool { stats.atBats > 0 }
    private var isHot: Bool { hasAtBats && avg >= 0.300 }

    /// Bar scales 0 → .500 so the .300 threshold sits meaningfully in the middle.
    private let scaleMax: Double = 0.500

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hasAtBats ? StatFormatter.avg(avg) : "—")
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                    .foregroundStyle(hasAtBats ? (isHot ? Color.green : Color.orange) : .secondary)
                Text(hasAtBats ? "recent AVG" : "no at-bats")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(.tertiarySystemFill))

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHot ? Color.green : Color.orange)
                        .frame(width: proxy.size.width * min(1.0, avg / scaleMax))
                        .opacity(hasAtBats ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: avg)

                    // .300 threshold tick
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1)
                        .offset(x: proxy.size.width * (0.300 / scaleMax))
                }
            }
            .frame(height: 10)

            if hasAtBats {
                Image(systemName: isHot ? "flame.fill" : "thermometer.low")
                    .font(.subheadline)
                    .foregroundStyle(isHot ? .green : .orange)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            hasAtBats
                ? "Recent batting average \(StatFormatter.avg(avg)), \(isHot ? "above" : "below") .300"
                : "No at-bats yet"
        )
    }
}

struct ContactChip: View {
    let quality: ContactQuality

    var body: some View {
        Text(quality.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(0.15))
            )
            .overlay(
                Capsule().stroke(tint.opacity(0.4), lineWidth: 0.5)
            )
    }

    private var tint: Color {
        switch quality {
        case .strong: return .green
        case .weak: return .orange
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

    @State private var contact: ContactQuality? = nil

    private let outcomes: [AtBatOutcome] = [
        .single, .double, .triple, .homeRun,
        .walk, .strikeout, .stolenBase, .rbi,
        .groundOut, .flyOut, .lineOut, .out
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Contact")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ContactToggle(
                    title: "Strong",
                    isOn: contact == .strong,
                    tint: .green
                ) { toggle(.strong) }
                ContactToggle(
                    title: "Weak",
                    isOn: contact == .weak,
                    tint: .orange
                ) { toggle(.weak) }
            }

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
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ quality: ContactQuality) {
        contact = contact == quality ? nil : quality
    }

    private func record(_ outcome: AtBatOutcome) {
        let entry = AtBatEntry(
            playerID: playerID,
            date: date,
            outcome: outcome,
            contact: contact
        )
        store.atBats.append(entry)
        history.register(
            undo: { [weak store] in store?.deleteAtBat(id: entry.id) },
            redo: { [weak store] in store?.atBats.append(entry) }
        )
        contact = nil
    }
}

struct ContactToggle: View {
    let title: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOn ? .white : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isOn ? tint : tint.opacity(0.15))
                )
                .overlay(
                    Capsule().stroke(tint, lineWidth: isOn ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
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
                    if let contact = entry.contact {
                        ContactChip(quality: contact)
                    }
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
