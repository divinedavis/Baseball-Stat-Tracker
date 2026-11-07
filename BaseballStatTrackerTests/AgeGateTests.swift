import Foundation
import Testing
@testable import BaseballStatTracker

/// Age-gate math, the under-13 device block, and the one-time upload
/// confirmation (COPPA). Swift Testing, alongside the XCTest suites.
@Suite("Age gate")
struct AgeGateTests {
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    struct Case: CustomTestStringConvertible, Sendable {
        let birthYear: Int
        let birthMonth: Int
        let today: (Int, Int, Int)
        let expectedAge: Int
        var testDescription: String {
            "born \(birthMonth)/\(birthYear) on \(today.1)/\(today.2)/\(today.0) → \(expectedAge)"
        }
    }

    @Test("Whole years from birth month + year", arguments: [
        Case(birthYear: 2013, birthMonth: 10, today: (2026, 11, 7), expectedAge: 13), // month passed
        Case(birthYear: 2013, birthMonth: 12, today: (2026, 11, 7), expectedAge: 12), // month ahead
        Case(birthYear: 2013, birthMonth: 11, today: (2026, 11, 7), expectedAge: 12), // birth month: conservative
        Case(birthYear: 2013, birthMonth: 1, today: (2026, 1, 31), expectedAge: 12),
        Case(birthYear: 2013, birthMonth: 1, today: (2026, 2, 1), expectedAge: 13),
        Case(birthYear: 1990, birthMonth: 6, today: (2026, 11, 7), expectedAge: 36),
        Case(birthYear: 2026, birthMonth: 1, today: (2026, 11, 7), expectedAge: 0),
        Case(birthYear: 2026, birthMonth: 12, today: (2026, 11, 7), expectedAge: 0), // never negative
    ])
    func age(_ c: Case) {
        let now = Self.date(c.today.0, c.today.1, c.today.2)
        #expect(AgeGate.age(birthYear: c.birthYear, birthMonth: c.birthMonth, on: now, calendar: Self.utc) == c.expectedAge)
    }

    @Test("13 is the line", arguments: [
        (2013, 10, true),
        (2013, 11, false),
        (2014, 1, false),
        (2000, 5, true),
    ])
    func isOldEnough(birthYear: Int, birthMonth: Int, expected: Bool) {
        let now = Self.date(2026, 11, 7)
        #expect(AgeGate.isOldEnough(birthYear: birthYear, birthMonth: birthMonth, on: now, calendar: Self.utc) == expected)
    }

    @Test("Year list is neutral: starts at this year, covers 100 years")
    func selectableYears() {
        let years = AgeGate.selectableYears(now: Self.date(2026, 11, 7), calendar: Self.utc)
        #expect(years.first == 2026)
        #expect(years.last == 1926)
        #expect(years.count == 101)
        #expect(years == years.sorted(by: >))
    }

    @Test("Only new, unconfirmed accounts are asked")
    func needsAgeCheck() {
        let before = AgeGate.gateLaunchDate.addingTimeInterval(-86_400)
        let after = AgeGate.gateLaunchDate.addingTimeInterval(60)
        #expect(AgeGate.needsAgeCheck(alreadyConfirmed: false, accountCreatedAt: after))
        #expect(!AgeGate.needsAgeCheck(alreadyConfirmed: true, accountCreatedAt: after))
        #expect(!AgeGate.needsAgeCheck(alreadyConfirmed: false, accountCreatedAt: before))
    }
}

@Suite("Age gate device block", .serialized)
@MainActor
struct AgeGateStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "agegate-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("Starts unblocked, block is remembered by a new instance")
    func blockPersists() {
        let account = "agegate.test.\(UUID().uuidString)"
        let defaults = freshDefaults()
        defer { KeychainStore.delete(account: account) }

        let first = AgeGateStore(defaults: defaults, keychainAccount: account)
        #expect(!first.isBlocked)
        first.recordBlocked()
        #expect(first.isBlocked)

        let second = AgeGateStore(defaults: defaults, keychainAccount: account)
        #expect(second.isBlocked)
    }

    @Test("Block survives wiped UserDefaults (reinstall) via the Keychain")
    func blockSurvivesDefaultsWipe() {
        let account = "agegate.test.\(UUID().uuidString)"
        defer { KeychainStore.delete(account: account) }

        AgeGateStore(defaults: freshDefaults(), keychainAccount: account).recordBlocked()
        let reinstalled = freshDefaults()
        let store = AgeGateStore(defaults: reinstalled, keychainAccount: account)
        #expect(store.isBlocked)
        #expect(reinstalled.bool(forKey: AgeGateStore.defaultsKey))
    }

    @Test("Sign-up is refused on a blocked device before any network call")
    func signUpRefusedWhenBlocked() {
        let shared = AgeGateStore.shared
        let wasBlocked = shared.isBlocked
        shared.recordBlocked()
        defer { if !wasBlocked { shared.resetForTesting() } }

        let auth = AuthStore()
        auth.signUp(email: "parent@example.com", password: "secret123", displayName: "Coach")
        #expect(auth.lastError == AuthStore.underAgeMessage)
        #expect(!auth.isSignedIn)
    }
}

@Suite("Upload attestation")
struct UploadAttestationTests {
    @Test("Per account, and nothing without an account id")
    func perAccount() {
        let name = "attest-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(!UploadAttestation.hasAttested(userId: "a", defaults: defaults))
        UploadAttestation.recordAttested(userId: "a", defaults: defaults)
        #expect(UploadAttestation.hasAttested(userId: "a", defaults: defaults))
        #expect(!UploadAttestation.hasAttested(userId: "b", defaults: defaults))

        UploadAttestation.recordAttested(userId: nil, defaults: defaults)
        UploadAttestation.recordAttested(userId: "", defaults: defaults)
        #expect(!UploadAttestation.hasAttested(userId: nil, defaults: defaults))
        #expect(!UploadAttestation.hasAttested(userId: "", defaults: defaults))
    }
}
