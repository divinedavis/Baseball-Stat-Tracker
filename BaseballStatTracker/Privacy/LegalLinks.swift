import Foundation

/// The one place the app's legal URLs live. Every in-app privacy link must
/// use `privacyPolicy` so the app, the README and App Store Connect's
/// privacyPolicyUrl all point at the same document (PRIVACY.md on main).
enum LegalLinks {
    static let privacyPolicy = URL(string: "https://github.com/divinedavis/Baseball-Stat-Tracker/blob/main/PRIVACY.md")!
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyContactEmail = "divinejdavis@gmail.com"
}
