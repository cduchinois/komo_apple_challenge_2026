import Foundation

// MARK: - Insight factor keys (aligned with EnergyScoreEngine drivers)

enum KomoInsightFactor: String, CaseIterable, Equatable {
    case sleep
    case hrv
    case rhr
    case activity
    case stress
    case meetings
    case workout

    static func from(driverLabel: String) -> KomoInsightFactor {
        switch driverLabel {
        case "Sleep":      return .sleep
        case "HRV":        return .hrv
        case "Resting HR": return .rhr
        case "Movement":   return .activity
        case "Stress":     return .stress
        case "Calendar":   return .meetings
        case "Workout":    return .workout
        default:           return .sleep
        }
    }
}

/// Structured insight produced from real HealthKit analysis + optional Foundation Models.
struct KomoGeneratedInsight: Equatable {
    let observation: String
    let suggestion: String
    let mainFactor: KomoInsightFactor
    let energyScore: Int
    let energyWord: String

    func asReflection() -> Reflection {
        Reflection(
            type: .reflect,
            observation: observation,
            suggestion: suggestion,
            actions: [.startNow, .save, .next]
        )
    }
}

/// Serializable day context injected into the Foundation Models user prompt.
/// All numbers come from Swift — the model must not invent values.
struct KomoInsightContext: Equatable {
    let energyScore: Int
    let energyWord: String
    let recovery: Double
    let load: Double
    let mainFactor: KomoInsightFactor
    let mainFactorLabel: String
    let mainFactorDetail: String
    let mainFactorImpactPoints: Int
    let mainFactorKind: EnergyDriver.Kind
    let mood: MoodLabel
    let driversSummary: String
    let serializedDataBlock: String

    static func build(from analysis: DayAnalysis) -> KomoInsightContext? {
        let engine = EnergyScoreEngine.shared
        let result = engine.compute(from: analysis)
        guard result.isAvailable else { return nil }

        let drivers = engine.analyzeDrivers(from: result, analysis: analysis)
        let top = drivers.max(by: { abs($0.deltaE) < abs($1.deltaE) })
            ?? drivers.first

        let factor = KomoInsightFactor.from(driverLabel: top?.label ?? "Sleep")
        let percent = Int(result.score.rounded())
        let word = EnergyLevel.from(percent: percent).word
        let mood = MoodLabel.from(analysis)

        let driversSummary = drivers
            .sorted { abs($0.deltaE) > abs($1.deltaE) }
            .prefix(5)
            .map { driver in
                let plainLabel = humanDriverLabel(driver.label)
                let sign = driver.deltaE >= 0 ? "+" : ""
                return "\(plainLabel): \(driver.detail) (\(sign)\(Int(driver.deltaE.rounded())) pts)"
            }
            .joined(separator: "\n")

        let humanFactor = KomoInsightVoice.humanFactorName(factor)

        var data = """
        ENERGY: \(percent)% (\(word))
        MAIN REASON TODAY (pre-computed, do not change): \(humanFactor)
        DETAIL: \(top?.detail ?? "none")
        MOOD: \(mood.rawValue)
        """

        if let sleep = analysis.sleepAssessment {
            let h = sleep.data.totalSleepMinutes / 60.0
            data += """

            SLEEP: \(String(format: "%.1f", h)) hours, quality \(Int(sleep.score))/100
            """
        }

        data += """

        WALKING: \(analysis.totalSteps) steps, \(analysis.totalCalories) active calories
        """

        if analysis.workoutMinutes > 0 {
            data += "Workout: \(Int(analysis.workoutMinutes)) min\n"
        }
        if let rhr = analysis.restingHeartRate {
            data += "Heart at rest: \(Int(rhr)) beats per minute\n"
        }
        if analysis.averageHRV > 0 {
            data += "Body recovery signal: \(String(format: "%.0f", analysis.averageHRV)) (internal score, do not quote units to user)\n"
        }
        data += "Stressful hours: \(analysis.highStressHours)\n"
        data += "Meetings: \(analysis.totalMeetings)\n"

        if !driversSummary.isEmpty {
            data += "\nWHAT SHAPED TODAY:\n\(driversSummary)\n"
        }

        return KomoInsightContext(
            energyScore: percent,
            energyWord: word,
            recovery: result.R,
            load: result.L,
            mainFactor: factor,
            mainFactorLabel: top?.label ?? "Sleep",
            mainFactorDetail: top?.detail ?? "—",
            mainFactorImpactPoints: Int((top?.deltaE ?? 0).rounded()),
            mainFactorKind: top?.kind ?? .recovery,
            mood: mood,
            driversSummary: driversSummary,
            serializedDataBlock: data
        )
    }

    private static func humanDriverLabel(_ label: String) -> String {
        switch label {
        case "Sleep":      return "Sleep"
        case "HRV":        return "Body recovery"
        case "Resting HR": return "Heart at rest"
        case "Movement":   return "Walking"
        case "Stress":     return "Stress"
        case "Calendar":   return "Meetings"
        case "Workout":    return "Workout"
        default:           return label
        }
    }

    /// Rule-based fallback when Foundation Models is unavailable.
    func ruleBasedInsight() -> KomoGeneratedInsight {
        let observation: String
        let suggestion: String

        switch mainFactor {
        case .sleep:
            observation = HealthKitL10n.aiFallbackObservationSleep(
                detail: mainFactorDetail, energyWord: energyWord.lowercased()
            )
            suggestion = mainFactorImpactPoints < 0
                ? HealthKitL10n.aiFallbackSuggestionSleepRecover
                : HealthKitL10n.aiFallbackSuggestionSleepUse
        case .hrv:
            observation = HealthKitL10n.aiFallbackObservationHRV(detail: mainFactorDetail)
            suggestion = mainFactorImpactPoints < 0
                ? HealthKitL10n.aiFallbackSuggestionHRVRest
                : HealthKitL10n.aiFallbackSuggestionHRVFocus
        case .rhr:
            observation = HealthKitL10n.aiFallbackObservationRHR(detail: mainFactorDetail)
            suggestion = HealthKitL10n.aiFallbackSuggestionRHR
        case .activity:
            observation = HealthKitL10n.aiFallbackObservationActivity(detail: mainFactorDetail)
            suggestion = energyScore >= 60
                ? HealthKitL10n.aiFallbackSuggestionActivityHigh
                : HealthKitL10n.aiFallbackSuggestionActivityLow
        case .stress:
            observation = HealthKitL10n.aiFallbackObservationStress(detail: mainFactorDetail)
            suggestion = HealthKitL10n.aiFallbackSuggestionStress
        case .meetings:
            observation = HealthKitL10n.aiFallbackObservationMeetings(detail: mainFactorDetail)
            suggestion = HealthKitL10n.aiFallbackSuggestionMeetings
        case .workout:
            observation = HealthKitL10n.aiFallbackObservationWorkout(detail: mainFactorDetail)
            suggestion = HealthKitL10n.aiFallbackSuggestionWorkout
        }

        return KomoGeneratedInsight(
            observation: KomoInsightVoice.polish(observation),
            suggestion: KomoInsightVoice.polish(suggestion),
            mainFactor: mainFactor,
            energyScore: energyScore,
            energyWord: energyWord
        )
    }
}
