import AppIntents
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AskKomoQuestionIntent: AppIntent {
    static var title: LocalizedStringResource = "Demander à Komo"
    static var description = IntentDescription(
        "Répond à une question libre sur l'énergie, le sommeil, le stress ou l'activité du jour"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Question")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Demander à Komo \(\.$question)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let healthKit = HealthKitManager.shared
        let analyzer = HealthAnalyzer.shared
        guard let summary = try? await healthKit.fetchDailySummary(for: Date()) else {
            return .result(dialog: "Désolé, je n'ai pas pu récupérer tes données santé aujourd'hui.")
        }

        let analysis = analyzer.analyzeDay(summary: summary)
        let answer = await answerQuestion(question, analysis: analysis)
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }

    private func answerQuestion(_ question: String, analysis: DayAnalysis) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), SystemLanguageModel.default.isAvailable {
            do {
                let session = LanguageModelSession(instructions: buildPrompt(from: analysis))
                let response = try await session.respond(to: question)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            } catch {
                print("AskKomoQuestionIntent Foundation Models failed: \(error.localizedDescription)")
            }
        }
        #endif

        return fallbackAnswer(for: question, analysis: analysis)
    }

    private func buildPrompt(from analysis: DayAnalysis) -> String {
        let energy = EnergyScoreEngine.score(from: analysis)
        var parts: [String] = [
            "ENERGIE: \(energy.energyScore)/100, humeur \(energy.moodLabel.rawValue)",
            "ACTIVITE: \(analysis.totalSteps) pas, \(analysis.totalCalories) calories actives, \(Int(analysis.workoutMinutes.rounded())) minutes d'entrainement",
            "STRESS: niveau moyen \(analysis.averageStressLevel.rawValue), \(analysis.highStressHours) heure(s) de stress eleve",
            "AGENDA: \(analysis.totalMeetings) reunion(s)",
            "SCREEN TIME: \(analysis.screenTimeMinutes) minutes"
        ]

        if let sleep = analysis.sleepAssessment {
            let hours = sleep.data.totalSleepMinutes / 60.0
            parts.append("SOMMEIL: score \(Int(sleep.score.rounded()))/100, \(String(format: "%.1f", hours)) heures, \(Int((sleep.data.deepSleepPct * 100).rounded()))% sommeil profond, \(Int((sleep.data.remSleepPct * 100).rounded()))% REM, \(sleep.data.awakeCount) reveil(s)")
        } else {
            parts.append("SOMMEIL: donnees non disponibles")
        }

        if let peak = analysis.peakStressHour {
            parts.append("PIC STRESS: \(peak.hour)h, frequence cardiaque moyenne \(Int(peak.meanHR.rounded())) BPM")
        }

        if let restingHeartRate = analysis.restingHeartRate {
            parts.append("FC REPOS: \(Int(restingHeartRate.rounded())) BPM")
        }

        let hrv = analysis.averageHRV
        if hrv > 0 {
            parts.append("HRV: \(Int(hrv.rounded())) ms SDNN")
        }

        if !analysis.anomalies.isEmpty {
            parts.append("ANOMALIES: \(analysis.anomalies.map(\.description).joined(separator: "; "))")
        }

        return """
        Tu es Komo, un assistant vocal de sante personnel.
        Reponds uniquement avec les donnees ci-dessous. N'invente jamais de metrique absente.
        Si la question concerne l'energie, le sommeil, le stress, l'activite, les pas, la recuperation, le coeur ou les conseils de bien-etre, reponds directement.
        Si la question est hors sujet, recentre en une phrase vers les donnees sante.
        Reponds en francais, naturellement, en 1 a 3 phrases maximum, avec les chiffres utiles.

        Donnees du jour:
        \(parts.joined(separator: "\n"))
        """
    }

    private func fallbackAnswer(for question: String, analysis: DayAnalysis) -> String {
        let lower = question.lowercased()

        if lower.contains("sommeil") || lower.contains("sleep") || lower.contains("dormi") || lower.contains("nuit") {
            guard let sleep = analysis.sleepAssessment else {
                return "Je n'ai pas trouvé de données de sommeil pour aujourd'hui sur Komo."
            }

            let hours = sleep.data.totalSleepMinutes / 60.0
            return "Ton sommeil est à \(Int(sleep.score.rounded())) sur 100. Tu as dormi \(String(format: "%.1f", hours)) heures, avec \(Int((sleep.data.deepSleepPct * 100).rounded())) pour cent de sommeil profond et \(sleep.data.awakeCount) réveil(s)."
        }

        if lower.contains("stress") || lower.contains("tendu") || lower.contains("pression") || lower.contains("anxieux") {
            let level = localizedStressLevel(analysis.averageStressLevel)
            if let peak = analysis.peakStressHour {
                return "Ton stress moyen est \(level), avec \(analysis.highStressHours) heure(s) de stress élevé. Le pic semble être vers \(peak.hour) heures, à \(Int(peak.meanHR.rounded())) battements par minute."
            }

            return "Ton stress moyen est \(level), avec \(analysis.highStressHours) heure(s) de stress élevé. Je ne vois pas de pic majeur aujourd'hui."
        }

        if lower.contains("activité") || lower.contains("activite") || lower.contains("pas") || lower.contains("sport") || lower.contains("calorie") || lower.contains("marche") {
            return "Aujourd'hui, tu as fait \(analysis.totalSteps) pas, brûlé environ \(analysis.totalCalories) calories actives et enregistré \(Int(analysis.workoutMinutes.rounded())) minutes d'entraînement."
        }

        if lower.contains("énergie") || lower.contains("energie") || lower.contains("forme") || lower.contains("fatigue") || lower.contains("score") {
            let score = EnergyScoreEngine.score(from: analysis)
            return "Ton énergie est de \(score.energyScore) sur 100 aujourd'hui, avec un état \(score.moodLabel.rawValue)."
        }

        if lower.contains("coeur") || lower.contains("cœur") || lower.contains("hrv") || lower.contains("récupération") || lower.contains("recuperation") {
            let hrvText = analysis.averageHRV > 0 ? " Ton HRV moyenne est de \(Int(analysis.averageHRV.rounded())) millisecondes." : ""
            let restingHeartRateText = analysis.restingHeartRate.map { " Ta fréquence cardiaque au repos est de \(Int($0.rounded())) battements par minute." } ?? ""
            return "Voici ta récupération sur Komo.\(hrvText)\(restingHeartRateText)"
        }

        return "Je peux te répondre sur ton énergie, ton sommeil, ton stress, ton activité, tes pas ou ta récupération. Essaie par exemple : quelle est mon énergie sur Komo ?"
    }

    private func localizedStressLevel(_ level: StressLevel) -> String {
        switch level {
        case .low:
            return "bas"
        case .medium:
            return "modéré"
        case .high:
            return "élevé"
        }
    }
}
