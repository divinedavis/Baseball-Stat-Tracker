import SwiftUI

/// High-level scouting view for a single player. Premium-only — the menu
/// entry that pushes this view checks `BillingStore.tier != .free` first.
///
/// Sections, top to bottom:
///   - Player archetype (Contact / Power / Speed / Patient / etc.)
///   - Slash line + OPS
///   - Spray chart (Left / Center / Right share of recorded hit locations)
///   - Plate discipline (BB%, K%, BB/K)
///   - Power profile (ISO, XBH, HR/AB)
///   - Quality of contact (Strong / Weak share)
///   - Recent form (last 10 ABs)
///   - Best game (highest single-game OPS)
struct PlayerInsightsView: View {
    @EnvironmentObject private var store: PlayerStore
    let playerID: Player.ID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let p = player {
                    header(p)
                }
                archetypeCard
                slashLineCard
                sprayCard
                plateDisciplineCard
                powerCard
                contactQualityCard
                recentFormCard
                bestGameCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Computed inputs

    private var player: Player? {
        store.players.first(where: { $0.id == playerID })
    }
    private var entries: [AtBatEntry] { store.entries(for: playerID) }
    private var stats: PlayerStats { store.stats(for: playerID) }

    // MARK: - Sections

    private func header(_ p: Player) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.18))
                Text("\(p.number)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.title2.bold())
                Text("\(p.position) · \(p.age) yo · \(p.team ?? "—")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var archetypeCard: some View {
        let arche = archetype(for: stats, entries: entries)
        return Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: arche.icon)
                    .font(.title)
                    .foregroundStyle(arche.color)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Player type").font(.caption).foregroundStyle(.secondary)
                    Text(arche.title).font(.title3.bold())
                    Text(arche.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var slashLineCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Slash line").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    StatPill(label: "AVG", value: format(stats.battingAverage))
                    StatPill(label: "OBP", value: format(stats.onBasePercentage))
                    StatPill(label: "SLG", value: format(stats.sluggingPercentage))
                    StatPill(label: "OPS", value: format(stats.ops))
                }
                Text("\(stats.atBats) AB · \(stats.hits) H · \(stats.homeRuns) HR · \(stats.runsBattedIn) RBI · \(stats.stolenBases) SB")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var sprayCard: some View {
        let spray = sprayDistribution(entries)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Spray").font(.caption).foregroundStyle(.secondary)
                if spray.total == 0 {
                    Text("No hit locations recorded yet. Tap Left / Center / Right when logging an at-bat to build this.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    SprayBar(spray: spray)
                    HStack {
                        Text(sprayInsight(spray))
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }
            }
        }
    }

    private var plateDisciplineCard: some View {
        let pa = stats.atBats + stats.walks
        let kPct = pa > 0 ? Double(stats.strikeouts) / Double(pa) : 0
        let bbPct = pa > 0 ? Double(stats.walks) / Double(pa) : 0
        let bbk = stats.strikeouts > 0
            ? String(format: "%.2f", Double(stats.walks) / Double(stats.strikeouts))
            : (stats.walks > 0 ? "∞" : "—")
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Plate discipline").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    StatPill(label: "BB%", value: pct(bbPct))
                    StatPill(label: "K%",  value: pct(kPct))
                    StatPill(label: "BB/K", value: bbk)
                }
            }
        }
    }

    private var powerCard: some View {
        let iso = max(0, stats.sluggingPercentage - stats.battingAverage)
        let xbh = stats.doubles + stats.triples + stats.homeRuns
        let hrPerAb = stats.atBats > 0
            ? String(format: "%.1f%%", Double(stats.homeRuns) / Double(stats.atBats) * 100)
            : "—"
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Power profile").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    StatPill(label: "ISO", value: format(iso))
                    StatPill(label: "XBH", value: "\(xbh)")
                    StatPill(label: "HR/AB", value: hrPerAb)
                }
            }
        }
    }

    private var contactQualityCard: some View {
        let strong = entries.filter { $0.contact == .strong }.count
        let weak = entries.filter { $0.contact == .weak }.count
        let total = strong + weak
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quality of contact").font(.caption).foregroundStyle(.secondary)
                if total == 0 {
                    Text("Tag at-bats Strong or Weak to see how well you're squaring it up.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ContactBar(strong: strong, weak: weak)
                    Text("\(strong) strong · \(weak) weak")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recentFormCard: some View {
        let recent = Array(entries.prefix(10))  // already sorted newest-first
        let recentStats = PlayerStats(entries: recent)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last 10 ABs").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    StatPill(label: "AVG", value: format(recentStats.battingAverage))
                    StatPill(label: "OPS", value: format(recentStats.ops))
                    StatPill(label: "H", value: "\(recentStats.hits)")
                    StatPill(label: "K", value: "\(recentStats.strikeouts)")
                }
            }
        }
    }

    private var bestGameCard: some View {
        guard let best = bestGame() else {
            return AnyView(EmptyView())
        }
        return AnyView(
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Best game").font(.caption).foregroundStyle(.secondary)
                    Text(best.label).font(.headline)
                    Text("\(best.stats.hits)-for-\(best.stats.atBats) · \(format(best.stats.ops)) OPS")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        )
    }

    // MARK: - Helpers

    private func bestGame() -> (label: String, stats: PlayerStats)? {
        let games = store.playerGames(for: playerID)
        guard !games.isEmpty else { return nil }
        var best: (String, PlayerStats)? = nil
        for key in games {
            let s = store.stats(for: playerID, on: key.day, gameNumber: key.gameNumber)
            guard s.atBats > 0 else { continue }
            if best == nil || s.ops > best!.1.ops {
                let label = "G\(key.gameNumber): \(key.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
                best = (label, s)
            }
        }
        return best
    }

    private func format(_ v: Double) -> String {
        String(format: "%.3f", v).replacingOccurrences(of: "0.", with: ".")
    }

    private func pct(_ v: Double) -> String {
        String(format: "%.1f%%", v * 100)
    }
}

// MARK: - Archetype

private struct Archetype {
    let title: String
    let summary: String
    let icon: String
    let color: Color
}

private func archetype(for s: PlayerStats, entries: [AtBatEntry]) -> Archetype {
    if s.atBats < 5 {
        return Archetype(
            title: "Sample size building",
            summary: "Log a few more at-bats and Barrel will profile this player's style.",
            icon: "hourglass", color: .secondary
        )
    }
    let pa = max(1, s.atBats + s.walks)
    let bbPct = Double(s.walks) / Double(pa)
    let kPct = Double(s.strikeouts) / Double(pa)
    let iso = max(0, s.sluggingPercentage - s.battingAverage)
    let avg = s.battingAverage
    let hrRate = Double(s.homeRuns) / Double(max(1, s.atBats))
    let speed = s.stolenBases + s.triples * 2

    if hrRate > 0.10 || iso > 0.220 {
        return Archetype(
            title: "Power hitter",
            summary: "Big-time pop — hard contact and extra-base hits land more often than league average.",
            icon: "bolt.fill", color: .orange
        )
    }
    if avg > 0.320 && kPct < 0.15 {
        return Archetype(
            title: "Pure contact hitter",
            summary: "Bat-to-ball is the calling card. Rarely misses, sprays the ball around the field.",
            icon: "scope", color: .green
        )
    }
    if speed >= 4 {
        return Archetype(
            title: "Speed threat",
            summary: "Turning singles into doubles, doubles into triples — pitchers can't relax once they reach.",
            icon: "hare.fill", color: .blue
        )
    }
    if bbPct > 0.15 && kPct < 0.20 {
        return Archetype(
            title: "Patient hitter",
            summary: "Tough out. Works counts, takes walks, makes pitchers earn every strike.",
            icon: "eye.fill", color: .purple
        )
    }
    if kPct > 0.30 && bbPct < 0.05 {
        return Archetype(
            title: "Free swinger",
            summary: "Aggressive at the plate. When it connects it's loud — but the strikeouts are piling up.",
            icon: "flame.fill", color: .red
        )
    }
    return Archetype(
        title: "All-around hitter",
        summary: "Balanced profile — no glaring weakness, contributes across the slash line.",
        icon: "star.fill", color: .yellow
    )
}

// MARK: - Spray

private struct SprayCounts {
    var left = 0, center = 0, right = 0
    var total: Int { left + center + right }
    func share(_ count: Int) -> Double {
        total == 0 ? 0 : Double(count) / Double(total)
    }
}

private func sprayDistribution(_ entries: [AtBatEntry]) -> SprayCounts {
    var s = SprayCounts()
    for e in entries {
        switch e.hitLocation {
        case .left:   s.left += 1
        case .center: s.center += 1
        case .right:  s.right += 1
        case .none:   continue
        }
    }
    return s
}

private func sprayInsight(_ s: SprayCounts) -> String {
    let parts = [(s.left, "pulling left"),
                 (s.center, "going up the middle"),
                 (s.right, "going opposite field")]
    let top = parts.max { $0.0 < $1.0 }!
    let pct = Int(s.share(top.0) * 100)
    if top.0 == 0 { return "" }
    return "\(pct)% \(top.1)."
}

// MARK: - Components

private struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SprayBar: View {
    let spray: SprayCounts
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                segment(width: geo.size.width * spray.share(spray.left),
                        color: .blue, label: "L \(spray.left)")
                segment(width: geo.size.width * spray.share(spray.center),
                        color: .green, label: "C \(spray.center)")
                segment(width: geo.size.width * spray.share(spray.right),
                        color: .orange, label: "R \(spray.right)")
            }
        }
        .frame(height: 36)
    }
    private func segment(width: CGFloat, color: Color, label: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.85))
            if width > 50 {
                Text(label).font(.caption.bold()).foregroundStyle(.white)
            }
        }
        .frame(width: max(0, width - 1))
    }
}

private struct ContactBar: View {
    let strong: Int
    let weak: Int
    var body: some View {
        let total = max(1, strong + weak)
        GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.green.opacity(0.85))
                    .frame(width: geo.size.width * Double(strong) / Double(total) - 1)
                    .overlay(Text("Strong \(strong)")
                        .font(.caption.bold()).foregroundStyle(.white))
                RoundedRectangle(cornerRadius: 8)
                    .fill(.orange.opacity(0.85))
                    .frame(width: geo.size.width * Double(weak) / Double(total) - 1)
                    .overlay(Text("Weak \(weak)")
                        .font(.caption.bold()).foregroundStyle(.white))
            }
        }
        .frame(height: 36)
    }
}
