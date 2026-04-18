import Foundation

struct AtBatEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let playerID: UUID
    var date: Date
    var outcome: AtBatOutcome

    init(id: UUID = UUID(), playerID: UUID, date: Date = .now, outcome: AtBatOutcome) {
        self.id = id
        self.playerID = playerID
        self.date = date
        self.outcome = outcome
    }
}
