import Foundation

enum ContactQuality: String, CaseIterable, Identifiable, Codable {
    case strong
    case weak

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strong: return "Strong"
        case .weak: return "Weak"
        }
    }
}

struct AtBatEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let playerID: UUID
    var date: Date
    var outcome: AtBatOutcome
    var contact: ContactQuality?
    /// 1–3. Which game of the day this at-bat belongs to. Defaults to 1 for
    /// entries created before multi-game tracking existed.
    var gameNumber: Int

    init(
        id: UUID = UUID(),
        playerID: UUID,
        date: Date = .now,
        outcome: AtBatOutcome,
        contact: ContactQuality? = nil,
        gameNumber: Int = 1
    ) {
        self.id = id
        self.playerID = playerID
        self.date = date
        self.outcome = outcome
        self.contact = contact
        self.gameNumber = gameNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.playerID = try c.decode(UUID.self, forKey: .playerID)
        self.date = try c.decode(Date.self, forKey: .date)
        self.outcome = try c.decode(AtBatOutcome.self, forKey: .outcome)
        self.contact = try c.decodeIfPresent(ContactQuality.self, forKey: .contact)
        self.gameNumber = try c.decodeIfPresent(Int.self, forKey: .gameNumber) ?? 1
    }
}
