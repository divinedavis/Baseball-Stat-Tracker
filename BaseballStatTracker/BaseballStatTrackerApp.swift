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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue
    @AppStorage("appLanguage") private var languageRaw: String = ""

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.systemDefault
    }

    var body: some Scene {
        WindowGroup {
            AppGateway()
                .environmentObject(store)
                .environmentObject(auth)
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.locale, language.locale)
                .onAppear {
                    AppIconScheduler.applyIfNeeded()
                    #if DEBUG
                    DemoSeeder.seedIfRequested(store: store, auth: auth)
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { AppIconScheduler.applyIfNeeded() }
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
