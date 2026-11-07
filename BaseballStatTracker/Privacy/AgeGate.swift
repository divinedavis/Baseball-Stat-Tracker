import Foundation
import Combine

/// Neutral age screen used before any new account is created (email sign-up
/// and a first-time Sign in with Apple). Barrel is not for children under 13
/// to hold their own accounts (COPPA); a parent, guardian or coach sets it up.
///
/// Rules this file encodes:
///   - We ask for birth month + year with nothing pre-selected and no hint of
///     the "right" answer. The answer never leaves the device; at most the
///     account gets `age_confirmed_13_plus = true` in its auth metadata.
///   - Only month + year are asked, so in the birth month itself we do not
///     know whether the birthday has passed. We treat it as not yet passed
///     (the conservative reading).
///   - An under-13 answer is remembered on the device (UserDefaults AND the
///     Keychain, which survives a reinstall) so going back and changing the
///     answer does not get around it.
enum AgeGate {
    static let minimumAge = 13
    /// Supabase auth user_metadata key set on accounts that passed the gate.
    static let metadataKey = "age_confirmed_13_plus"
    /// Accounts created before the gate shipped are grandfathered: they never
    /// saw the question, and asking an existing user is not account creation.
    /// Any account created on/after this instant without the flag is treated
    /// as new and must pass the gate before it is used.
    static let gateLaunchDate = Date(timeIntervalSince1970: 1_794_009_600) // 2026-11-07T00:00:00Z

    /// Whole years old on `date`, given birth month (1...12) and year.
    static func age(birthYear: Int, birthMonth: Int, on date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return 0 }
        var years = year - birthYear
        // Birthday this year has passed only once we are past the birth month.
        if month <= birthMonth { years -= 1 }
        return max(0, years)
    }

    static func isOldEnough(birthYear: Int, birthMonth: Int, on date: Date = .now, calendar: Calendar = .current) -> Bool {
        age(birthYear: birthYear, birthMonth: birthMonth, on: date, calendar: calendar) >= minimumAge
    }

    /// Years offered in the picker: this year back 100 years, newest first.
    /// Deliberately starts at the current year so no option implies an
    /// expected answer.
    static func selectableYears(now: Date = .now, calendar: Calendar = .current) -> [Int] {
        let current = calendar.component(.year, from: now)
        return Array(stride(from: current, through: current - 100, by: -1))
    }

    /// Whether a just-signed-in account still has to answer the age question.
    static func needsAgeCheck(alreadyConfirmed: Bool, accountCreatedAt: Date) -> Bool {
        if alreadyConfirmed { return false }
        return accountCreatedAt >= gateLaunchDate
    }
}

/// Remembers an under-13 answer on this device.
@MainActor
final class AgeGateStore: ObservableObject {
    static let shared = AgeGateStore()

    static let defaultsKey = "barrel.ageGate.blocked"
    static let keychainAccount = "agegate.blocked"

    @Published private(set) var isBlocked: Bool

    private let defaults: UserDefaults
    private let keychainAccount: String

    init(defaults: UserDefaults = .standard, keychainAccount: String = AgeGateStore.keychainAccount) {
        self.defaults = defaults
        self.keychainAccount = keychainAccount
        let inKeychain = KeychainStore.get(account: keychainAccount) != nil
        let inDefaults = defaults.bool(forKey: Self.defaultsKey)
        self.isBlocked = inKeychain || inDefaults
        // Re-sync both stores so a reinstall (defaults wiped, Keychain kept)
        // keeps the block in both places.
        if isBlocked { persistBlock() }
    }

    func recordBlocked() {
        isBlocked = true
        persistBlock()
    }

    private func persistBlock() {
        defaults.set(true, forKey: Self.defaultsKey)
        try? KeychainStore.set(Data([1]), account: keychainAccount)
    }

    #if DEBUG
    /// Test-only: forget a block. Never reachable in Release builds.
    func resetForTesting() {
        isBlocked = false
        defaults.removeObject(forKey: Self.defaultsKey)
        KeychainStore.delete(account: keychainAccount)
    }
    #endif
}

/// One-time confirmation before a user's first swing photo/video upload:
/// they are the player (13+) or the player's parent/guardian/coach with
/// permission to upload. Stored per account on the device and, best effort,
/// in the account's auth metadata.
enum UploadAttestation {
    static let metadataKey = "media_upload_attested"

    static func defaultsKey(for userId: String) -> String {
        "barrel.uploadAttestation.\(userId)"
    }

    static func hasAttested(userId: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return defaults.bool(forKey: defaultsKey(for: userId))
    }

    static func recordAttested(userId: String?, defaults: UserDefaults = .standard) {
        guard let userId, !userId.isEmpty else { return }
        defaults.set(true, forKey: defaultsKey(for: userId))
    }
}
