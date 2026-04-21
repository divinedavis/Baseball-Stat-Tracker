import UIKit

/// Swaps the app icon between the primary (dark/gold outline) and the
/// alternate "BarrelNight" (gold bg, black barrel) icon based on the time
/// of day in Eastern Time. Night window is 8PM–6AM ET.
@MainActor
enum AppIconScheduler {
    private static let nightIconName = "BarrelNight"
    private static let nightStartHour = 20
    private static let nightEndHour = 6

    private static var easternTZ: TimeZone {
        TimeZone(identifier: "America/New_York") ?? .current
    }

    static func applyIfNeeded(now: Date = .now) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        let desired: String? = isNight(now: now) ? nightIconName : nil
        if app.alternateIconName == desired { return }
        app.setAlternateIconName(desired) { error in
            if let error {
                print("AppIconScheduler: failed to switch icon — \(error.localizedDescription)")
            }
        }
    }

    static func isNight(now: Date = .now) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = easternTZ
        let hour = cal.component(.hour, from: now)
        return hour >= nightStartHour || hour < nightEndHour
    }
}
