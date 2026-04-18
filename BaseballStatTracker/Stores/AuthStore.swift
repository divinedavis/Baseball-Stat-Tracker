import Foundation
import Combine

struct AuthUser: Codable, Equatable {
    let email: String
    let displayName: String
}

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var currentUser: AuthUser?
    @Published var lastError: String?

    private let defaults: UserDefaults
    private let userKey = "auth.currentUser"
    private let credentialsKey = "auth.credentials"

    var isSignedIn: Bool { currentUser != nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: userKey),
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
        defaults.removeObject(forKey: userKey)
    }

    func clearError() { lastError = nil }

    // MARK: - Internal

    private struct StoredCredential: Codable {
        let passwordHash: String
        let displayName: String
    }

    private func storedCredentials() -> [String: StoredCredential] {
        guard let data = defaults.data(forKey: credentialsKey),
              let decoded = try? JSONDecoder().decode([String: StoredCredential].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveCredentials(_ creds: [String: StoredCredential]) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        defaults.set(data, forKey: credentialsKey)
    }

    private func persist(_ user: AuthUser) {
        currentUser = user
        lastError = nil
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: userKey)
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    // Deterministic non-cryptographic obfuscation so plaintext isn't sitting in UserDefaults.
    // Not secure — swap for Keychain + a real backend before shipping to real users.
    private func hash(_ password: String) -> String {
        let salted = "bst.v1:" + password
        return Data(salted.utf8).base64EncodedString()
    }
}
