#if DEBUG
import Foundation

/// Populates the app with a realistic roster + at-bat history for README
/// screenshots. Triggered only when the process is launched with `-demoSeed`.
@MainActor
enum DemoSeeder {
    static func seedIfRequested(store: PlayerStore, auth: AuthStore) {
        guard CommandLine.arguments.contains("-demoSeed") else { return }

        if !auth.isSignedIn { auth.signInDemo() }

        guard store.players.isEmpty else { return }

        let jordan = Player(name: "Jordan Davis", number: 7, position: "CF", age: 10, team: "Thunder")
        let micah  = Player(name: "Micah Lee",    number: 12, position: "SS", age: 11, team: "Thunder")
        let ari    = Player(name: "Ari Chen",     number: 3,  position: "2B", age: 9,  team: "Thunder")
        store.addPlayer(jordan)
        store.addPlayer(micah)
        store.addPlayer(ari)

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ daysAgo: Int, _ hour: Int) -> Date {
            let base = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
        }

        // Jordan — hot streak
        store.recordAtBat(for: jordan.id, outcome: .single,  contact: .strong, at: at(0, 10))
        store.recordAtBat(for: jordan.id, outcome: .double,  contact: .strong, at: at(0, 11))
        store.recordAtBat(for: jordan.id, outcome: .homeRun, contact: .strong, at: at(0, 13))
        store.recordAtBat(for: jordan.id, outcome: .walk,                      at: at(1, 10))
        store.recordAtBat(for: jordan.id, outcome: .single,                    at: at(1, 12))
        store.recordAtBat(for: jordan.id, outcome: .strikeout,                 at: at(2, 14))
        store.recordAtBat(for: jordan.id, outcome: .single,  contact: .strong, at: at(2, 15))
        store.recordAtBat(for: jordan.id, outcome: .flyOut,                    at: at(3, 11))
        store.recordAtBat(for: jordan.id, outcome: .triple,  contact: .strong, at: at(3, 13))
        store.recordAtBat(for: jordan.id, outcome: .stolenBase,                at: at(3, 13))

        // Micah — balanced
        store.recordAtBat(for: micah.id,  outcome: .single,                    at: at(0, 10))
        store.recordAtBat(for: micah.id,  outcome: .groundOut,                 at: at(0, 12))
        store.recordAtBat(for: micah.id,  outcome: .walk,                      at: at(1, 11))
        store.recordAtBat(for: micah.id,  outcome: .double,   contact: .strong, at: at(1, 14))
        store.recordAtBat(for: micah.id,  outcome: .strikeout,                 at: at(2, 10))
        store.recordAtBat(for: micah.id,  outcome: .single,                    at: at(3, 13))
        store.recordAtBat(for: micah.id,  outcome: .flyOut,                    at: at(3, 14))

        // Ari — rookie
        store.recordAtBat(for: ari.id,    outcome: .single,                    at: at(0, 11))
        store.recordAtBat(for: ari.id,    outcome: .strikeout,                 at: at(1, 10))
        store.recordAtBat(for: ari.id,    outcome: .groundOut,                 at: at(2, 12))
        store.recordAtBat(for: ari.id,    outcome: .walk,                      at: at(3, 13))
        store.recordAtBat(for: ari.id,    outcome: .single,   contact: .weak,  at: at(3, 14))
    }
}
#endif
