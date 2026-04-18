import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore

    enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @FocusState private var focused: Field?

    enum Field { case email, password, name }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.09, blue: 0.25),
                         Color(red: 0.10, green: 0.06, blue: 0.18),
                         Color(red: 0.55, green: 0.30, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header
                    card
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.baseball")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white)
                .padding(22)
                .background(
                    Circle().fill(.white.opacity(0.12))
                )
            Text("Baseball Stat Tracker")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(mode == .signIn ? "Welcome back." : "Create your account.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            Picker("Mode", selection: $mode) {
                Text("Sign In").tag(Mode.signIn)
                Text("Sign Up").tag(Mode.signUp)
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in auth.clearError() }

            if mode == .signUp {
                field("Display name", text: $displayName, field: .name, icon: "person")
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
            }

            field("Email", text: $email, field: .email, icon: "envelope")
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            secureField("Password", text: $password, icon: "lock")

            if let err = auth.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                Text(mode == .signIn ? "Sign In" : "Create Account")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [.blue, .indigo],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(.white)
            }
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var footer: some View {
        Button {
            withAnimation(.easeInOut) {
                mode = (mode == .signIn) ? .signUp : .signIn
                auth.clearError()
            }
        } label: {
            Text(mode == .signIn ? "Don't have an account? Sign up" : "Already have an account? Sign in")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, field: Field, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField(placeholder, text: text)
                .focused($focused, equals: field)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.85))
        )
    }

    private func secureField(_ placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            SecureField(placeholder, text: text)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .focused($focused, equals: .password)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.85))
        )
    }

    private var canSubmit: Bool {
        let emailOk = !email.trimmingCharacters(in: .whitespaces).isEmpty
        let pwOk = password.count >= 6
        let nameOk = mode == .signIn || !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        return emailOk && pwOk && nameOk
    }

    private func submit() {
        focused = nil
        switch mode {
        case .signIn:
            auth.signIn(email: email, password: password)
        case .signUp:
            auth.signUp(email: email, password: password, displayName: displayName)
        }
    }
}

#Preview {
    AuthView().environmentObject(AuthStore())
}
