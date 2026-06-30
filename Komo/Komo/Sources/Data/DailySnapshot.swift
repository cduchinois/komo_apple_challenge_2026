import Foundation
import SwiftData

// MARK: - DailySnapshot
//
// Un snapshot quotidien persisté via SwiftData.
// Stocke toutes les métriques de santé du jour pour calculer
// les baselines personnelles (moyenne glissante sur 14 jours).
//
// Architecture inspirée de Whoop Recovery / Oura Readiness :
//   → comparer les données du jour à l'historique personnel
//   → "Ton HRV est 12% au-dessus de ta moyenne → bonne récup ↑"

@Model
final class DailySnapshot {

    // MARK: - Identifiant unique (1 snapshot par jour)

    /// Clé unique au format "yyyy-MM-dd" — empêche les doublons
    @Attribute(.unique) var dateKey: String

    /// Date du jour (pour les requêtes temporelles)
    var date: Date

    // MARK: - Recovery Metrics

    /// HRV SDNN moyenne du jour (ms)
    var hrvAvg: Double

    /// Fréquence cardiaque au repos (BPM)
    var restingHR: Double

    /// Durée totale de sommeil (minutes)
    var sleepMinutes: Double

    /// Score de qualité du sommeil (0-100)
    var sleepScore: Double

    /// Pourcentage de sommeil profond (fraction 0.0-1.0)
    var deepSleepPct: Double

    /// Pourcentage de sommeil REM (fraction 0.0-1.0)
    var remSleepPct: Double

    /// Nombre d'épisodes de réveil pendant la nuit
    var awakeCount: Int

    // MARK: - Activity Metrics

    /// Nombre de pas dans la journée
    var steps: Int

    /// Calories actives brûlées (kcal)
    var calories: Int

    /// Minutes d'exercice (workout)
    var workoutMinutes: Double

    /// METs moyens (intensité physique)
    var averageMETs: Double

    // MARK: - Load Metrics

    /// Nombre d'heures de stress élevé (détecté par CoreML StressClassifier)
    var highStressHours: Int

    /// Nombre de réunions dans le calendrier
    var meetings: Int

    /// Temps d'écran (minutes) — hardcodé pour l'instant (contrainte Apple)
    var screenTimeMinutes: Int

    // MARK: - Score Final

    /// Score d'énergie calculé (0-100)
    var energyScore: Int

    /// Label d'humeur ("lumineux", "serein", "agité", "fatigué", "lourd")
    var moodLabel: String

    // MARK: - Init

    init(
        dateKey: String,
        date: Date,
        hrvAvg: Double,
        restingHR: Double,
        sleepMinutes: Double,
        sleepScore: Double,
        deepSleepPct: Double,
        remSleepPct: Double,
        awakeCount: Int,
        steps: Int,
        calories: Int,
        workoutMinutes: Double,
        averageMETs: Double,
        highStressHours: Int,
        meetings: Int,
        screenTimeMinutes: Int,
        energyScore: Int,
        moodLabel: String
    ) {
        self.dateKey = dateKey
        self.date = date
        self.hrvAvg = hrvAvg
        self.restingHR = restingHR
        self.sleepMinutes = sleepMinutes
        self.sleepScore = sleepScore
        self.deepSleepPct = deepSleepPct
        self.remSleepPct = remSleepPct
        self.awakeCount = awakeCount
        self.steps = steps
        self.calories = calories
        self.workoutMinutes = workoutMinutes
        self.averageMETs = averageMETs
        self.highStressHours = highStressHours
        self.meetings = meetings
        self.screenTimeMinutes = screenTimeMinutes
        self.energyScore = energyScore
        self.moodLabel = moodLabel
    }

    // MARK: - Helpers

    /// Crée la clé de date au format "yyyy-MM-dd"
    static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// Crée un snapshot à partir d'un DayAnalysis et d'un EnergyScoreResult
    static func from(
        analysis: DayAnalysis,
        energyResult: EnergyScoreResult
    ) -> DailySnapshot {
        let sleepScore = analysis.sleepAssessment?.score ?? 0
        let sleepMinutes = analysis.sleepAssessment?.data.totalSleepMinutes ?? 0
        let deepPct = analysis.sleepAssessment?.data.deepSleepPct ?? 0
        let remPct = analysis.sleepAssessment?.data.remSleepPct ?? 0
        let awakeCount = analysis.sleepAssessment?.data.awakeCount ?? 0

        return DailySnapshot(
            dateKey: key(for: analysis.date),
            date: analysis.date,
            hrvAvg: analysis.averageHRV,
            restingHR: analysis.restingHeartRate ?? 0,
            sleepMinutes: sleepMinutes,
            sleepScore: sleepScore,
            deepSleepPct: deepPct,
            remSleepPct: remPct,
            awakeCount: awakeCount,
            steps: analysis.totalSteps,
            calories: analysis.totalCalories,
            workoutMinutes: analysis.workoutMinutes,
            averageMETs: analysis.averageMETs,
            highStressHours: analysis.highStressHours,
            meetings: analysis.totalMeetings,
            screenTimeMinutes: analysis.screenTimeMinutes,
            energyScore: energyResult.energyScore,
            moodLabel: energyResult.moodLabel.rawValue
        )
    }
}
