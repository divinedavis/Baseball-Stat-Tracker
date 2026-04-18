import SwiftUI

struct PlayerRow: View {
    @EnvironmentObject private var store: PlayerStore
    let player: Player

    private var subtitle: String {
        var parts: [String] = [player.position]
        if let age = player.age, age > 0 { parts.append("\(age) yo") }
        if let team = player.team, !team.isEmpty { parts.append(team) }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        let stats = store.stats(for: player.id)
        HStack(spacing: 12) {
            NumberBadge(number: player.number)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(StatFormatter.avg(stats.battingAverage))
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .fontWeight(.semibold)
                Text("AVG")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PlayerCard: View {
    let player: Player

    var body: some View {
        PlayerRow(player: player)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NumberBadge: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.system(.headline, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(
                LinearGradient(
                    colors: [.blue, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}

enum StatFormatter {
    static func avg(_ value: Double) -> String {
        String(format: "%.3f", value).replacingOccurrences(of: "0.", with: ".")
    }
}
