import SwiftUI

struct PlayerDetailView: View {
    @EnvironmentObject private var store: PlayerStore
    @StateObject private var history = UndoHistory()

    let player: Player

    @AppStorage("playerDetail.showCountingStats") private var showCountingStats: Bool = false
    @State private var editingEntry: AtBatEntry? = nil

    private var current: Player {
        store.players.first(where: { $0.id == player.id }) ?? player
    }

    private var games: [DayGameKey] { store.playerGames(for: current.id) }
    private var todaySessions: [GameSession] { store.sessions(for: current.id, on: .now) }
    private var activeGameNumber: Int {
        todaySessions.map { $0.gameNumber }.max() ?? 1
    }
    private var canAddAnotherGame: Bool {
        activeGameNumber < PlayerStore.maxGamesPerDay
    }
    /// Top-of-screen stats reflect the game in progress, not the player's
    /// lifetime totals — so "Add another game" naturally resets the display
    /// to zeros for the new game.
    private var stats: PlayerStats {
        store.stats(for: current.id, on: .now, gameNumber: activeGameNumber)
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section {
                StatGrid(stats: stats)
            } header: {
                HStack {
                    Text("Slash line")
                    Spacer()
                    Text("\(stats.atBats) AB")
                        .foregroundStyle(.secondary)
                }
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
            if !games.isEmpty {
                Section("Game log") {
                    ForEach(games) { key in
                        GameLogRow(
                            playerID: current.id,
                            key: key,
                            history: history,
                            editingEntry: $editingEntry
                        )
                    }
                }
                .id("gamelog")
            }
        }
        .sheet(item: $editingEntry) { entry in
            EditAtBatSheet(original: entry, history: history)
                .environmentObject(store)
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
    let title: LocalizedStringKey
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

struct ContactChip: View {
    let quality: ContactQuality

    var body: some View {
        Text(LocalizedStringKey(quality.label))
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
    @State private var hitLocation: HitLocation? = nil

    private let outcomes: [AtBatOutcome] = [
        .single, .double, .triple, .homeRun,
        .walk, .strikeout, .stolenBase, .rbi,
        .groundOut, .reachedOnError, .lineOut, .bunt
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Hit location")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ContactToggle(
                    title: "Left",
                    isOn: hitLocation == .left,
                    tint: .blue
                ) { toggleLocation(.left) }
                ContactToggle(
                    title: "Center",
                    isOn: hitLocation == .center,
                    tint: .blue
                ) { toggleLocation(.center) }
                ContactToggle(
                    title: "Right",
                    isOn: hitLocation == .right,
                    tint: .blue
                ) { toggleLocation(.right) }
            }

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

    private func toggleLocation(_ location: HitLocation) {
        hitLocation = hitLocation == location ? nil : location
    }

    private func record(_ outcome: AtBatOutcome) {
        let entry = store.recordAtBat(
            for: playerID,
            outcome: outcome,
            contact: contact,
            hitLocation: hitLocation,
            at: .now,
            gameNumber: gameNumber
        )
        history.register(
            undo: { [weak store] in store?.deleteAtBat(id: entry.id) },
            redo: { [weak store] in store?.restore(entry) }
        )
        contact = nil
        hitLocation = nil
    }
}

struct ContactToggle: View {
    let title: LocalizedStringKey
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

struct GameLogRow: View {
    @EnvironmentObject private var store: PlayerStore
    let playerID: Player.ID
    let key: DayGameKey
    @ObservedObject var history: UndoHistory
    @Binding var editingEntry: AtBatEntry?

    private var entries: [AtBatEntry] {
        store.entries(for: playerID, on: key.day, gameNumber: key.gameNumber)
    }
    private var gameStats: PlayerStats {
        store.stats(for: playerID, on: key.day, gameNumber: key.gameNumber)
    }

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
                    Button {
                        editingEntry = entry
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
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
                    Text("G\(key.gameNumber): \(key.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                        .font(.subheadline.weight(.semibold))
                    Text("\(entries.count) AB • \(StatFormatter.avg(gameStats.battingAverage)) AVG")
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

struct EditAtBatSheet: View {
    @EnvironmentObject private var store: PlayerStore
    @Environment(\.dismiss) private var dismiss
    let original: AtBatEntry
    @ObservedObject var history: UndoHistory

    @State private var outcome: AtBatOutcome
    @State private var date: Date
    @State private var contact: ContactQuality?
    @State private var hitLocation: HitLocation?

    private let outcomes: [AtBatOutcome] = [
        .single, .double, .triple, .homeRun,
        .walk, .strikeout, .stolenBase, .rbi,
        .groundOut, .reachedOnError, .lineOut, .bunt
    ]

    init(original: AtBatEntry, history: UndoHistory) {
        self.original = original
        self.history = history
        _outcome = State(initialValue: original.outcome)
        _date = State(initialValue: original.date)
        _contact = State(initialValue: original.contact)
        _hitLocation = State(initialValue: original.hitLocation)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Outcome") {
                    Picker("Outcome", selection: $outcome) {
                        ForEach(outcomes) { o in
                            Text(o.label).tag(o)
                        }
                    }
                }

                Section("When") {
                    DatePicker("Time", selection: $date)
                }

                Section("Hit location") {
                    Picker("Hit location", selection: $hitLocation) {
                        Text("None").tag(HitLocation?.none)
                        ForEach(HitLocation.allCases) { l in
                            Text(LocalizedStringKey(l.label)).tag(HitLocation?.some(l))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Contact") {
                    Picker("Contact", selection: $contact) {
                        Text("None").tag(ContactQuality?.none)
                        ForEach(ContactQuality.allCases) { q in
                            Text(LocalizedStringKey(q.label)).tag(ContactQuality?.some(q))
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Edit at-bat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        var updated = original
        updated.outcome = outcome
        updated.date = date
        updated.contact = contact
        updated.hitLocation = hitLocation
        store.updateAtBat(updated)
        let before = original
        history.register(
            undo: { [weak store] in store?.updateAtBat(before) },
            redo: { [weak store] in store?.updateAtBat(updated) }
        )
        dismiss()
    }
}
