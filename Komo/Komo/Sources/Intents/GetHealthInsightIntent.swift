import AppIntents
import SwiftUI

struct GetHealthInsightIntent: AppIntent {
    static var title: LocalizedStringResource = "Quels sont mes conseils santé ?"
    static var description = IntentDescription(
        "Génère un conseil de santé personnalisé avec Komo basé sur les données du jour"
    )
    
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let analyzer = HealthAnalyzer.shared
        let healthKit = HealthKitManager.shared
        guard let summary = try? await healthKit.fetchDailySummary(for: Date()) else {
            return .result(dialog: "Désolé, je n'ai pas de données de santé disponibles pour aujourd'hui.")
        }
        
        let analysis = analyzer.analyzeDay(summary: summary)
        let insights = await InsightGenerator.shared.generateInsights(from: analysis)
        guard let firstInsight = insights.first else {
            return .result(dialog: "Tout va bien aujourd'hui !")
        }
        
        // Return the first insight for the voice response
        return .result(dialog: IntentDialog(stringLiteral: firstInsight))
    }
}
