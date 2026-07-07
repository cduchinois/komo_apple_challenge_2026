import Foundation

// MARK: - MoodLabel
// Computed from DayAnalysis — used by KomoPromptBuilder to
// contextualise the AI system prompt with the user's current energy state.

enum MoodLabel: String {
    case lumineux = "lumineux"
    case serein   = "serein"
    case fatigué  = "fatigué"
    case agité    = "agité"
    case lourd    = "lourd"

    static func from(_ analysis: DayAnalysis) -> MoodLabel {
        let hrv        = analysis.averageHRV
        let highStress = analysis.highStressHours
        let sleepH     = analysis.sleepAssessment.map { $0.data.totalSleepMinutes / 60.0 } ?? 7.5

        if sleepH < 6   && highStress >= 2                               { return .lourd   }
        if sleepH < 6.5 || (hrv > 0 && hrv < 30)                        { return .fatigué }
        if highStress >= 3                                                { return .agité   }
        if sleepH >= 7.5 && (hrv == 0 || hrv >= 50) && highStress == 0  { return .lumineux }
        return .serein
    }

    var firstPersonContext: String {
        switch self {
        case .lumineux: return "I feel energised and focused today. I can handle demanding work."
        case .serein:   return "I feel balanced overall. A few small signals to keep an eye on."
        case .fatigué:  return "I'm tired. My recovery is limited. I need gentleness today."
        case .agité:    return "I sense tension in my body. My nervous system is under load."
        case .lourd:    return "I'm exhausted and under pressure. Every effort feels doubled today."
        }
    }

    static var deviceLanguageInstruction: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "fr": return "Reply in French (français)."
        case "es": return "Reply in Spanish (español)."
        case "de": return "Reply in German (Deutsch)."
        case "it": return "Reply in Italian (italiano)."
        case "pt": return "Reply in Portuguese (português)."
        case "ja": return "Reply in Japanese (日本語)."
        case "zh": return "Reply in Simplified Chinese (简体中文)."
        case "ru": return "Reply in Russian (русский)."
        case "pl": return "Reply in Polish (polski)."
        case "tr": return "Reply in Turkish (Türkçe)."
        case "sv": return "Reply in Swedish (svenska)."
        case "da": return "Reply in Danish (dansk)."
        case "nb", "no": return "Reply in Norwegian (norsk)."
        case "th": return "Reply in Thai (ภาษาไทย)."
        case "vi": return "Reply in Vietnamese (tiếng Việt)."
        case "hi": return "Reply in Hindi (हिन्दी)."
        default:   return "Reply in English."
        }
    }
}
