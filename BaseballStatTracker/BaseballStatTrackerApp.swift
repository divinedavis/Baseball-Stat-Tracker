import SwiftUI

@main
struct BaseballStatTrackerApp: App {
    @StateObject private var store = PlayerStore()
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            AppGateway()
                .environmentObject(store)
                .environmentObject(auth)
        }
    }
}

struct AppGateway: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        Group {
            if auth.isSignedIn {
                RootView()
                    .transition(.opacity)
            } else {
                AuthView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isSignedIn)
    }
}
