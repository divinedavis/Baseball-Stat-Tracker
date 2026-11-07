import Foundation
import Combine
import CryptoKit
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
    /// True while a brand-new Sign in with Apple account waits for the
    /// neutral age question. The session exists in Supabase but the app
    /// treats the user as signed out until the gate is answered.
    @Published private(set) var pendingAgeCheck = false

    private let sessionAccount = "session.currentUser"
    private let migrationFlagDefaultsKey = "bst.auth.migratedToSupabase"
    private let legacyV3Account = "session.credentials.v3"
    private let legacyV2Account = "session.credentials"
    private var pendingAppleNonce: String?
    /// The Supabase user behind `pendingAgeCheck`.
    private var pendingAgeUser: User?
    /// Set while a Sign in with Apple exchange is in flight so the auth
    /// listener doesn't sign the user in before the age decision.
    private var appleExchangeInFlight = false
    /// Survives an app kill mid-gate: a session for this user id is not
    /// trusted on relaunch until the age question is answered.
    static let pendingAgeUserDefaultsKey = "barrel.ageGate.pendingUserId"
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
        #if DEBUG
        // During XCUITest runs we never reach Supabase — the live auth
        // state listener and the startup session refresh would both race
        // with `signInDemo()` and clear the demo user before the UI ever
        // settles. Skip both for a deterministic test surface.
        if UITestSupport.isUITestRun { return }
        #endif
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
                            self.adoptSessionUser(session.user)
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
            adoptSessionUser(session.user)
        } catch {
            // No session — clear any stale Apple cache.
            clearLocalSession()
        }
    }

    /// Session events from the listener / startup refresh. Never lets a
    /// user past the age gate: an Apple exchange in flight decides for
    /// itself, and an account left mid-gate re-opens the question.
    private func adoptSessionUser(_ user: User) {
        if appleExchangeInFlight || pendingAgeCheck { return }
        if UserDefaults.standard.string(forKey: Self.pendingAgeUserDefaultsKey) == user.id.uuidString {
            beginAgeCheck(for: user)
            return
        }
        persistFromSupabaseUser(user)
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

    /// Apple's native Sign-In + Supabase pattern (per Supabase docs):
    ///  - Set `request.nonce` to **SHA-256(rawNonce)**, hex-encoded.
    ///  - Apple embeds that hashed value verbatim in the JWT's `nonce` claim.
    ///  - Pass the **raw** nonce to `signInWithIdToken`.
    ///  - Supabase Auth (GoTrue) hashes the raw nonce server-side and compares
    ///    against the JWT's `nonce` claim.
    func appleNonce() -> String {
        let raw = Self.randomNonce()
        pendingAppleNonce = raw
        return Self.sha256Hex(raw)
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
            appleExchangeInFlight = true
            let displayName: String? = [credential.fullName?.givenName,
                                        credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
                .nilIfEmpty
            isLoading = true
            // Diagnostic: surface what we're actually sending so a mismatch
            // is debuggable from the screen, not from logs we can't read.
            let jwtNonce = Self.decodeJWTNonce(token) ?? "?"
            let rawHash = Self.sha256Hex(rawNonce)
            let diagnostic = "jwt=\(jwtNonce.prefix(12)) raw=\(rawNonce.prefix(8)) hash(raw)=\(rawHash.prefix(12))"
            Task {
                defer {
                    Task { @MainActor in
                        self.isLoading = false
                        self.pendingAppleNonce = nil
                        self.appleExchangeInFlight = false
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
                    await self.decideAfterAppleSignIn(session.user)
                } catch {
                    await MainActor.run {
                        self.lastError = "Apple sign-in failed — \(error.localizedDescription) [\(diagnostic)]"
                    }
                }
            }
        }
    }

    // MARK: - Age gate (COPPA)

    /// Message shown when a new account is refused on a device that already
    /// answered under 13.
    static let underAgeMessage = "Ask a parent, guardian or coach to set up the account."

    private static func isAgeConfirmed(_ user: User) -> Bool {
        if case .bool(true)? = user.userMetadata[AgeGate.metadataKey] { return true }
        return false
    }

    /// After Supabase accepts the Apple token: grandfathered or already
    /// confirmed accounts go straight in; a new account either answers the
    /// age question or, on a device that already answered under 13, is
    /// deleted again before anything else is stored.
    private func decideAfterAppleSignIn(_ user: User) async {
        let needsCheck = AgeGate.needsAgeCheck(
            alreadyConfirmed: Self.isAgeConfirmed(user),
            accountCreatedAt: user.createdAt
        )
        guard needsCheck else {
            persistFromSupabaseUser(user)
            return
        }
        if AgeGateStore.shared.isBlocked {
            await discardUnconfirmedAccount()
            lastError = Self.underAgeMessage
            return
        }
        beginAgeCheck(for: user)
    }

    private func beginAgeCheck(for user: User) {
        pendingAgeUser = user
        pendingAgeCheck = true
        UserDefaults.standard.set(user.id.uuidString, forKey: Self.pendingAgeUserDefaultsKey)
    }

    private func endAgeCheck() {
        pendingAgeUser = nil
        pendingAgeCheck = false
        UserDefaults.standard.removeObject(forKey: Self.pendingAgeUserDefaultsKey)
    }

    /// Answer from the neutral age form for a pending Apple account.
    func resolvePendingAgeCheck(isOldEnough: Bool) {
        guard pendingAgeCheck else { return }
        if isOldEnough {
            let user = pendingAgeUser
            endAgeCheck()
            Task {
                try? await SupabaseService.client.auth.update(
                    user: UserAttributes(data: [AgeGate.metadataKey: .bool(true)])
                )
                let fresh = (try? await SupabaseService.client.auth.session)?.user ?? user
                if let fresh { self.persistFromSupabaseUser(fresh) }
            }
        } else {
            AgeGateStore.shared.recordBlocked()
            Task {
                await self.discardUnconfirmedAccount()
                self.endAgeCheck()
            }
        }
    }

    /// The person backed out of the age question: the account was created
    /// moments ago by this sign-in and never confirmed, so remove it.
    func cancelPendingAgeCheck() {
        guard pendingAgeCheck else { return }
        Task {
            await self.discardUnconfirmedAccount()
            self.endAgeCheck()
        }
    }

    /// Deletes the just-created, unconfirmed account server-side (same
    /// delete-user function as Delete Account) and signs out locally.
    private func discardUnconfirmedAccount() async {
        isLoading = true
        defer { isLoading = false }
        try? await callDeleteUserFunction()
        try? await SupabaseService.client.auth.signOut()
        clearLocalSession()
    }

    /// Best-effort server copy of the one-time upload confirmation.
    func recordUploadAttestation() {
        UploadAttestation.recordAttested(userId: currentUser?.identifier)
        #if DEBUG
        if UITestSupport.isUITestRun { return }
        #endif
        Task {
            try? await SupabaseService.client.auth.update(
                user: UserAttributes(data: [UploadAttestation.metadataKey: .bool(true)])
            )
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
        // The sign-up form only reaches here after the neutral age question
        // was answered 13+; a device that answered under 13 never signs up.
        guard !AgeGateStore.shared.isBlocked else {
            lastError = Self.underAgeMessage
            return
        }
        isLoading = true
        Task {
            defer { Task { @MainActor in self.isLoading = false } }
            do {
                let response = try await SupabaseService.client.auth.signUp(
                    email: cleaned,
                    password: password,
                    data: [
                        "display_name": .string(trimmedName),
                        AgeGate.metadataKey: .bool(true),
                    ]
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

    /// Apple 5.1.1(v) compliance. Calls the `delete-user` edge function which
    /// removes the user's storage objects under swing-media/<userId>/ and
    /// then `auth.admin.deleteUser` — cascading FKs clean up subscriptions,
    /// usage_counters, daily_usage, swing_analyses, chat_messages, and
    /// app_events. After the server-side delete returns we sign out and
    /// clear any local cache.
    ///
    /// If the server call fails we still sign the user out locally and
    /// surface the error so they know retry-from-our-end is needed.
    func deleteAccount() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await callDeleteUserFunction()
            } catch {
                lastError = "Couldn't fully delete your account. Please email support so we can finish removing your data."
            }
            try? await SupabaseService.client.auth.signOut()
            await MainActor.run { self.clearLocalSession() }
        }
    }

    private func callDeleteUserFunction() async throws {
        guard let session = try? await SupabaseService.client.auth.session else {
            throw URLError(.userAuthenticationRequired)
        }
        var req = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("functions/v1/delete-user"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
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

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Pulls the `nonce` claim out of an Apple-issued JWT for diagnostic
    /// display only — does not validate the signature.
    private static func decodeJWTNonce(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = payload.count % 4
        if rem > 0 { payload.append(String(repeating: "=", count: 4 - rem)) }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nonce = json["nonce"] as? String else { return nil }
        return nonce
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
