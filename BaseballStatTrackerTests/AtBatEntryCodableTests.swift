import XCTest
@testable import BaseballStatTracker

final class AtBatEntryCodableTests: XCTestCase {
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func testRoundTripPreservesEveryField() throws {
        let original = AtBatEntry(
            id: UUID(),
            playerID: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            outcome: .double,
            contact: .strong,
            hitLocation: .left,
            gameNumber: 2
        )
        let data = try encoder().encode(original)
        let decoded = try decoder().decode(AtBatEntry.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodingLegacyEntryWithoutGameNumberDefaultsToOne() throws {
        // Legacy on-disk shape pre-multi-game-tracking — gameNumber missing.
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "playerID": "\(UUID().uuidString)",
            "date": "2024-04-15T13:00:00Z",
            "outcome": "single"
        }
        """.data(using: .utf8)!
        let decoded = try decoder().decode(AtBatEntry.self, from: json)
        XCTAssertEqual(decoded.gameNumber, 1)
        XCTAssertEqual(decoded.outcome, .single)
        XCTAssertNil(decoded.contact)
        XCTAssertNil(decoded.hitLocation)
    }

    func testDecodingWithoutContactOrLocationFields() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "playerID": "\(UUID().uuidString)",
            "date": "2024-04-15T13:00:00Z",
            "outcome": "walk",
            "gameNumber": 3
        }
        """.data(using: .utf8)!
        let decoded = try decoder().decode(AtBatEntry.self, from: json)
        XCTAssertEqual(decoded.gameNumber, 3)
        XCTAssertNil(decoded.contact)
        XCTAssertNil(decoded.hitLocation)
    }
}

final class PlayerCodableTests: XCTestCase {
    func testPlayerRoundTrip() throws {
        let p = Player(name: "Jordan", number: 7, position: "CF", age: 10, team: "Thunder", level: "Travel", bats: "Right")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Player.self, from: data)
        XCTAssertEqual(decoded, p)
    }

    func testPlayerOptionalFieldsCanBeNil() throws {
        let p = Player(name: "Ari", number: 3, position: "2B")
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Player.self, from: data)
        XCTAssertNil(decoded.age)
        XCTAssertNil(decoded.team)
        XCTAssertNil(decoded.level)
        XCTAssertNil(decoded.bats)
    }
}
