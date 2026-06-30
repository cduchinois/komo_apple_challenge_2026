import AppIntents
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum KomoHealthMetric: String, AppEnum {
    case energy
    case sleep
    case stress
    case activity
    case recovery

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Donnée santé")

    static var caseDisplayRepresentations: [KomoHealthMetric: DisplayRepresentation] = [
        .energy: "énergie",
        .sleep: "sommeil",
        .stress: "stress",
        .activity: "activité",
        .recovery: "récupération"
    ]
}

struct CheckKomoHealthMetricIntent: AppIntent {
    static var title: LocalizedStringResource = "Consulter une donnée Komo"
    static var description = IntentDescription(
        "Répond sur l'énergie, le sommeil, le stress, l'activité ou la récupération du jour"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Donnée")
    var metric: KomoHealthMetric

    static var parameterSummary: some ParameterSummary {
        Summary("Consulter \(\.$metric) sur Komo")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let healthKit = HealthKitManager.shared
        let analyzer = HealthAnalyzer.shared
        guard let summary = try? await healthKit.fetchDailySummary(for: Date()) else {
            return .result(dialog: "Désolé, je n'ai pas pu récupérer tes données santé aujourd'hui.")
        }

        let analysis = analyzer.analyzeDay(summary: summary)
        let answer = await answer(for: metric, analysis: analysis)
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }

    private func answer(for metric: KomoHealthMetric, analysis: DayAnalysis) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), SystemLanguageModel.default.isAvailable {
            do {
                let session = LanguageModelSession(instructions: buildPrompt(from: analysis))
                let response = try await session.respond(to: "Réponds sur ma donnée \(displayName(for: metric)) aujourd'hui.")
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            } catch {
                print("CheckKomoHealthMetricIntent Foundation Models failed: \(error.localizedDescription)")
            }
        }
        #endif

        return fallbackAnswer(for: metric, analysis: analysis)
    }

    private func buildPrompt(from analysis: DayAnalysis) -> String {
        let energy = EnergyScoreEngine.score(from: analysis)
        var parts: [String] = [
            "ENERGIE: \(energy.energyScore)/100, humeur \(energy.moodLabel.rawValue)",
            "ACTIVITE: \(analysis.totalSteps) pas, \(analysis.totalCalories) calories actives, \(Int(analysis.workoutMinutes.rounded())) minutes d'entrainement",
            "STRESS: niveau moyen \(analysis.averageStressLevel.rawValue), \(analysis.highStressHours) heure(s) de stress eleve",
            "AGENDA: \(analysis.totalMeetings) reunion(s)"
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

        if analysis.averageHRV > 0 {
            parts.append("HRV: \(Int(analysis.averageHRV.rounded())) ms SDNN")
        }

        return """
        Tu es Komo, un assistant vocal de sante personnel.
        Reponds uniquement avec les donnees ci-dessous. N'invente jamais de metrique absente.
        Reponds en francais, naturellement, en 1 a 3 phrases maximum, avec les chiffres utiles.

        Donnees du jour:
        \(parts.joined(separator: "\n"))
        """
    }

    private func fallbackAnswer(for metric: KomoHealthMetric, analysis: DayAnalysis) -> String {
        switch metric {
        case .energy:
            let score = EnergyScoreEngine.score(from: analysis)
            return "Ton énergie est de \(score.energyScore) sur 100 aujourd'hui, avec un état \(score.moodLabel.rawValue)."

        case .sleep:
            guard let sleep = analysis.sleepAssessment else {
                return "Je n'ai pas trouvé de données de sommeil pour aujourd'hui sur Komo."
            }

            let hours = sleep.data.totalSleepMinutes / 60.0
            return "Ton sommeil est à \(Int(sleep.score.rounded())) sur 100. Tu as dormi \(String(format: "%.1f", hours)) heures, avec \(Int((sleep.data.deepSleepPct * 100).rounded())) pour cent de sommeil profond et \(sleep.data.awakeCount) réveil(s)."

        case .stress:
            let level = localizedStressLevel(analysis.averageStressLevel)
            if let peak = analysis.peakStressHour {
                return "Ton stress moyen est \(level), avec \(analysis.highStressHours) heure(s) de stress élevé. Le pic semble être vers \(peak.hour) heures, à \(Int(peak.meanHR.rounded())) battements par minute."
            }

            return "Ton stress moyen est \(level), avec \(analysis.highStressHours) heure(s) de stress élevé. Je ne vois pas de pic majeur aujourd'hui."

        case .activity:
            return "Aujourd'hui, tu as fait \(analysis.totalSteps) pas, brûlé environ \(analysis.totalCalories) calories actives et enregistré \(Int(analysis.workoutMinutes.rounded())) minutes d'entraînement."

        case .recovery:
            let hrvText = analysis.averageHRV > 0 ? "Ton HRV moyenne est de \(Int(analysis.averageHRV.rounded())) millisecondes." : "Je n'ai pas de mesure HRV exploitable aujourd'hui."
            let restingHeartRateText = analysis.restingHeartRate.map { " Ta fréquence cardiaque au repos est de \(Int($0.rounded())) battements par minute." } ?? ""
            return "\(hrvText)\(restingHeartRateText)"
        }
    }

    private func displayName(for metric: KomoHealthMetric) -> String {
        switch metric {
        case .energy:
            return "énergie"
        case .sleep:
            return "sommeil"
        case .stress:
            return "stress"
        case .activity:
            return "activité"
        case .recovery:
            return "récupération"
        }
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
