import SwiftUI

struct AddPlayerView: View {
    @EnvironmentObject private var store: PlayerStore
    @EnvironmentObject private var billing: BillingStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var number: Int = 0
    @State private var age: Int = 0
    @State private var position: String = "CF"
    @State private var level: String = "Little League"
    @State private var bats: String = "Right"
    @State private var showingPaywall = false

    private let positions = ["P", "C", "1B", "2B", "3B", "SS", "LF", "CF", "RF", "DH"]
    private let levels = [
        "T-Ball", "Coach Pitch", "Machine Pitch", "Little League",
        "Travel", "Middle School", "High School",
    ]
    private let battingHands = ["Right", "Left", "Switch"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("playerNameField")
                    numericRow(label: "Number", value: $number, range: 0...99)
                    numericRow(label: "Age", value: $age, range: 0...21)
                    Picker("Position", selection: $position) {
                        ForEach(positions, id: \.self) { Text($0) }
                    }
                    Picker("Level", selection: $level) {
                        ForEach(levels, id: \.self) { Text(LocalizedStringKey($0)) }
                    }
                    Picker("Bats", selection: $bats) {
                        ForEach(battingHands, id: \.self) { Text(LocalizedStringKey($0)) }
                    }
                }

                Section {
                    Group {
                        if billing.tier == .free {
                            ProUpsell { showingPaywall = true }
                        } else {
                            ProFeaturesCard(tier: billing.tier)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelAddPlayerButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveAddPlayerButton")
                }
            }
            .sheet(isPresented: $showingPaywall) {
                AIPaywallView()
            }
        }
    }

    private func numericRow(label: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .onChange(of: value.wrappedValue) { _, newValue in
                    if newValue < range.lowerBound { value.wrappedValue = range.lowerBound }
                    if newValue > range.upperBound { value.wrappedValue = range.upperBound }
                }
            Stepper("", value: value, in: range).labelsHidden()
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let player = Player(
            name: trimmedName,
            number: number,
            position: position,
            age: age > 0 ? age : nil,
            team: nil,
            level: level,
            bats: bats
        )
        store.addPlayer(player)
        dismiss()
    }
}

/// Reusable upsell card for free-tier users. Highlights what Barrel AI
/// unlocks and pushes the paywall sheet on tap.
private struct ProUpsell: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Unlock Barrel AI")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                upsellRow(icon: "video.fill.badge.checkmark",
                          text: "Frame-by-frame swing analysis")
                upsellRow(icon: "bubble.left.and.bubble.right.fill",
                          text: "AI coach that answers any hitting question")
                upsellRow(icon: "chart.bar.doc.horizontal",
                          text: "Insights — archetype, spray chart, season totals")
            }

            Button(action: action) {
                Text("See plans")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(.tint))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.tint.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func upsellRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

/// Reminds paid users what their subscription unlocks. Tier-aware so Pro
/// users see "unlimited" Q&A and the higher swing cap, Standard users see
/// their actual numbers.
private struct ProFeaturesCard: View {
    let tier: AITier

    private var planLabel: String {
        switch tier {
        case .pro:      return "Barrel AI Pro"
        case .standard: return "Barrel AI Standard"
        case .free:     return "Free"
        }
    }

    private var swingLine: String {
        "\(tier.monthlySwings) swing analyses / month · \(tier.dailySwings) per day"
    }

    private var questionLine: String {
        tier.monthlyQuestions < 0
            ? "Unlimited AI coach questions"
            : "\(tier.monthlyQuestions) AI coach questions / month"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("You're on \(planLabel)")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "video.fill.badge.checkmark",
                           text: swingLine)
                featureRow(icon: "bubble.left.and.bubble.right.fill",
                           text: questionLine)
                featureRow(icon: "chart.bar.doc.horizontal",
                           text: "Insights — archetype, spray chart, season totals")
            }

            Text("Open the AI tab any time to chat or upload a swing. Tap Insights from any player's 3-dot menu.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.tint.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}
