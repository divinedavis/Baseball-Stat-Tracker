import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct BaseballStatTrackerApp: App {
    @StateObject private var store = PlayerStore()
    @StateObject private var auth = AuthStore()
    @AppStorage("appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            AppGateway()
                .environmentObject(store)
                .environmentObject(auth)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear {
                    #if DEBUG
                    DemoSeeder.seedIfRequested(store: store, auth: auth)
                    #endif
                }
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
