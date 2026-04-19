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
                .environment(\.colorScheme, .light)
                .presentationCornerRadius(28)
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
                    auth.clearError()
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
                    Text("Continue with email")
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
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @FocusState private var focused: Field?

    enum Field { case name, email, password, confirm }

    private let canvas = Color.white
    private let ink = Color(red: 0.10, green: 0.10, blue: 0.12)

    private var passwordsMatch: Bool {
        mode == .signIn || (password == confirmPassword && !confirmPassword.isEmpty)
    }

    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ink.opacity(0.65))
                        }
                        Spacer()
                    }
                    .padding(.bottom, 24)

                    Text(mode == .signIn ? "Welcome back." : "Let's get started.")
                        .font(.subheadline)
                        .foregroundStyle(ink.opacity(0.55))
                        .padding(.bottom, 8)

                    Text(mode == .signIn ? "Sign in to\nyour stats." : "Create your\nplayer locker.")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(ink)
                        .lineSpacing(-4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)

                    Text("Track every at-bat for every player.\nPrivate, offline, unlimited undo.")
                        .font(.subheadline)
                        .foregroundStyle(ink.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 28)

                    VStack(spacing: 4) {
                        if mode == .signUp {
                            UnderlinedField(
                                "Display name",
                                text: $displayName,
                                ink: ink,
                                field: .name,
                                focused: $focused
                            )
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                        }
                        UnderlinedField(
                            "Email",
                            text: $email,
                            ink: ink,
                            field: .email,
                            focused: $focused
                        )
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        UnderlinedSecureField(
                            "Password",
                            text: $password,
                            ink: ink,
                            field: .password,
                            focused: $focused
                        )
                        .textContentType(mode == .signIn ? .password : .newPassword)

                        if mode == .signUp {
                            UnderlinedSecureField(
                                "Confirm password",
                                text: $confirmPassword,
                                ink: ink,
                                field: .confirm,
                                focused: $focused
                            )
                            .textContentType(.newPassword)
                        }
                    }
                    .padding(.bottom, 20)

                    if mode == .signUp, !confirmPassword.isEmpty, password != confirmPassword {
                        Label("Passwords don't match.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .padding(.bottom, 12)
                    } else if let err = auth.lastError {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .padding(.bottom, 12)
                    }

                    Button {
                        submit()
                    } label: {
                        Text(mode == .signIn ? "Sign In" : "Create Account")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(ink))
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.4)
                    .padding(.top, 8)

                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                mode = mode == .signIn ? .signUp : .signIn
                                confirmPassword = ""
                                auth.clearError()
                            }
                        } label: {
                            Text(mode == .signIn
                                 ? "Don't have an account? Sign up"
                                 : "Already have an account? Sign in")
                                .font(.footnote)
                                .foregroundStyle(ink.opacity(0.6))
                                .underline()
                        }
                        Spacer()
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var canSubmit: Bool {
        let emailOk = !email.trimmingCharacters(in: .whitespaces).isEmpty
        let pwOk = password.count >= 6
        let nameOk = mode == .signIn || !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        return emailOk && pwOk && nameOk && passwordsMatch
    }

    private func submit() {
        focused = nil
        switch mode {
        case .signIn:
            auth.signIn(email: email, password: password)
        case .signUp:
            auth.signUp(email: email, password: password, displayName: displayName)
        }
        if auth.isSignedIn { dismiss() }
    }
}

private struct UnderlinedField: View {
    let placeholder: String
    @Binding var text: String
    let ink: Color
    let field: EmailAuthSheet.Field
    @FocusState.Binding var focused: EmailAuthSheet.Field?

    init(
        _ placeholder: String,
        text: Binding<String>,
        ink: Color,
        field: EmailAuthSheet.Field,
        focused: FocusState<EmailAuthSheet.Field?>.Binding
    ) {
        self.placeholder = placeholder
        self._text = text
        self.ink = ink
        self.field = field
        self._focused = focused
    }

    var body: some View {
        VStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .focused($focused, equals: field)
                .font(.body)
                .foregroundStyle(ink)
                .padding(.vertical, 14)
            Rectangle()
                .fill(focused == field ? ink.opacity(0.6) : ink.opacity(0.2))
                .frame(height: 1)
                .animation(.easeInOut(duration: 0.15), value: focused)
        }
    }
}

private struct UnderlinedSecureField: View {
    let placeholder: String
    @Binding var text: String
    let ink: Color
    let field: EmailAuthSheet.Field
    @FocusState.Binding var focused: EmailAuthSheet.Field?

    init(
        _ placeholder: String,
        text: Binding<String>,
        ink: Color,
        field: EmailAuthSheet.Field,
        focused: FocusState<EmailAuthSheet.Field?>.Binding
    ) {
        self.placeholder = placeholder
        self._text = text
        self.ink = ink
        self.field = field
        self._focused = focused
    }

    var body: some View {
        VStack(spacing: 6) {
            SecureField(placeholder, text: $text)
                .focused($focused, equals: field)
                .font(.body)
                .foregroundStyle(ink)
                .padding(.vertical, 14)
            Rectangle()
                .fill(focused == field ? ink.opacity(0.6) : ink.opacity(0.2))
                .frame(height: 1)
                .animation(.easeInOut(duration: 0.15), value: focused)
        }
    }
}

#Preview {
    AuthView().environmentObject(AuthStore())
}
