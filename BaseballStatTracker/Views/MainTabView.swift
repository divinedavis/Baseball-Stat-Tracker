import SwiftUI

/// Wraps `RootView` for free users (no tab bar) and adds an AI tab once
/// the user is on a paid tier. Keeps the existing UX untouched for free
/// players while giving subscribers a persistent jump-point.
struct MainTabView: View {
    @EnvironmentObject private var billing: BillingStore

    var body: some View {
        Group {
            if billing.tier == .free {
                RootView()
            } else {
                TabView {
                    RootView()
                        .tabItem {
                            Label("Players", systemImage: "list.bullet")
                        }
                    AIChatView()
                        .tabItem {
                            Label("AI", systemImage: "sparkles")
                        }
                }
            }
        }
        .task {
            await billing.refreshEntitlements()
        }
    }
}
