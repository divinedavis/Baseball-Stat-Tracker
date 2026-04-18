import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: PlayerStore
    @EnvironmentObject private var auth: AuthStore
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if store.players.isEmpty {
                    ContentUnavailableView(
                        "No players yet",
                        systemImage: "figure.baseball",
                        description: Text("Tap + to add your first player.")
                    )
                } else {
                    List {
                        ForEach(store.players) { player in
                            NavigationLink(value: player.id) {
                                PlayerCard(player: player)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(player)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    delete(player)
                                } label: {
                                    Label("Delete player", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Player")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if let user = auth.currentUser {
                            Section {
                                Text(user.displayName)
                                if let email = user.email {
                                    Text(email).font(.caption)
                                }
                            }
                        }
                        Button(role: .destructive) {
                            auth.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
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

    private func delete(_ player: Player) {
        guard let idx = store.players.firstIndex(where: { $0.id == player.id }) else { return }
        store.delete(at: IndexSet(integer: idx))
    }
}

#Preview {
    RootView()
        .environmentObject(PlayerStore())
        .environmentObject(AuthStore())
}
