import StoreKit
import UIKit

enum ReviewPrompter {
    static let gameThreshold = 3
    private static let promptedKey = "bst.hasRequestedReview"

    /// Apple throttles `requestReview` to ~3 prompts/365 days regardless of how
    /// often we ask, so we additionally gate on a one-shot UserDefaults flag —
    /// that way a user who dismisses the sheet doesn't get re-prompted on every
    /// subsequent game.
    static func maybeRequestReview(gamesLogged: Int) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: promptedKey) else { return }
        guard gamesLogged >= gameThreshold else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        defaults.set(true, forKey: promptedKey)
        SKStoreReviewController.requestReview(in: scene)
    }
}
