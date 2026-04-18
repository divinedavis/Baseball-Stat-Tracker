import Foundation

struct Player: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var number: Int
    var position: String
    var atBats: Int
    var hits: Int
    var doubles: Int
    var triples: Int
    var homeRuns: Int
    var runsBattedIn: Int
    var walks: Int
    var strikeouts: Int

    init(
        id: UUID = UUID(),
        name: String,
        number: Int,
        position: String,
        atBats: Int = 0,
        hits: Int = 0,
        doubles: Int = 0,
        triples: Int = 0,
        homeRuns: Int = 0,
        runsBattedIn: Int = 0,
        walks: Int = 0,
        strikeouts: Int = 0
    ) {
        self.id = id
        self.name = name
        self.number = number
        self.position = position
        self.atBats = atBats
        self.hits = hits
        self.doubles = doubles
        self.triples = triples
        self.homeRuns = homeRuns
        self.runsBattedIn = runsBattedIn
        self.walks = walks
        self.strikeouts = strikeouts
    }

    var singles: Int {
        max(0, hits - doubles - triples - homeRuns)
    }

    var battingAverage: Double {
        guard atBats > 0 else { return 0 }
        return Double(hits) / Double(atBats)
    }

    var onBasePercentage: Double {
        let denom = atBats + walks
        guard denom > 0 else { return 0 }
        return Double(hits + walks) / Double(denom)
    }

    var sluggingPercentage: Double {
        guard atBats > 0 else { return 0 }
        let totalBases = singles + 2 * doubles + 3 * triples + 4 * homeRuns
        return Double(totalBases) / Double(atBats)
    }

    var ops: Double {
        onBasePercentage + sluggingPercentage
    }
}
