#if DEBUG
import Foundation
import UIKit

/// Hooks for XCUITest runs to start the app from a known clean state.
///
/// Three flags are honored:
///   - `-uiTestReset`     : delete every persisted JSON file under
///     Documents/, clear the UserDefaults keys the app reads, then sign in
///     via `AuthStore.signInDemo()` so the test bypasses the auth wall.
///   - `-uiTestSignedIn`  : sign in via demo without touching disk, for tests
///     that want pre-existing roster state to survive between launches.
///   - `-uiTestSignedOut` : reset like `-uiTestReset` but also clear the
///     Keychain session so the app launches into the auth screen.
enum UITestSupport {
    static var isUITestRun: Bool {
        let args = CommandLine.arguments
        return args.contains("-uiTestReset")
            || args.contains("-uiTestSignedIn")
            || args.contains("-uiTestSignedOut")
    }

    /// Invoked from `BaseballStatTrackerApp.init()` before any @StateObject
    /// initializer fires. Wipes persisted state so a fresh PlayerStore loads
    /// nothing on launch.
    static func resetIfRequested() {
        let args = CommandLine.arguments
        let signedOut = args.contains("-uiTestSignedOut")
        let reset = args.contains("-uiTestReset")
        if isUITestRun {
            // Kill UIView animations across the whole process so toolbar
            // taps and sheet presentations are deterministic — animation
            // mid-transition is what makes XCUITest taps occasionally
            // disappear into the void.
            UIView.setAnimationsEnabled(false)
        }
        guard reset || signedOut else { return }
        wipeDocuments()
        wipeUserDefaults()
        if signedOut { wipeAuthSession() }
    }

    private static func wipeAuthSession() {
        KeychainStore.delete(account: "session.currentUser")
    }

    private static func wipeDocuments() {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix("bst-") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func wipeUserDefaults() {
        let keys = [
            "appearance",
            "appLanguage",
            "playerDetail.showCountingStats",
            "bst.hasRequestedReview",
        ]
        let defaults = UserDefaults.standard
        for k in keys { defaults.removeObject(forKey: k) }
        // Mark the Supabase migration as already-run so AuthStore.init does
        // not delete the cached demo session it relies on.
        defaults.set(true, forKey: "bst.auth.migratedToSupabase")
    }
}
#endif
