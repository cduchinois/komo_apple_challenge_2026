import Foundation

// MARK: - KomoEnvironmentContext
// Lightweight on-device temporal context injected into the AI prompt.
// No network calls — derived purely from the device clock and locale.

struct KomoEnvironmentContext {
    let hour: Int
    let dayOfWeek: String
    let isWeekend: Bool

    static var current: KomoEnvironmentContext {
        let now      = Date()
        let calendar = Calendar.current
        let hour     = calendar.component(.hour, from: now)
        let weekday  = calendar.component(.weekday, from: now)
        let isWeekend = weekday == 1 || weekday == 7

        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE"
        fmt.locale = Locale.current
        let dayName = fmt.string(from: now)

        return KomoEnvironmentContext(hour: hour, dayOfWeek: dayName, isWeekend: isWeekend)
    }

    var promptDescription: String {
        let moment: String
        switch hour {
        case 5..<12:  moment = "morning"
        case 12..<14: moment = "midday"
        case 14..<18: moment = "afternoon"
        case 18..<22: moment = "evening"
        default:      moment = "night"
        }
        return "\(isWeekend ? "Weekend" : "Weekday"), \(dayOfWeek), \(moment) (\(hour)h)."
    }
}
