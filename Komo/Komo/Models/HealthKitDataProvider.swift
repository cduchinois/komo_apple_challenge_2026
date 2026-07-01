//  HealthKitDataProvider.swift
//  Komo
//
//  Implémentation réelle de EnergyDataProviding.
//  Branche le backend (HealthAvatarEngine + EnergyScoreEngine + InsightGenerator)
//  sur le frontend de ton mate sans toucher aucun fichier Screens/ ou Components/.
//
//  Pattern : AppState reçoit un MockDataProvider au démarrage,
//  puis le remplace par un HealthKitDataProvider une fois les données chargées.

import Foundation
import SwiftData
import SwiftUI

// MARK: - HealthKitDataProvider

/// Provider réel : lit DayAnalysis + EnergyScoreResult et les sert au frontend.
@MainActor
final class HealthKitDataProvider: EnergyDataProviding {

    // MARK: - State

    private var analysis: DayAnalysis?
    private var energyResult: EnergyScoreResult?
    private var baseline: PersonalBaseline?
    private var bubbleInsights: [String] = []
    private let daysTogetherCount: Int

    // MARK: - Init

    init(
        analysis: DayAnalysis,
        energyResult: EnergyScoreResult,
        baseline: PersonalBaseline?,
        bubbleInsights: [String],
        daysTogetherCount: Int
    ) {
        self.analysis = analysis
        self.energyResult = energyResult
        self.baseline = baseline
        self.bubbleInsights = bubbleInsights
        self.daysTogetherCount = daysTogetherCount
    }

    // MARK: - EnergyDataProviding

    func currentSnapshot() -> EnergySnapshot {
        guard let result = energyResult, let analysis = analysis else {
            return MockDataProvider().currentSnapshot()
        }

        let word = energyWord(for: result.moodLabel)
        let percent = result.energyScore
        let headline = bubbleInsights.first ?? fallbackHeadline(analysis: analysis, result: result)

        let rechargedBy = rechargedByText(analysis: analysis)
        let usedBy = usedByText(analysis: analysis)

        return EnergySnapshot(
            word: word,
            percent: percent,
            daysTogether: daysTogetherCount,
            rechargedBy: rechargedBy,
            usedBy: usedBy,
            headlineInsight: headline
        )
    }

    func stats() -> [EnergyStat] {
        guard let analysis = analysis, let result = energyResult else {
            return MockDataProvider().stats()
        }

        var stats: [EnergyStat] = []

        // FC repos
        if let rhr = analysis.restingHeartRate, rhr > 0 {
            let tone: StatTone = rhr < 70 ? .good : .warn
            let sub = rhr < 60 ? "Athlétique · en forme" : rhr < 70 ? "Normal · stable" : "Un peu élevé aujourd'hui"
            stats.append(.init(id: "hr", label: "Fréquence cardiaque", value: "\(Int(rhr))", unit: "bpm", sub: sub, tone: tone))
        }

        // Pas
        if analysis.totalSteps > 0 {
            let pct = min(100, analysis.totalSteps * 100 / 10_000)
            let tone: StatTone = analysis.totalSteps >= 7_000 ? .good : .warn
            let sub = "\(pct)% de ton objectif"
            stats.append(.init(id: "steps", label: "Pas", value: "\(analysis.totalSteps.formatted())", unit: "", sub: sub, tone: tone))
        }

        // Sommeil
        if let sleep = analysis.sleepAssessment {
            let h = Int(sleep.data.totalSleepMinutes / 60)
            let m = Int(sleep.data.totalSleepMinutes) % 60
            let duration = m > 0 ? "\(h)h \(m)m" : "\(h)h"
            let tone: StatTone = sleep.score >= 70 ? .good : .warn
            let sub = sleep.score >= 80 ? "Nuit solide" : sleep.score >= 60 ? "Nuit correcte" : "Nuit courte"
            stats.append(.init(id: "sleep", label: "Sommeil", value: duration, unit: "", sub: sub, tone: tone))
        }

        // Stress CoreML
        let stressLabel = analysis.highStressHours == 0 ? "Bas" : analysis.highStressHours <= 2 ? "Modéré" : "Élevé"
        let stressSub = analysis.highStressHours == 0 ? "Calme toute la journée" : "\(analysis.highStressHours)h de tension détectée"
        let stressTone: StatTone = analysis.highStressHours <= 1 ? .good : .warn
        stats.append(.init(id: "stress", label: "Stress (CoreML)", value: stressLabel, unit: "", sub: stressSub, tone: stressTone))

        // HRV
        if analysis.averageHRV > 0 {
            let hrv = Int(analysis.averageHRV.rounded())
            let pct: Int
            if let b = baseline, b.isReliable, b.hrvAvg > 0 {
                pct = Int((analysis.averageHRV / b.hrvAvg * 100).rounded())
            } else {
                pct = Int((min(analysis.averageHRV, 80) / 80 * 100).rounded())
            }
            let tone: StatTone = hrv >= 50 ? .good : hrv >= 30 ? .good : .warn
            let sub = baseline?.isReliable == true ? "vs ta moyenne perso" : "Signal de récupération"
            stats.append(.init(id: "hrv", label: "HRV Récupération", value: "\(pct)", unit: "%", sub: sub, tone: tone))
        }

        // Calories
        if analysis.totalCalories > 0 {
            let tone: StatTone = analysis.totalCalories >= 300 ? .good : .warn
            stats.append(.init(id: "activity", label: "Activité", value: "\(analysis.totalCalories)", unit: "kcal", sub: "Énergie active brûlée", tone: tone))
        }

        // Réunions / calendrier
        if analysis.totalMeetings > 0 {
            let tone: StatTone = analysis.totalMeetings <= 4 ? .good : .warn
            let sub = analysis.totalMeetings >= 5 ? "Journée chargée" : "Charge mentale modérée"
            stats.append(.init(id: "calendar", label: "Calendrier", value: "\(analysis.totalMeetings)", unit: "événements", sub: sub, tone: tone))
        }

        // Score énergie (récap)
        stats.append(.init(
            id: "hrv",
            label: "Score Énergie",
            value: "\(result.energyScore)",
            unit: "/ 100",
            sub: "\(energyWord(for: result.moodLabel)) · \(result.energyScore)%",
            tone: result.energyScore >= 60 ? .good : .warn
        ))

        return stats
    }

    func headlineInsights() -> [String] {
        if !bubbleInsights.isEmpty { return bubbleInsights }
        guard let analysis = analysis, let result = energyResult else {
            return MockDataProvider().headlineInsights()
        }
        return [fallbackHeadline(analysis: analysis, result: result)]
    }

    func insightLines(for tone: CompanionTone) -> [String] {
        // Utilise les insights IA générés par InsightGenerator si disponibles
        if !bubbleInsights.isEmpty {
            return bubbleInsights
        }
        // Fallback : données réelles mais sans IA
        return MockDataProvider().insightLines(for: tone)
    }

    // MARK: - Helpers privés

    private func energyWord(for mood: MoodLabel) -> String {
        switch mood {
        case .lumineux: return "Bright"
        case .serein:   return "High"
        case .agité:    return "Steady"
        case .fatigué:  return "Low"
        case .lourd:    return "Drained"
        }
    }

    private func rechargedByText(analysis: DayAnalysis) -> String {
        var parts: [String] = []
        if let sleep = analysis.sleepAssessment, sleep.score >= 70 { parts.append("sommeil") }
        if analysis.totalSteps >= 7_000 { parts.append("marche") }
        if analysis.averageHRV >= 50 { parts.append("récup HRV") }
        if parts.isEmpty { parts.append("repos") }
        return parts.prefix(2).joined(separator: " + ")
    }

    private func usedByText(analysis: DayAnalysis) -> String {
        var parts: [String] = []
        if analysis.totalMeetings >= 3 { parts.append("réunions") }
        if analysis.highStressHours >= 2 { parts.append("stress") }
        if let sleep = analysis.sleepAssessment, sleep.score < 60 { parts.append("manque de sommeil") }
        if parts.isEmpty { parts.append("journée normale") }
        return parts.prefix(2).joined(separator: " + ")
    }

    private func fallbackHeadline(analysis: DayAnalysis, result: EnergyScoreResult) -> String {
        if let sleep = analysis.sleepAssessment {
            let h = sleep.data.totalSleepMinutes / 60.0
            if h < 6.5 || sleep.data.awakeCount >= 3 {
                let duration = String(format: "%.0fh%02d", floor(h), Int(sleep.data.totalSleepMinutes) % 60)
                return "Tu as dormi \(duration) avec \(sleep.data.awakeCount) réveils. Garde ta prochaine pause vraiment calme."
            }
        }
        if analysis.highStressHours >= 3 {
            return "\(analysis.highStressHours)h de stress élevé détectés. Bloque 10 minutes sans écran maintenant."
        }
        if analysis.totalSteps < 4_000 {
            return "Tu es à \(analysis.totalSteps) pas aujourd'hui. Une marche de 7 minutes peut relancer ton énergie."
        }
        if analysis.totalMeetings >= 5 {
            return "\(analysis.totalMeetings) événements aujourd'hui. Protège un sas de 12 min entre deux blocs."
        }
        switch result.moodLabel {
        case .lumineux: return "✨ Ton énergie semble disponible. Choisis une seule chose importante."
        case .serein:   return "Tes signaux sont stables. Garde une pause courte avant de repartir."
        case .agité:    return "Komo sent une journée un peu chargée. Fais simple pendant 5 minutes."
        case .fatigué:  return "Ton énergie semble plus basse. Choisis la version minimale de ta prochaine tâche."
        case .lourd:    return "La journée paraît lourde. Protège le prochain quart d'heure."
        }
    }
}
