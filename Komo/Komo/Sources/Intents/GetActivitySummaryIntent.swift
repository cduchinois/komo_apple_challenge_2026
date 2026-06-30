import AppIntents
import Foundation

struct GetActivitySummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Résumer mon activité"
    static var description = IntentDescription(
        "Donne les pas, calories et minutes d'entraînement du jour avec Komo"
    )

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let healthKit = HealthKitManager.shared
        guard let summary = try? await healthKit.fetchDailySummary(for: Date()) else {
            return .result(dialog: "Désolé, je n'ai pas pu récupérer ton activité aujourd'hui.")
        }

        let restingHeartRateText: String
        if let restingHeartRate = summary.restingHeartRate {
            restingHeartRateText = " Ta fréquence cardiaque au repos est de \(Int(restingHeartRate.rounded())) battements par minute."
        } else {
            restingHeartRateText = ""
        }

        let dialog = IntentDialog(
            stringLiteral: "Aujourd'hui sur Komo, tu as fait \(summary.totalSteps) pas, brûlé environ \(summary.totalCalories) calories actives et enregistré \(Int(summary.workoutMinutes.rounded())) minutes d'entraînement.\(restingHeartRateText)"
        )

        return .result(dialog: dialog)
    }
}
