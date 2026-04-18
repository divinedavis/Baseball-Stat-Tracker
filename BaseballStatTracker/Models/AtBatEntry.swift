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

    init(
        id: UUID = UUID(),
        playerID: UUID,
        date: Date = .now,
        outcome: AtBatOutcome,
        contact: ContactQuality? = nil
    ) {
        self.id = id
        self.playerID = playerID
        self.date = date
        self.outcome = outcome
        self.contact = contact
    }
}
