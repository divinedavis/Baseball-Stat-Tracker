import SwiftUI

struct AddPlayerView: View {
    @EnvironmentObject private var store: PlayerStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var number: Int = 0
    @State private var age: Int = 0
    @State private var position: String = "CF"
    @State private var team: String = ""

    private let positions = ["P", "C", "1B", "2B", "3B", "SS", "LF", "CF", "RF", "DH"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    TextField("Name", text: $name)
                    numericRow(label: "Number", value: $number, range: 0...99)
                    numericRow(label: "Age", value: $age, range: 0...21)
                    Picker("Position", selection: $position) {
                        ForEach(positions, id: \.self) { Text($0) }
                    }
                }

                Section {
                    TextField("Team (optional)", text: $team)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    if !store.teams.isEmpty {
                        Menu {
                            Button("None") { team = "" }
                            Divider()
                            ForEach(store.teams, id: \.self) { t in
                                Button(t) { team = t }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "list.bullet")
                                Text("Pick from saved teams")
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("Team")
                } footer: {
                    Text("Saved teams appear here the next time you add a player.")
                        .font(.caption2)
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func numericRow(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
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
        let trimmedTeam = team.trimmingCharacters(in: .whitespacesAndNewlines)
        let player = Player(
            name: trimmedName,
            number: number,
            position: position,
            age: age > 0 ? age : nil,
            team: trimmedTeam.isEmpty ? nil : trimmedTeam
        )
        store.addPlayer(player)
        if !trimmedTeam.isEmpty {
            store.rememberTeam(trimmedTeam)
        }
        dismiss()
    }
}
