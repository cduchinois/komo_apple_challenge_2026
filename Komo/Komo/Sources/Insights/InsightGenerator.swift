import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - InsightGenerator

/// Generates natural language health insights from DayAnalysis.
///
/// Primary path: Apple Foundation Models (on-device LLM, iOS 26+).
/// Fallback: Rule-based insights for older devices or when LLM unavailable.
class InsightGenerator {

    static let shared = InsightGenerator()

    // MARK: - Public API

    /// Generate personalized insights from the day's analysis.
    ///
    /// - Parameter analysis: Complete day analysis from HealthAnalyzer.
    /// - Returns: Array of insight strings (3-5 items), each prefixed with an emoji.
    func generateInsights(from analysis: DayAnalysis) async -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), SystemLanguageModel.default.isAvailable {
            if let aiInsights = await generateWithFoundationModels(analysis: analysis) {
                return aiInsights
            }
        }
        #endif
        // Fallback: rule-based insights
        return generateRuleBasedInsights(from: analysis)
    }

    /// Generate a single phrase for the bubble above the blob.
    /// Primary path: Foundation Models with DynamicInstructions. Fallback: deterministic data-aware phrasing.
    func generateBubbleInsight(
        from analysis: DayAnalysis,
        mood: MoodLabel,
        environmentContext: KomoEnvironmentContext? = nil
    ) async -> String {
        let fallback = fallbackPrompt(from: analysis, mood: mood, index: 0)
        #if canImport(FoundationModels)
        if #available(iOS 27, *), let generated = await generateDynamicBubble(
            analysis: analysis,
            mood: mood,
            environmentContext: environmentContext,
            focus: nil,
            fallback: fallback
        ) {
            return generated
        }
        #endif
        return fallback
    }

    /// Generate the next data-aware prompt when the user taps Komo.
    func generateBlobTapPrompt(
        from analysis: DayAnalysis,
        mood: MoodLabel,
        index: Int,
        environmentContext: KomoEnvironmentContext? = nil
    ) async -> String {
        let fallback = fallbackPrompt(from: analysis, mood: mood, index: index)
        #if canImport(FoundationModels)
        if #available(iOS 27, *), let generated = await generateDynamicBubble(
            analysis: analysis,
            mood: mood,
            environmentContext: environmentContext,
            focus: promptFocus(from: analysis, index: index, environmentContext: environmentContext),
            fallback: fallback
        ) {
            return generated
        }
        #endif
        return fallback
    }

    // MARK: - Bubble prompts (uses real data, not hardcoded)

    private func energyPrompts(from analysis: DayAnalysis, mood: MoodLabel) -> [String] {
        var prompts: [String] = []

        if let sleep = analysis.sleepAssessment {
            let hours = sleep.data.totalSleepMinutes / 60.0
            let duration = formatSleepDuration(minutes: sleep.data.totalSleepMinutes)
            if hours < 6.5 || sleep.data.awakeCount >= 3 {
                prompts.append("Tu as dormi \(duration), avec \(sleep.data.awakeCount) réveil\(sleep.data.awakeCount > 1 ? "s" : ""). Garde ta prochaine pause vraiment calme pendant 10 minutes.\n[Start reset]")
            } else {
                prompts.append("Ta nuit de \(duration) donne une base correcte pour aujourd'hui. Garde ce rythme sans trop charger la prochaine heure.\n[Remind me later]")
            }
        }

        if let peak = analysis.peakStressHour {
            prompts.append("Ton signal le plus haut est à \(peak.hour)h, avec \(Int(peak.meanHR)) BPM. Un reset de 3 minutes peut protéger ton énergie avant le prochain bloc.\n[Start reset]")
        } else if analysis.highStressHours > 0 {
            prompts.append("Tu as \(analysis.highStressHours)h de stress élevé aujourd'hui. Une vraie coupure courte avant ton prochain bloc peut aider.\n[Start reset]")
        }

        if analysis.averageHRV > 0 {
            let hrv = Int(analysis.averageHRV.rounded())
            if hrv < 35 {
                prompts.append("Ton HRV est à \(hrv) ms. Choisir une version plus légère de ta prochaine tâche peut garder de la marge.\n[Start calm pause]")
            } else if hrv < 55 {
                prompts.append("Ton HRV est à \(hrv) ms. Garde un peu d'énergie pour la fin de journée au lieu de remplir le prochain créneau.\n[Remind me later]")
            } else {
                prompts.append("Ton HRV est à \(hrv) ms. Tu peux utiliser cette marge sans remplir toute ta journée.\n[Plan light task]")
            }
        }

        if analysis.totalSteps < 4_000 {
            prompts.append("Tu es à \(analysis.totalSteps) pas aujourd'hui. Une marche douce de 7 minutes peut relancer ton énergie sans forcer.\n[Start mini walk]")
        } else if analysis.totalSteps >= 8_000 {
            prompts.append("Tu es déjà à \(analysis.totalSteps) pas. Garde la suite légère pour ne pas transformer l'élan en fatigue.\n[Keep it light]")
        }

        if analysis.totalMeetings >= 4 {
            prompts.append("Tu as \(analysis.totalMeetings) événements aujourd'hui. Un sas de 12 minutes sans conversation peut protéger ton énergie entre deux blocs.\n[Start reset]")
        }

        if prompts.isEmpty {
            switch mood {
            case .lumineux:
                prompts.append("Ton énergie semble disponible aujourd'hui. Choisis une seule chose importante et garde le reste simple.\n[Plan light task]")
            case .serein:
                prompts.append("Tes signaux sont plutôt stables aujourd'hui. Garde une pause courte avant de repartir sur un nouveau bloc.")
            case .agité:
                prompts.append("Komo sent une journée un peu nerveuse. Fais simple maintenant : baisse le rythme pendant 5 minutes.")
            case .fatigué:
                prompts.append("Ton énergie semble plus basse aujourd'hui. Choisis la version minimale de ta prochaine tâche.")
            case .lourd:
                prompts.append("La journée paraît lourde. Protège juste le prochain quart d'heure, sans ajouter de charge.")
            }
        }

        return prompts
    }

    private func fallbackPrompt(from analysis: DayAnalysis, mood: MoodLabel, index: Int) -> String {
        let prompts = energyPrompts(from: analysis, mood: mood)
        guard !prompts.isEmpty else {
            return "Avance doucement aujourd'hui. Garde une petite pause calme pour préserver ton énergie."
        }
        return prompts[index % prompts.count]
    }

    private func promptFocus(from analysis: DayAnalysis, index: Int) -> String? {
        var focuses: [String] = []

        if analysis.sleepAssessment != nil {
            focuses.append("sommeil et récupération")
        }
        if analysis.peakStressHour != nil || analysis.highStressHours > 0 {
            focuses.append("tension ou charge mentale")
        }
        if analysis.averageHRV > 0 {
            focuses.append("HRV et marge d'énergie")
        }
        if analysis.totalSteps > 0 {
            focuses.append("mouvement du jour")
        }
        if analysis.totalMeetings > 0 {
            focuses.append("rythme de journée")
        }

        guard !focuses.isEmpty else { return nil }
        return focuses[index % focuses.count]
    }

    private func cleanBubbleText(_ text: String) -> String? {
        var cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        while cleaned.hasPrefix("-") || cleaned.hasPrefix("•") || cleaned.hasPrefix("*") {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleaned.hasPrefix("\"") || cleaned.hasPrefix("“") {
            cleaned.removeFirst()
        }
        if cleaned.hasSuffix("\"") || cleaned.hasSuffix("”") {
            cleaned.removeLast()
        }

        let lowercased = cleaned.lowercased()
        let rejectedFragments = [
            "donnée manque",
            "données manquent",
            "indisponible",
            "insuffisant",
            "incomplet",
            "apple intelligence",
            "assistant ia"
        ]

        guard !cleaned.isEmpty,
              cleaned.count <= 260,
              !rejectedFragments.contains(where: { lowercased.contains($0) }) else {
            return nil
        }

        return cleaned
    }

    private func formatSleepDuration(minutes: Double) -> String {
        let totalMinutes = Int(minutes.rounded())
        let hours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60
        if remainingMinutes == 0 {
            return "\(hours) h"
        }
        return "\(hours) h \(String(format: "%02d", remainingMinutes))"
    }


    // MARK: - Foundation Models (iOS 26+)

    #if canImport(FoundationModels)
    @available(iOS 27, *)
    private func generateDynamicBubble(
        analysis: DayAnalysis,
        mood: MoodLabel,
        focus: String?,
        fallback: String
    ) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        do {
            let instructions = KomoInsightInstructions(analysis: analysis, mood: mood)
            let session = LanguageModelSession(dynamicInstructions: instructions)
            let focusText = focus.map { " Mets l'accent sur : \($0)." } ?? ""
            let response = try await session.respond(
                to: "Écris une réponse quotidienne pour la bulle d'accueil de Komo.\(focusText)"
            )
            return cleanBubbleText(response.content)
        } catch {
            print("⚠️ DynamicInstructions bubble failed: \(error.localizedDescription)")
            return nil
        }
    }

    @available(iOS 26, *)
    private func generateWithFoundationModels(analysis: DayAnalysis) async -> [String]? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(
                instructions: systemPrompt
            )

            let userPrompt = buildDataPrompt(from: analysis)
            let response = try await session.respond(to: userPrompt)

            // Parse response into individual insights
            let insights = response.content
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            return insights.isEmpty ? nil : insights
        } catch {
            print("⚠️ Foundation Models failed: \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    // MARK: - System Prompt

    private let systemPrompt = """
    You are a caring but direct health companion avatar. Based on the user's \
    health data analysis, generate 3-5 personalized insights.

    Rules:
    - Be specific with times and numbers
    - Reference actual data values
    - Suggest ONE actionable improvement
    - Keep each insight to 1-2 sentences max
    - Use a warm, encouraging tone — like a friend who cares about your health
    - Start each insight with an emoji
    - Write each insight on a separate line
    - Do NOT use bullet points or numbering
    """

    // MARK: - Data Prompt Builder

    private func buildDataPrompt(from analysis: DayAnalysis) -> String {
        var parts: [String] = []

        // Sleep
        if let sleep = analysis.sleepAssessment {
            let hours = sleep.data.totalSleepMinutes / 60.0
            parts.append(
                "Sleep: \(String(format: "%.1f", hours)) hours, " +
                "score \(Int(sleep.score))/100 (\(sleep.category.rawValue)), " +
                "\(Int(sleep.data.deepSleepPct))% deep sleep, " +
                "\(Int(sleep.data.remSleepPct))% REM, " +
                "\(sleep.data.awakeCount) awakenings"
            )
        }

        // Stress timeline
        if !analysis.stressTimeline.isEmpty {
            let highStress = analysis.stressTimeline.filter { $0.level == .high }
            let medStress = analysis.stressTimeline.filter { $0.level == .medium }
            parts.append(
                "Stress: \(highStress.count) high-stress hours, " +
                "\(medStress.count) medium-stress hours out of " +
                "\(analysis.stressTimeline.count) hours analyzed"
            )
            if let peak = analysis.peakStressHour {
                parts.append(
                    "Peak stress at \(formatHour(peak.hour)) — " +
                    "HR was \(Int(peak.meanHR)) BPM"
                )
            }
        }

        // Anomalies
        for anomaly in analysis.anomalies {
            parts.append("Anomaly: \(anomaly.description)")
        }

        // Activity
        parts.append("Steps: \(analysis.totalSteps)")
        parts.append("Meetings: \(analysis.totalMeetings)")
        if analysis.workoutMinutes > 0 {
            parts.append("Workout: \(Int(analysis.workoutMinutes)) minutes")
        }
        if let rhr = analysis.restingHeartRate {
            parts.append("Resting HR: \(Int(rhr)) BPM")
        }

        return "Here is my health data for today:\n" + parts.joined(separator: "\n")
    }

    // MARK: - Rule-Based Fallback

    private func generateRuleBasedInsights(from analysis: DayAnalysis) -> [String] {
        var insights: [String] = []

        // Sleep insights
        if let sleep = analysis.sleepAssessment {
            let hours = sleep.data.totalSleepMinutes / 60.0
            if hours < 6 {
                insights.append(
                    "😴 You only slept \(String(format: "%.1f", hours)) hours " +
                    "last night. That's well below the recommended 7-8 hours — " +
                    "try to get to bed earlier tonight."
                )
            } else if hours < 7 {
                insights.append(
                    "😴 \(String(format: "%.1f", hours)) hours of sleep — a bit short. " +
                    "Your sleep score was \(Int(sleep.score))/100."
                )
            } else if sleep.score >= 80 {
                insights.append(
                    "✨ Great sleep last night! \(String(format: "%.1f", hours)) hours " +
                    "with a score of \(Int(sleep.score))/100. Keep it up!"
                )
            }

            if sleep.data.deepSleepPct < 10 {
                insights.append(
                    "🔵 Your deep sleep was only \(Int(sleep.data.deepSleepPct))%. " +
                    "Try limiting screen time and caffeine before bed."
                )
            }

            if sleep.data.awakeCount >= 5 {
                insights.append(
                    "🌙 You woke up \(sleep.data.awakeCount) times during the night. " +
                    "Check your room temperature and limit fluids before bed."
                )
            }
        }

        // Stress insights
        if analysis.highStressHours >= 3 {
            insights.append(
                "🔴 You had \(analysis.highStressHours) hours of high stress today. " +
                "Consider taking short breathing breaks between tasks."
            )
        } else if analysis.highStressHours >= 1 {
            if let peak = analysis.peakStressHour {
                insights.append(
                    "⚡️ Stress peak at \(formatHour(peak.hour)) — your heart rate " +
                    "hit \(Int(peak.meanHR)) BPM. " +
                    (peak.meanHR > 100
                        ? "Was that a workout or a stressful moment?"
                        : "Nothing too concerning.")
                )
            }
        } else if !analysis.stressTimeline.isEmpty {
            insights.append("💚 Low stress levels all day — your body handled today well!")
        }

        // Anomaly insights
        for anomaly in analysis.anomalies.prefix(2) {
            insights.append("⚠️ \(anomaly.description)")
        }

        // Activity insights
        if analysis.totalSteps < 3000 {
            insights.append(
                "🚶 Only \(analysis.totalSteps) steps today. Try a short walk — " +
                "even 10 minutes helps your heart and mood."
            )
        } else if analysis.totalSteps >= 10_000 {
            insights.append("🏃 \(analysis.totalSteps) steps — amazing work today! 💪")
        }

        // Meeting load insight
        if analysis.totalMeetings >= 5 {
            insights.append(
                "📅 \(analysis.totalMeetings) meetings today — that's a packed " +
                "schedule. Make sure to take breaks for your mental health."
            )
        }

        // Ensure we have at least 3 insights
        if insights.isEmpty {
            insights.append("💚 Overall a balanced day — keep up the good habits!")
        }

        return Array(insights.prefix(5))
    }

    // MARK: - Helpers

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let calendar = Calendar.current
        let date = calendar.date(
            bySettingHour: hour, minute: 0, second: 0,
            of: Date()
        )
        return date.map { formatter.string(from: $0).lowercased() } ?? "\(hour):00"
    }
}
