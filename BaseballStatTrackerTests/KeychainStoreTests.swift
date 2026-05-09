import XCTest
@testable import BaseballStatTracker

final class KeychainStoreTests: XCTestCase {
    private var account: String = ""

    override func setUp() {
        super.setUp()
        // Unique per-test account so parallel runs and prior failures
        // never leak state into each other.
        account = "test.\(UUID().uuidString)"
    }

    override func tearDown() {
        KeychainStore.delete(account: account)
        super.tearDown()
    }

    func testSetAndGetRoundTrip() throws {
        let payload = "hello-keychain".data(using: .utf8)!
        try KeychainStore.set(payload, account: account)
        let read = KeychainStore.get(account: account)
        XCTAssertEqual(read, payload)
    }

    func testSetTwiceUpdatesExistingItem() throws {
        let first = "v1".data(using: .utf8)!
        let second = "v2".data(using: .utf8)!
        try KeychainStore.set(first, account: account)
        try KeychainStore.set(second, account: account)
        XCTAssertEqual(KeychainStore.get(account: account), second)
    }

    func testGetReturnsNilForMissingAccount() {
        let missing = "missing.\(UUID().uuidString)"
        XCTAssertNil(KeychainStore.get(account: missing))
    }

    func testDeleteRemovesItem() throws {
        try KeychainStore.set(Data([0x42]), account: account)
        XCTAssertNotNil(KeychainStore.get(account: account))
        XCTAssertTrue(KeychainStore.delete(account: account))
        XCTAssertNil(KeychainStore.get(account: account))
    }

    func testDeleteOnMissingAccountIsTolerant() {
        // Deleting an account that was never set should report success
        // (errSecItemNotFound is treated as a successful no-op).
        let missing = "missing.\(UUID().uuidString)"
        XCTAssertTrue(KeychainStore.delete(account: missing))
    }
}
