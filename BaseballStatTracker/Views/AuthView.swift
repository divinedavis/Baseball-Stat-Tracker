import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showEmailSheet = false
    @State private var heroIndex = 1

    private let heroWords = ["Swing", "Track", "Win"]
    private let rotationInterval: TimeInterval = 2.6

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                heroStack
                    .padding(.top, 80)
                Spacer(minLength: 0)
                lowerCard
            }
            .frame(maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear { startRotation() }
        .sheet(isPresented: $showEmailSheet) {
            EmailAuthSheet()
                .environmentObject(auth)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var background: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.38),
                .init(color: Color(red: 0.78, green: 0.90, blue: 1.0), location: 0.52),
                .init(color: Color(red: 0.20, green: 0.52, blue: 0.96), location: 0.78),
                .init(color: Color(red: 0.10, green: 0.35, blue: 0.88), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var heroStack: some View {
        VStack(alignment: .leading, spacing: 22) {
            heroLine(for: index(-1), opacity: 0.18, fontSize: 48, bold: false)
            heroLine(for: index(0), opacity: 1.0, fontSize: 60, bold: true, icon: true)
            heroLine(for: index(1), opacity: 0.18, fontSize: 48, bold: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
        .animation(.easeInOut(duration: 0.6), value: heroIndex)
    }

    private func heroLine(for i: Int, opacity: Double, fontSize: CGFloat, bold: Bool, icon: Bool = false) -> some View {
        HStack(spacing: 12) {
            if icon {
                HeroIcon().frame(width: 44, height: 44)
            }
            Text(heroWords[i])
                .font(.system(size: fontSize, weight: bold ? .bold : .regular))
                .foregroundStyle(.black)
                .opacity(opacity)
        }
    }

    private func index(_ offset: Int) -> Int {
        let n = heroWords.count
        return ((heroIndex + offset) % n + n) % n
    }

    private func startRotation() {
        Timer.scheduledTimer(withTimeInterval: rotationInterval, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.6)) {
                    heroIndex = (heroIndex + 1) % heroWords.count
                }
            }
        }
    }

    private var lowerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppBadge()
            Text("Every at-bat,\ntracked.")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Record hits, walks, and game stats for every player. Unlimited undo, private, all yours.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            SignInWithAppleButton(
                .continue,
                onRequest: { req in
                    req.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    auth.handleAppleAuthorization(result)
                }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(Capsule())

            Button {
                auth.clearError()
                showEmailSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .font(.subheadline)
                    Text("Sign in with email")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(.white)
                .background(Capsule().fill(.white.opacity(0.22)))
                .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
            }

            if let err = auth.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 44)
    }
}

private struct HeroIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            HStack(alignment: .bottom, spacing: 3) {
                bar(height: 12); bar(height: 22); bar(height: 32)
            }
        }
    }
    private func bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(colors: [Color.orange, Color(red: 1, green: 0.42, blue: 0.2)],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(width: 6, height: height)
    }
}

private struct AppBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            Image(systemName: "baseball.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom)
                )
        }
        .frame(width: 46, height: 46)
    }
}

private struct EmailAuthSheet: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        Text("Sign In").tag(Mode.signIn)
                        Text("Sign Up").tag(Mode.signUp)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in auth.clearError() }
                }

                Section("Account") {
                    if mode == .signUp {
                        TextField("Display name", text: $displayName)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                    }
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                }

                if let err = auth.lastError {
                    Section {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button(mode == .signIn ? "Sign In" : "Create Account") { submit() }
                        .disabled(!canSubmit)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(mode == .signIn ? "Sign In" : "Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        let emailOk = !email.trimmingCharacters(in: .whitespaces).isEmpty
        let pwOk = password.count >= 6
        let nameOk = mode == .signIn || !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        return emailOk && pwOk && nameOk
    }

    private func submit() {
        switch mode {
        case .signIn:
            auth.signIn(email: email, password: password)
        case .signUp:
            auth.signUp(email: email, password: password, displayName: displayName)
        }
        if auth.isSignedIn { dismiss() }
    }
}

#Preview {
    AuthView().environmentObject(AuthStore())
}
