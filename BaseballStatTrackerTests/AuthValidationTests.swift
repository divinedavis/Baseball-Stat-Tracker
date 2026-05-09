import XCTest
@testable import BaseballStatTracker

@MainActor
final class AuthValidationTests: XCTestCase {
    func testSignInRejectsBadEmailWithoutHittingNetwork() {
        let store = AuthStore()
        store.signIn(email: "not-an-email", password: "secret123")
        XCTAssertEqual(store.lastError, "Enter a valid email.")
        XCTAssertFalse(store.isSignedIn)
    }

    func testSignInRejectsShortPassword() {
        let store = AuthStore()
        store.signIn(email: "user@example.com", password: "abc")
        XCTAssertEqual(store.lastError, "Password must be at least 6 characters.")
        XCTAssertFalse(store.isSignedIn)
    }

    func testSignUpRequiresValidEmail() {
        let store = AuthStore()
        store.signUp(email: "broken", password: "secret123", displayName: "Coach")
        XCTAssertEqual(store.lastError, "Enter a valid email.")
    }

    func testSignUpRequiresPasswordLength() {
        let store = AuthStore()
        store.signUp(email: "user@example.com", password: "12345", displayName: "Coach")
        XCTAssertEqual(store.lastError, "Password must be at least 6 characters.")
    }

    func testSignUpRequiresDisplayName() {
        let store = AuthStore()
        store.signUp(email: "user@example.com", password: "secret123", displayName: "   ")
        XCTAssertEqual(store.lastError, "Enter a display name.")
    }

    func testClearErrorResetsLastError() {
        let store = AuthStore()
        store.signIn(email: "bad", password: "secret123")
        XCTAssertNotNil(store.lastError)
        store.clearError()
        XCTAssertNil(store.lastError)
    }
}
