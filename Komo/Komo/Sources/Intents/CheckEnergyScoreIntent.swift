import AppIntents
import SwiftUI

struct CheckEnergyScoreIntent: AppIntent {
    static var title: LocalizedStringResource = "Vérifier mon niveau d'énergie"
    static var description = IntentDescription(
        "Donne le score d'énergie actuel de Komo avec un conseil personnalisé"
    )
    
    // Siri va l'annoncer sans ouvrir l'app si possible
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Demande une analyse complète
        let analyzer = HealthAnalyzer.shared
        let healthKit = HealthKitManager.shared
        guard let summary = try? await healthKit.fetchDailySummary(for: Date()) else {
            return .result(dialog: "Désolé, je n'ai pas pu analyser tes données de santé aujourd'hui.")
        }
        
        let analysis = analyzer.analyzeDay(summary: summary)
        let score = EnergyScoreEngine.score(from: analysis)
        let energyLevel = score.moodLabel
        
        // Obtenir un insight via le générateur local pour le dialogue Siri
        let insight = await InsightGenerator.shared.generateBubbleInsight(from: analysis, mood: energyLevel)
        
        // Dialogue naturel pour Siri
        let dialog = IntentDialog(
            stringLiteral: "Ton énergie est de \(score.energyScore) sur 100 aujourd'hui. \(insight)"
        )
        
        return .result(dialog: dialog)
    }
}
