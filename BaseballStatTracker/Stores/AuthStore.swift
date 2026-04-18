import Foundation
import Combine
import CryptoKit

struct AuthUser: Codable, Equatable {
    let email: String
    let displayName: String
}

/// Local-only auth backed by the iOS Keychain so that:
///  - sessions survive app relaunches (users stay signed in),
///  - sessions survive app deletion + reinstall on the same device
///    (Keychain entries persist when the app's sandbox is wiped),
///  - signing out is the only way to end a session.
///
/// When we wire up a real backend (Supabase, Firebase, custom), swap the
/// `credentials` dictionary for a remote identity provider and keep the session
/// token in Keychain the same way.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var currentUser: AuthUser?
    @Published var lastError: String?

    private let sessionAccount = "session.currentUser"
    private let credentialsAccount = "session.credentials"

    var isSignedIn: Bool { currentUser != nil }

    init() {
        if let data = KeychainStore.get(account: sessionAccount),
           let user = try? JSONDecoder().decode(AuthUser.self, from: data) {
            self.currentUser = user
        }
    }

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
        guard stored.passwordHash == hash(password) else {
            lastError = "Incorrect password."
            return
        }
        persist(AuthUser(email: email, displayName: stored.displayName))
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
        creds[email] = StoredCredential(passwordHash: hash(password), displayName: trimmedName)
        saveCredentials(creds)
        persist(AuthUser(email: email, displayName: trimmedName))
    }

    func signOut() {
        currentUser = nil
        KeychainStore.delete(account: sessionAccount)
        // Intentionally keep `credentialsAccount` intact — the user's password
        // on this device should still work the next time they sign in.
    }

    func clearError() { lastError = nil }

    // MARK: - Credential storage

    private struct StoredCredential: Codable {
        let passwordHash: String
        let displayName: String
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

    private func hash(_ password: String) -> String {
        let salted = "bst.v2:" + password
        let digest = SHA256.hash(data: Data(salted.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
