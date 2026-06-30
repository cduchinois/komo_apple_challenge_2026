import AppIntents
import Foundation

struct CheckStressLevelIntent: AppIntent {
    static var title: LocalizedStringResource = "Vérifier mon stress"
    static var description = IntentDescription(
        "Donne le niveau de stress détecté aujourd'hui avec Komo"
    )

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let analyzer = HealthAnalyzer.shared
        let healthKit = HealthKitManager.shared
        guard let summary = try? await healthKit.fetchDailySummary(for: Date()) else {
            return .result(dialog: "Désolé, je n'ai pas pu récupérer tes données de stress aujourd'hui.")
        }

        let analysis = analyzer.analyzeDay(summary: summary)
        guard !analysis.stressTimeline.isEmpty else {
            return .result(dialog: "Je n'ai pas assez de données cardiaques aujourd'hui pour estimer ton stress sur Komo.")
        }

        let level = localizedStressLevel(analysis.averageStressLevel)
        let highStressHours = analysis.highStressHours
        let peakText: String
        if let peak = analysis.peakStressHour {
            peakText = " Le pic semble être vers \(peak.hour) heures, avec une fréquence cardiaque moyenne de \(Int(peak.meanHR.rounded())) battements par minute."
        } else {
            peakText = " Je ne vois pas de pic de stress élevé aujourd'hui."
        }

        let dialog = IntentDialog(
            stringLiteral: "Ton niveau de stress moyen est \(level) aujourd'hui. Komo détecte \(highStressHours) heure(s) de stress élevé.\(peakText)"
        )

        return .result(dialog: dialog)
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
