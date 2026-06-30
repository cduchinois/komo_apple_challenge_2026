import AppIntents
import Foundation

struct CheckSleepQualityIntent: AppIntent {
    static var title: LocalizedStringResource = "Vérifier mon sommeil"
    static var description = IntentDescription(
        "Donne le score et les détails de sommeil du jour avec Komo"
    )

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let analyzer = HealthAnalyzer.shared
        let healthKit = HealthKitManager.shared
        guard let summary = try? await healthKit.fetchDailySummary(for: Date()) else {
            return .result(dialog: "Désolé, je n'ai pas pu récupérer tes données de sommeil aujourd'hui.")
        }

        let analysis = analyzer.analyzeDay(summary: summary)
        guard let sleep = analysis.sleepAssessment else {
            return .result(dialog: "Je n'ai pas trouvé de données de sommeil pour aujourd'hui sur Komo.")
        }

        let hours = sleep.data.totalSleepMinutes / 60.0
        let category = localizedSleepCategory(sleep.category)
        let dialog = IntentDialog(
            stringLiteral: "Ton sommeil est \(category), avec un score de \(Int(sleep.score.rounded())) sur 100. Tu as dormi \(String(format: "%.1f", hours)) heures, avec \(Int((sleep.data.deepSleepPct * 100).rounded())) pour cent de sommeil profond et \(sleep.data.awakeCount) réveil(s)."
        )

        return .result(dialog: dialog)
    }

    private func localizedSleepCategory(_ category: SleepCategory) -> String {
        switch category {
        case .poor:
            return "faible"
        case .fair:
            return "correct"
        case .good:
            return "bon"
        case .excellent:
            return "excellent"
        }
    }
}
