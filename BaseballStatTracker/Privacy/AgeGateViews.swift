import SwiftUI
import AuthenticationServices

/// Neutral birth month + year question. Nothing is pre-selected, the copy
/// never says what age is required, and the answer is only used on-device.
struct AgeGateForm: View {
    /// Called with `true` for 13+, `false` for under 13.
    let onAnswer: (Bool) -> Void
    var onCancel: (() -> Void)?
    var ink: Color = .primary

    @State private var month: Int?
    @State private var year: Int?

    private let years = AgeGate.selectableYears()
    private var monthNames: [String] { Calendar.current.monthSymbols }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ink.opacity(0.7))
                    .accessibilityIdentifier("ageGateCancelButton")
            }

            Text("When were you born?")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Enter your birth month and year to set up your account. This stays on your phone.")
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                Picker("Birth month", selection: $month) {
                    Text("Month").tag(Int?.none)
                    ForEach(Array(monthNames.enumerated()), id: \.offset) { idx, name in
                        Text(name).tag(Int?.some(idx + 1))
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityIdentifier("ageGateMonthPicker")

                Picker("Birth year", selection: $year) {
                    Text("Year").tag(Int?.none)
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(Int?.some(y))
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityIdentifier("ageGateYearPicker")
            }
            .frame(height: 180)

            Button {
                guard let month, let year else { return }
                onAnswer(AgeGate.isOldEnough(birthYear: year, birthMonth: month))
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color(red: 0.10, green: 0.10, blue: 0.12)))
            }
            .disabled(month == nil || year == nil)
            .opacity(month == nil || year == nil ? 0.4 : 1)
            .accessibilityIdentifier("ageGateContinueButton")
        }
    }
}

/// Shown instead of the sign-up options once this device has answered
/// under 13. A parent or coach who already has an account can still sign in.
struct AgeBlockedView: View {
    let onParentSignIn: () -> Void
    var appleSignIn: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "figure.and.child.holdinghands")
                .font(.system(size: 40))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            Text("Thanks for checking out Barrel!")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("ageBlockedTitle")

            Text("Ask a parent, guardian or coach to set up a Barrel account. Once they have one, they can sign in here and track your at-bats with you.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onParentSignIn) {
                Text("Parent or coach sign in")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(.white.opacity(0.22)))
                    .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
            }
            .accessibilityIdentifier("ageBlockedSignInButton")

            if let appleSignIn { appleSignIn }

            Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityIdentifier("ageBlockedPrivacyLink")
        }
    }
}

/// One-time confirmation before the first swing photo/video upload.
struct UploadAttestationSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Before you upload a swing")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("uploadAttestationTitle")

                Text("Swing photos and videos usually show a young player. Please confirm that you are either:")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Label("the player, and 13 or older, or", systemImage: "person.fill")
                    Label("the player's parent, guardian or coach, with permission to upload their swing.",
                          systemImage: "person.2.fill")
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

                Text("Each upload is sent to our AI provider for feedback and deleted from our storage as soon as the analysis finishes. Only the text feedback is kept. Please don't include a child's full name in your note.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Link("Read the Privacy Policy", destination: LegalLinks.privacyPolicy)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("uploadAttestationPrivacyLink")

                Button(action: onConfirm) {
                    Text("I confirm")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("uploadAttestationConfirm")

                Button("Not now", action: onCancel)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("uploadAttestationCancel")
            }
            .padding(24)
        }
        .presentationDetents([.large])
    }
}
