import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, es

    var id: String { rawValue }

    /// Picks Spanish iff the device's first preferred language starts with
    /// "es" — so a user whose iPhone is set to Dominican Spanish lands in
    /// Spanish on first launch without having to tap the toggle.
    static var systemDefault: AppLanguage {
        let code = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        return code.hasPrefix("es") ? .es : .en
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var displayCode: String { rawValue.uppercased() }

    func toggled() -> AppLanguage { self == .en ? .es : .en }
}
