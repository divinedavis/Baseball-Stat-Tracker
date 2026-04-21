import Foundation

struct PlayerStats: Equatable {
    var atBats: Int = 0
    var hits: Int = 0
    var doubles: Int = 0
    var triples: Int = 0
    var homeRuns: Int = 0
    var runsBattedIn: Int = 0
    var walks: Int = 0
    var strikeouts: Int = 0
    var groundOuts: Int = 0
    var flyOuts: Int = 0
    var lineOuts: Int = 0
    var stolenBases: Int = 0
    var reachedOnErrors: Int = 0
    var bunts: Int = 0

    init(entries: some Sequence<AtBatEntry>) {
        for entry in entries {
            apply(entry.outcome)
        }
    }

    mutating func apply(_ outcome: AtBatOutcome) {
        switch outcome {
        case .single:
            atBats += 1; hits += 1
        case .double:
            atBats += 1; hits += 1; doubles += 1
        case .triple:
            atBats += 1; hits += 1; triples += 1
        case .homeRun:
            atBats += 1; hits += 1; homeRuns += 1; runsBattedIn += 1
        case .walk:
            walks += 1
        case .strikeout:
            atBats += 1; strikeouts += 1
        case .groundOut:
            atBats += 1; groundOuts += 1
        case .flyOut:
            atBats += 1; flyOuts += 1
        case .lineOut:
            atBats += 1; lineOuts += 1
        case .out:
            atBats += 1
        case .stolenBase:
            stolenBases += 1
        case .rbi:
            runsBattedIn += 1
        case .reachedOnError:
            atBats += 1; reachedOnErrors += 1
        case .bunt:
            bunts += 1
        }
    }

    var singles: Int { max(0, hits - doubles - triples - homeRuns) }

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

    var ops: Double { onBasePercentage + sluggingPercentage }
}
