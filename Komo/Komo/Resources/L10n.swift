//  L10n.swift
//  Komo
//
//  Localization helpers. User-facing copy lives in Localizable.xcstrings.
//  Onboarding answers are stored as stable English keys; display labels are localized here.

import Foundation

enum L10n {
    /// Localizes an onboarding option or other string whose catalog key equals the stored value.
    static func option(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    static func energyLevel(_ level: EnergyLevel) -> String {
        switch level {
        case .charged: return String(localized: "Charged")
        case .steady:  return String(localized: "Steady")
        case .fragile: return String(localized: "Fragile")
        case .low:     return String(localized: "Low")
        case .drained: return String(localized: "Drained")
        }
    }

    static func reflectionAction(_ action: ReflectionAction) -> String {
        switch action {
        case .addToCalendar: return String(localized: "Add to calendar")
        case .save:          return String(localized: "Save")
        case .writeNote:     return String(localized: "Write a note")
        case .remindMe:      return String(localized: "Remind me")
        case .startNow:      return String(localized: "Start now")
        case .done:          return String(localized: "Done")
        case .next:          return String(localized: "Next")
        }
    }

    static func permissionState(_ state: PermissionState) -> String {
        switch state {
        case .granted:       return String(localized: "Connected")
        case .denied:        return String(localized: "Not connected")
        case .notDetermined: return String(localized: "Not connected")
        }
    }

    static func calendarPermissionOpening(for drainKey: String) -> String {
        switch drainKey {
        case "meetings":     return String(localized: "meetings drain you.")
        case "intense work": return String(localized: "heavy workload drains you.")
        case "social plans": return String(localized: "social plans drain you.")
        default:             return String(localized: "your calendar drains you.")
        }
    }

    static func energyHeadline(word: String) -> String {
        String(format: String(localized: "%@ energy"), word.lowercased())
    }
}

enum OnboardingOptions {
    static let energyPeaks = ["morning", "afternoon", "evening", "changes a lot"]
    static let energyNow = ["strong", "okay", "low", "running on fumes"]
    static let sleep = ["slept great", "okay", "badly", "barely slept"]
    static let restores = ["walking", "music", "quiet time", "workout",
                           "nap / sleep", "outside", "talking", "not sure yet"]
    static let drains = ["poor sleep", "screen time", "meetings", "sitting too long",
                         "intense work", "social plans", "commute / travel", "not sure yet"]
}
