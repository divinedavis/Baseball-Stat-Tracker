import SwiftUI

@main
struct BaseballStatTrackerApp: App {
    @StateObject private var store = PlayerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
