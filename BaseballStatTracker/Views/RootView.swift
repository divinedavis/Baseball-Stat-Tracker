import SwiftUI
import LocalAuthentication

struct RootView: View {
    @EnvironmentObject private var store: PlayerStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var billing: BillingStore
    @State private var showingAdd = false
    @State private var path = NavigationPath()
    @State private var showingDeleteConfirm = false
    @State private var showingPaywall = false
    @AppStorage("appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.players.isEmpty {
                    ContentUnavailableView {
                        Text("No players yet").font(.headline)
                    } description: {
                        Text("Tap + to add your first player.")
                    }
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
            .navigationTitle("Players")
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
                        Picker(selection: $appearanceRaw) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(LocalizedStringKey(mode.label)).tag(mode.rawValue)
                            }
                        } label: {
                            Label("Appearance", systemImage: "moon")
                        }
                        Button {
                            showingPaywall = true
                        } label: {
                            Label(billing.tier == .free ? "Use AI" : "Manage AI",
                                  systemImage: "sparkles")
                        }
                        Button(role: .destructive) {
                            auth.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Account", systemImage: "trash")
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
            .sheet(isPresented: $showingPaywall) {
                AIPaywallView()
            }
            .alert("Delete account?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteAccount() }
            } message: {
                Text("This permanently deletes your account and every roster, at-bat, and game log stored on this device. This cannot be undone.")
            }
            .onChange(of: store.totalGamesLogged) { _, newValue in
                ReviewPrompter.maybeRequestReview(gamesLogged: newValue)
            }
            .task {
                ReviewPrompter.maybeRequestReview(gamesLogged: store.totalGamesLogged)
            }
            #if DEBUG
            .task {
                if CommandLine.arguments.contains("-demoOpenDetail"),
                   let first = store.players.first,
                   path.isEmpty {
                    path.append(first.id)
                }
            }
            #endif
        }
    }

    private func delete(_ player: Player) {
        guard let idx = store.players.firstIndex(where: { $0.id == player.id }) else { return }
        store.delete(at: IndexSet(integer: idx))
    }

    private func deleteAccount() {
        Task {
            let context = LAContext()
            var policyError: NSError?
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) {
                do {
                    try await context.evaluatePolicy(
                        .deviceOwnerAuthentication,
                        localizedReason: "Confirm account deletion"
                    )
                } catch {
                    return
                }
            }
            await MainActor.run {
                store.deleteAllData()
                auth.deleteAccount()
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(PlayerStore())
        .environmentObject(AuthStore())
}
