import SwiftUI

struct AddPlayerView: View {
    @EnvironmentObject private var store: PlayerStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var number: Int = 0
    @State private var position: String = "CF"

    private let positions = ["P", "C", "1B", "2B", "3B", "SS", "LF", "CF", "RF", "DH"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    TextField("Name", text: $name)
                    Stepper(value: $number, in: 0...99) {
                        Text("Number: \(number)")
                    }
                    Picker("Position", selection: $position) {
                        ForEach(positions, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.addPlayer(Player(name: trimmed, number: number, position: position))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
