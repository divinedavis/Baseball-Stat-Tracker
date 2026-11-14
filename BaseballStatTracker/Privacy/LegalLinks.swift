import Foundation

/// The one place the app's legal URLs live. Every in-app privacy link must
/// use `privacyPolicy` so the app, the README and App Store Connect's
/// privacyPolicyUrl all point at the same page. That page is PRIVACY.md,
/// published by scripts/publish_privacy_page.py (owner, 2026-11-13: off
/// GitHub, so the repository can be private).
enum LegalLinks {
    static let privacyPolicy = URL(string: "https://divinedavis.com/barrel/privacy/")!
    static let support = URL(string: "https://divinedavis.com/barrel/support/")!
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyContactEmail = "divinejdavis@gmail.com"
}
