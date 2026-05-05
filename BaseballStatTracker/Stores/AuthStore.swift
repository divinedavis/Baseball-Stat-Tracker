import Foundation
import Combine
import AuthenticationServices
import Security
import Supabase

struct AuthUser: Codable, Equatable {
    enum Method: String, Codable { case apple, email }
    let method: Method
    let identifier: String   // Supabase user id (uuid string)
    let displayName: String
    let email: String?
}

/// Thin facade over Supabase Auth, plus a Keychain-cached snapshot of the
/// current user so the launch screen can decide which view to render
/// before the network round-trip completes.
///
/// All sign-in / sign-up / sign-out paths route through Supabase. The
/// previous local-only credential store (v3 salted hashes) is wiped on
/// first launch with this build — email accounts must re-register
/// against Supabase Auth, Apple accounts re-tap "Continue with Apple".
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var currentUser: AuthUser?
    @Published var lastError: String?
    @Published private(set) var isLoading = false

    private let sessionAccount = "session.currentUser"
    private let migrationFlagDefaultsKey = "bst.auth.migratedToSupabase"
    private let legacyV3Account = "session.credentials.v3"
    private let legacyV2Account = "session.credentials"
    private var pendingAppleNonce: String?
    private var authStateTask: Task<Void, Never>?

    var isSignedIn: Bool { currentUser != nil }
    var supabaseUserId: UUID? {
        guard let user = currentUser else { return nil }
        return UUID(uuidString: user.identifier)
    }

    init() {
        performSupabaseMigrationIfNeeded()
        if let data = KeychainStore.get(account: sessionAccount),
           let user = try? JSONDecoder().decode(AuthUser.self, from: data) {
            self.currentUser = user
        }
        observeAuthState()
        Task { await refreshFromSupabase() }
    }

    deinit {
        authStateTask?.cancel()
    }

    /// One-shot wipe of legacy local-only credential stores. Apple users keep
    /// their cached AuthUser until the next Supabase round-trip rejects it;
    /// email users get force-signed-out so they re-register against Supabase.
    private func performSupabaseMigrationIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationFlagDefaultsKey) else { return }
        KeychainStore.delete(account: legacyV2Account)
        KeychainStore.delete(account: legacyV3Account)
        if let data = KeychainStore.get(account: sessionAccount),
           let user = try? JSONDecoder().decode(AuthUser.self, from: data),
           user.method == .email {
            KeychainStore.delete(account: sessionAccount)
        }
        defaults.set(true, forKey: migrationFlagDefaultsKey)
    }

    private func observeAuthState() {
        authStateTask = Task { [weak self] in
            for await change in SupabaseService.client.auth.authStateChanges {
                guard let self else { return }
                await MainActor.run {
                    switch change.event {
                    case .signedIn, .tokenRefreshed, .userUpdated:
                        if let session = change.session {
                            self.persistFromSupabaseUser(session.user)
                        }
                    case .signedOut:
                        self.clearLocalSession()
                    default:
                        break
                    }
                }
            }
        }
    }

    private func refreshFromSupabase() async {
        do {
            let session = try await SupabaseService.client.auth.session
            persistFromSupabaseUser(session.user)
        } catch {
            // No session — clear any stale Apple cache.
            clearLocalSession()
        }
    }

    private func persistFromSupabaseUser(_ user: User) {
        let provider = user.appMetadata["provider"]?.stringValue ?? "email"
        let method: AuthUser.Method = (provider == "apple") ? .apple : .email
        let nameFromMeta = user.userMetadata["display_name"]?.stringValue
            ?? user.userMetadata["full_name"]?.stringValue
        let displayName = nameFromMeta?.isEmpty == false
            ? nameFromMeta!
            : (user.email?.components(separatedBy: "@").first ?? "Player")
        let mapped = AuthUser(
            method: method,
            identifier: user.id.uuidString,
            displayName: displayName,
            email: user.email
        )
        currentUser = mapped
        if let data = try? JSONEncoder().encode(mapped) {
            try? KeychainStore.set(data, account: sessionAccount)
        }
    }

    private func clearLocalSession() {
        currentUser = nil
        KeychainStore.delete(account: sessionAccount)
    }

    func clearError() { lastError = nil }

    #if DEBUG
    /// Injects a local-only user for `-demoSeed` screenshot runs. Skips
    /// Supabase entirely — AI features stay locked because there's no JWT.
    func signInDemo() {
        let demo = AuthUser(
            method: .email,
            identifier: UUID().uuidString,
            displayName: "Coach Davis",
            email: "coach@example.com"
        )
        currentUser = demo
        if let data = try? JSONEncoder().encode(demo) {
            try? KeychainStore.set(data, account: sessionAccount)
        }
    }
    #endif

    // MARK: - Sign in with Apple

    /// Returns the raw nonce to set on the Apple sign-in request, and caches
    /// the same value for the Supabase exchange. Supabase Auth compares the
    /// `nonce` parameter directly against the JWT's `nonce` claim with no
    /// server-side hashing, so the value we send to Apple and the value we
    /// send to Supabase must match exactly.
    func appleNonce() -> String {
        let raw = Self.randomNonce()
        pendingAppleNonce = raw
        return raw
    }

    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure:
            return
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                lastError = "Sign in with Apple failed."
                return
            }
            guard let rawNonce = pendingAppleNonce else {
                lastError = "Sign in with Apple failed (missing nonce)."
                return
            }
            let displayName: String? = [credential.fullName?.givenName,
                                        credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
                .nilIfEmpty
            isLoading = true
            Task {
                defer {
                    Task { @MainActor in
                        self.isLoading = false
                        self.pendingAppleNonce = nil
                    }
                }
                do {
                    let session = try await SupabaseService.client.auth.signInWithIdToken(
                        credentials: .init(provider: .apple, idToken: token, nonce: rawNonce)
                    )
                    if let displayName, !displayName.isEmpty {
                        try? await SupabaseService.client.auth.update(
                            user: UserAttributes(data: ["display_name": .string(displayName)])
                        )
                    }
                    await MainActor.run {
                        self.persistFromSupabaseUser(session.user)
                    }
                } catch {
                    await MainActor.run {
                        self.lastError = "Sign in with Apple failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Email + password

    func signIn(email: String, password: String) {
        let cleaned = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(cleaned) else {
            lastError = "Enter a valid email."
            return
        }
        guard password.count >= 6 else {
            lastError = "Password must be at least 6 characters."
            return
        }
        isLoading = true
        Task {
            defer { Task { @MainActor in self.isLoading = false } }
            do {
                let session = try await SupabaseService.client.auth.signIn(
                    email: cleaned, password: password
                )
                await MainActor.run { self.persistFromSupabaseUser(session.user) }
            } catch {
                await MainActor.run {
                    self.lastError = self.friendlyAuthError(error)
                }
            }
        }
    }

    func signUp(email: String, password: String, displayName: String) {
        let cleaned = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(cleaned) else {
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
        isLoading = true
        Task {
            defer { Task { @MainActor in self.isLoading = false } }
            do {
                let response = try await SupabaseService.client.auth.signUp(
                    email: cleaned,
                    password: password,
                    data: ["display_name": .string(trimmedName)]
                )
                if let session = response.session {
                    await MainActor.run { self.persistFromSupabaseUser(session.user) }
                } else {
                    // Project requires email confirmation — surface that.
                    await MainActor.run {
                        self.lastError = "Check your email to confirm the account."
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastError = self.friendlyAuthError(error)
                }
            }
        }
    }

    func signOut() {
        Task {
            try? await SupabaseService.client.auth.signOut()
            await MainActor.run { self.clearLocalSession() }
        }
    }

    /// Apple 5.1.1(v) compliance. Calls `auth.admin.deleteUser` indirectly via
    /// a server-side delete-user RPC if you add one later; for now we sign
    /// out and clear local data. The Supabase user row remains until you
    /// remove it via the dashboard or a privileged edge function.
    func deleteAccount() {
        Task {
            try? await SupabaseService.client.auth.signOut()
            await MainActor.run { self.clearLocalSession() }
        }
    }

    // MARK: - Helpers

    private func isValidEmail(_ email: String) -> Bool {
        email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    private func friendlyAuthError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("Invalid login") { return "Incorrect email or password." }
        if msg.contains("already registered") { return "An account with that email already exists." }
        return msg
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
