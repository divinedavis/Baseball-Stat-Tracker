import Foundation
import Combine
import CryptoKit
import AuthenticationServices
import Security

struct AuthUser: Codable, Equatable {
    enum Method: String, Codable { case apple, email }
    let method: Method
    let identifier: String   // Apple sub id, or lowercased email
    let displayName: String
    let email: String?
}

/// Local-only auth backed by the iOS Keychain so that:
///  - sessions survive app relaunches,
///  - sessions survive app deletion + reinstall on the same device,
///  - signing out is the only way to end a session.
///
/// Two entry methods:
///  - Sign in with Apple — delegates identity to Apple; we store userIdentifier + name/email.
///  - Email + password — local credentials. Each credential carries a per-user
///    16-byte random salt; the password is hashed as `SHA-256("bst.v3:" + salt + ":" + password)`.
///    Legacy v2 (static-salt) credentials are dropped on first launch with this build,
///    so any pre-existing email accounts must re-register or switch to Sign in with Apple.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var currentUser: AuthUser?
    @Published var lastError: String?

    private let sessionAccount = "session.currentUser"
    private let credentialsAccount = "session.credentials.v3"
    private let legacyCredentialsAccount = "session.credentials"
    private let migrationFlagDefaultsKey = "bst.auth.migratedToV3"

    var isSignedIn: Bool { currentUser != nil }

    init() {
        performV3MigrationIfNeeded()
        if let data = KeychainStore.get(account: sessionAccount),
           let user = try? JSONDecoder().decode(AuthUser.self, from: data) {
            self.currentUser = user
            Task { await self.validateAppleCredentialIfNeeded() }
        }
    }

    /// One-shot migration: nuke the legacy static-salt credentials store and
    /// force-sign-out any active email session so the user has to re-register
    /// against the new salted format. Apple sessions stay intact.
    private func performV3MigrationIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationFlagDefaultsKey) else { return }
        KeychainStore.delete(account: legacyCredentialsAccount)
        if let data = KeychainStore.get(account: sessionAccount),
           let user = try? JSONDecoder().decode(AuthUser.self, from: data),
           user.method == .email {
            KeychainStore.delete(account: sessionAccount)
        }
        defaults.set(true, forKey: migrationFlagDefaultsKey)
    }

    // MARK: - Sign in with Apple

    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure:
            // Silently ignore every failure path from the Apple sheet — cancel,
            // dismiss, simulator-has-no-Apple-ID (error 1000 .unknown), and
            // transient network blips. If the sign-in didn't succeed, the user
            // is still on this screen and can retry. A red error line for a
            // user-initiated cancel is worse UX than staying quiet.
            return
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                lastError = "Unexpected credential type."
                return
            }
            let userID = credential.user
            let email = credential.email
            let fullName = credential.fullName
            let composedName: String? = [fullName?.givenName, fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
                .nilIfEmpty

            // Apple only returns name/email the first time. If we've seen this user before,
            // fall back to the previously-stored display name.
            let previous = storedAppleProfile(for: userID)
            let displayName = composedName
                ?? previous?.displayName
                ?? (email?.components(separatedBy: "@").first ?? "Player")

            let user = AuthUser(
                method: .apple,
                identifier: userID,
                displayName: displayName,
                email: email ?? previous?.email
            )
            saveAppleProfile(user)
            persist(user)
        }
    }

    func validateAppleCredentialIfNeeded() async {
        guard let user = currentUser, user.method == .apple else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: user.identifier)
            switch state {
            case .authorized:
                return
            case .revoked, .notFound:
                signOut()
            case .transferred:
                return
            @unknown default:
                return
            }
        } catch {
            // Network / ephemeral errors — keep the session, try again next launch.
        }
    }

    // MARK: - Email + password

    func signIn(email: String, password: String) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(email) else {
            lastError = "Enter a valid email."
            return
        }
        guard password.count >= 6 else {
            lastError = "Password must be at least 6 characters."
            return
        }
        guard let stored = storedCredentials()[email] else {
            lastError = "No account found for that email."
            return
        }
        guard stored.passwordHash == hash(password, salt: stored.salt) else {
            lastError = "Incorrect password."
            return
        }
        persist(AuthUser(
            method: .email,
            identifier: email,
            displayName: stored.displayName,
            email: email
        ))
    }

    func signUp(email: String, password: String, displayName: String) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(email) else {
            lastError = "Enter a valid email."
            return
        }
        guard password.count >= 6 else {
            lastError = "Password must be at least 6 characters."
            return
        }
        guard !trimmedName.isEmpty else {
            lastError = "Enter a display name."
            return
        }
        var creds = storedCredentials()
        if creds[email] != nil {
            lastError = "An account with that email already exists."
            return
        }
        let salt = Self.generateSalt()
        creds[email] = StoredCredential(
            passwordHash: hash(password, salt: salt),
            displayName: trimmedName,
            salt: salt
        )
        saveCredentials(creds)
        persist(AuthUser(
            method: .email,
            identifier: email,
            displayName: trimmedName,
            email: email
        ))
    }

    func signOut() {
        currentUser = nil
        KeychainStore.delete(account: sessionAccount)
    }

    /// Permanently deletes the signed-in account's credentials from the
    /// Keychain, then signs out. Apple 5.1.1(v) requires an in-app account
    /// deletion path for any app that supports account creation.
    ///
    /// Caller should also wipe the user's on-device content (roster, at-bats)
    /// via `PlayerStore.deleteAllData()` — this method only owns the
    /// account/credential side of the delete.
    func deleteAccount() {
        guard let user = currentUser else { return }
        switch user.method {
        case .email:
            var creds = storedCredentials()
            creds.removeValue(forKey: user.identifier)
            if creds.isEmpty {
                KeychainStore.delete(account: credentialsAccount)
            } else {
                saveCredentials(creds)
            }
        case .apple:
            var profiles = appleProfiles()
            profiles.removeValue(forKey: user.identifier)
            if profiles.isEmpty {
                KeychainStore.delete(account: "session.apple")
            } else if let data = try? JSONEncoder().encode(profiles) {
                try? KeychainStore.set(data, account: "session.apple")
            }
        }
        signOut()
    }

    #if DEBUG
    /// Bypasses the auth sheet so `-demoSeed` can produce README screenshots.
    func signInDemo() {
        persist(AuthUser(
            method: .email,
            identifier: "coach@example.com",
            displayName: "Coach Davis",
            email: "coach@example.com"
        ))
    }
    #endif

    func clearError() { lastError = nil }

    // MARK: - Credential storage

    private struct StoredCredential: Codable {
        let passwordHash: String
        let displayName: String
        let salt: String
    }

    private struct AppleProfile: Codable {
        let userID: String
        let displayName: String
        let email: String?
    }

    private func storedCredentials() -> [String: StoredCredential] {
        guard let data = KeychainStore.get(account: credentialsAccount),
              let decoded = try? JSONDecoder().decode([String: StoredCredential].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveCredentials(_ creds: [String: StoredCredential]) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        try? KeychainStore.set(data, account: credentialsAccount)
    }

    private func appleProfiles() -> [String: AppleProfile] {
        guard let data = KeychainStore.get(account: "session.apple"),
              let decoded = try? JSONDecoder().decode([String: AppleProfile].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func storedAppleProfile(for userID: String) -> AppleProfile? {
        appleProfiles()[userID]
    }

    private func saveAppleProfile(_ user: AuthUser) {
        var profiles = appleProfiles()
        profiles[user.identifier] = AppleProfile(
            userID: user.identifier,
            displayName: user.displayName,
            email: user.email
        )
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? KeychainStore.set(data, account: "session.apple")
    }

    private func persist(_ user: AuthUser) {
        currentUser = user
        lastError = nil
        if let data = try? JSONEncoder().encode(user) {
            try? KeychainStore.set(data, account: sessionAccount)
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private func hash(_ password: String, salt: String) -> String {
        let salted = "bst.v3:" + salt + ":" + password
        let digest = SHA256.hash(data: Data(salted.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 16 bytes from `SecRandomCopyBytes`, hex-encoded. Falls back to a UUID-derived
    /// value only if the system RNG fails — which on iOS in practice never happens.
    private static func generateSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
