import SwiftUI

struct PlayerDetailView: View {
    @EnvironmentObject private var store: PlayerStore
    @StateObject private var history = UndoHistory()

    let player: Player

    @AppStorage("playerDetail.showCountingStats") private var showCountingStats: Bool = false

    private var current: Player {
        store.players.first(where: { $0.id == player.id }) ?? player
    }

    private var stats: PlayerStats { store.stats(for: current.id) }
    private var activeDays: [Date] { store.activeDays(for: current.id) }
    private var todaySessions: [GameSession] { store.sessions(for: current.id, on: .now) }
    private var activeGameNumber: Int {
        todaySessions.map { $0.gameNumber }.max() ?? 1
    }
    private var canAddAnotherGame: Bool {
        activeGameNumber < PlayerStore.maxGamesPerDay
    }
    private var recentEntries: [AtBatEntry] {
        Array(
            store.entries(for: current.id)
                .lazy
                .filter { $0.outcome.countsAsAtBat }
                .prefix(5)
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section("Slash line") {
                StatGrid(stats: stats)
            }
            .id("slash")
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
                AtBatPad(
                    playerID: current.id,
                    gameNumber: activeGameNumber,
                    history: history
                )
            }
            Section {
                ForEach(todaySessions) { session in
                    GameTimeRow(session: session)
                }
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
                .id("gamelog")
            }
        }
        #if DEBUG
        .task {
            if CommandLine.arguments.contains("-demoExpandStats") {
                showCountingStats = true
            }
            if CommandLine.arguments.contains("-demoScrollGameLog") {
                try? await Task.sleep(nanoseconds: 250_000_000)
                withAnimation(.none) {
                    proxy.scrollTo("gamelog", anchor: .top)
                }
            }
            if CommandLine.arguments.contains("-demoPreview") {
                await runPreviewSequence()
            }
        }
        #endif
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
                    Button {
                        addAnotherGame()
                    } label: {
                        Label("Add another game", systemImage: "plus.circle")
                    }
                    .disabled(!canAddAnotherGame)

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
        .onAppear {
            store.ensureG1Session(for: current.id, on: .now)
        }
    }

    private func addAnotherGame() {
        guard let started = store.startNextGame(for: current.id, on: .now) else { return }
        history.register(
            undo: { [weak store] in
                store?.gameSessions.removeAll { $0.id == started.id }
            },
            redo: { [weak store] in
                guard let store, !store.gameSessions.contains(where: { $0.id == started.id }) else { return }
                store.gameSessions.append(started)
            }
        )
    }

    private func resetAll() {
        let removedEntries = store.entries(for: current.id)
        let removedSessions = store.gameSessions.filter { $0.playerID == current.id }
        guard !(removedEntries.isEmpty && removedSessions.isEmpty) else { return }
        for entry in removedEntries {
            store.deleteAtBat(id: entry.id)
        }
        store.gameSessions.removeAll { $0.playerID == current.id }
        let pid = current.id
        history.register(
            undo: { [weak store] in
                guard let store else { return }
                store.restore(removedEntries)
                store.gameSessions.append(contentsOf: removedSessions)
            },
            redo: { [weak store] in
                guard let store else { return }
                for entry in removedEntries {
                    store.deleteAtBat(id: entry.id)
                }
                store.gameSessions.removeAll { $0.playerID == pid }
            }
        )
    }

    #if DEBUG
    /// Drives the scripted App Preview recording. Plays a 1B → 2B → HR reveal,
    /// pauses on the climbed slash line, then unwinds via undo so the whole
    /// demo ends back at the empty state it started from.
    @MainActor
    private func runPreviewSequence() async {
        let id = current.id
        let s = store
        let sleep = { (sec: Double) in
            try? await Task.sleep(nanoseconds: UInt64(sec * 1_000_000_000))
        }

        await sleep(2.4)                                       // land on empty slash
        let a = s.recordAtBat(for: id, outcome: .single,  contact: .strong)
        await sleep(2.1)
        let b = s.recordAtBat(for: id, outcome: .double,  contact: .strong)
        await sleep(2.1)
        let c = s.recordAtBat(for: id, outcome: .homeRun, contact: .strong)
        await sleep(4.0)                                       // savor the climb
        s.deleteAtBat(id: c.id); await sleep(1.9)
        s.deleteAtBat(id: b.id); await sleep(1.9)
        s.deleteAtBat(id: a.id); await sleep(2.0)
    }
    #endif
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
    let gameNumber: Int
    @ObservedObject var history: UndoHistory

    @State private var contact: ContactQuality? = nil

    private let outcomes: [AtBatOutcome] = [
        .single, .double, .triple, .homeRun,
        .walk, .strikeout, .stolenBase, .rbi,
        .groundOut, .reachedOnError, .lineOut, .bunt
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
        let entry = store.recordAtBat(
            for: playerID,
            outcome: outcome,
            contact: contact,
            at: .now,
            gameNumber: gameNumber
        )
        history.register(
            undo: { [weak store] in store?.deleteAtBat(id: entry.id) },
            redo: { [weak store] in store?.restore(entry) }
        )
        contact = nil
    }
}

struct GameTimeRow: View {
    @EnvironmentObject private var store: PlayerStore
    let session: GameSession

    var body: some View {
        DatePicker(
            "G\(session.gameNumber) Time",
            selection: Binding(
                get: { session.startTime },
                set: { store.updateGameSessionStart(id: session.id, to: $0) }
            ),
            displayedComponents: [.hourAndMinute]
        )
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
            undo: { [weak store] in store?.restore(entry) },
            redo: { [weak store] in store?.deleteAtBat(id: entry.id) }
        )
    }
}
