import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: PlayerStore
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if store.players.isEmpty {
                    ContentUnavailableView(
                        "No players yet",
                        systemImage: "figure.baseball",
                        description: Text("Tap + to add your first player.")
                    )
                } else {
                    ForEach(store.players) { player in
                        NavigationLink(value: player.id) {
                            PlayerRow(player: player)
                        }
                    }
                    .onDelete(perform: store.delete)
                }
            }
            .navigationTitle("Roster")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Player.ID.self) { id in
                if let player = store.players.first(where: { $0.id == id }) {
                    PlayerDetailView(player: player)
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddPlayerView()
            }
        }
    }
}

#Preview {
    RootView().environmentObject(PlayerStore())
}
