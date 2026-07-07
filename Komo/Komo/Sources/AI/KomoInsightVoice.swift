import Foundation

// MARK: - Human-friendly insight copy
//
// Keeps user-facing insight text warm and plain — no em-dashes, no medical jargon.

enum KomoInsightVoice {

    /// Plain-language factor name for prompts and fallbacks (localized via device language in AI output).
    static func humanFactorName(_ factor: KomoInsightFactor) -> String {
        switch factor {
        case .sleep:     return String(localized: "sleep")
        case .hrv:       return String(localized: "body recovery")
        case .rhr:       return String(localized: "heart at rest")
        case .activity:  return String(localized: "movement")
        case .stress:    return String(localized: "stress")
        case .meetings:  return String(localized: "your calendar")
        case .workout:   return String(localized: "today's workout")
        }
    }

    /// Light cleanup for model or legacy strings that slip through.
    static func polish(_ text: String) -> String {
        var s = text
            .replacingOccurrences(of: " — ", with: ". ")
            .replacingOccurrences(of: " – ", with: ", ")
            .replacingOccurrences(of: "—", with: ". ")
            .replacingOccurrences(of: "–", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Collapse double spaces / double periods from replacements.
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        while s.contains("..") { s = s.replacingOccurrences(of: "..", with: ".") }
        return s
    }
}
