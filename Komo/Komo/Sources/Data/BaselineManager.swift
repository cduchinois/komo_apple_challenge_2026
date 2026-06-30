import Foundation
import SwiftData

// MARK: - PersonalBaseline
//
// Moyennes personnelles calculées sur les N derniers jours (défaut 14).
// Utilisé par EnergyScoreEngine pour comparer les données du jour
// à l'historique de l'utilisateur (modèle Whoop/Oura).

struct PersonalBaseline {
    /// Moyenne HRV SDNN sur la fenêtre (ms)
    let hrvAvg: Double

    /// Moyenne FC repos sur la fenêtre (BPM)
    let restingHRAvg: Double

    /// Moyenne durée de sommeil (minutes)
    let sleepMinutesAvg: Double

    /// Moyenne du score de sommeil (0-100)
    let sleepScoreAvg: Double

    /// Moyenne des pas quotidiens
    let stepsAvg: Double

    /// Moyenne du score d'énergie (0-100)
    let energyScoreAvg: Double

    /// Moyenne des heures de stress élevé par jour
    let highStressHoursAvg: Double

    /// Nombre de jours dans l'historique (0 = aucune donnée)
    let dataPointCount: Int

    /// True si on a assez de données pour une baseline fiable (≥ 3 jours)
    var isReliable: Bool { dataPointCount >= 3 }

    /// Baseline vide (aucun historique)
    static let empty = PersonalBaseline(
        hrvAvg: 0, restingHRAvg: 0, sleepMinutesAvg: 0,
        sleepScoreAvg: 0, stepsAvg: 0, energyScoreAvg: 0,
        highStressHoursAvg: 0, dataPointCount: 0
    )
}

// MARK: - BaselineManager

/// Calcule les baselines personnelles à partir de l'historique SwiftData.
///
/// Usage :
/// ```swift
/// let baseline = BaselineManager.computeBaseline(context: modelContext)
/// // baseline.hrvAvg = 55.3 (ta moyenne sur 14 jours)
/// // baseline.isReliable = true (si ≥ 3 jours de données)
/// ```
struct BaselineManager {

    /// Nombre de jours pour la fenêtre glissante (défaut 14, comme Whoop)
    static let windowDays = 14

    /// Calcule la baseline personnelle sur les N derniers jours.
    ///
    /// - Parameter context: Le ModelContext SwiftData de l'app
    /// - Returns: PersonalBaseline avec les moyennes calculées
    @MainActor
    static func computeBaseline(context: ModelContext) -> PersonalBaseline {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -windowDays,
            to: Date()
        )!

        // Exclure le jour actuel (on ne veut pas que le snapshot en cours
        // d'écriture pollue la baseline)
        let todayKey = DailySnapshot.key(for: Date())

        let predicate = #Predicate<DailySnapshot> { snapshot in
            snapshot.date >= cutoffDate && snapshot.dateKey != todayKey
        }

        let descriptor = FetchDescriptor<DailySnapshot>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        do {
            let snapshots = try context.fetch(descriptor)

            guard !snapshots.isEmpty else {
                print("📊 Baseline: aucun historique disponible")
                return .empty
            }

            let count = snapshots.count

            // Filtrer les valeurs à 0 (jours sans données Watch/sommeil)
            let hrvValues = snapshots.map(\.hrvAvg).filter { $0 > 0 }
            let rhrValues = snapshots.map(\.restingHR).filter { $0 > 0 }
            let sleepValues = snapshots.map(\.sleepMinutes).filter { $0 > 0 }
            let sleepScoreValues = snapshots.map(\.sleepScore).filter { $0 > 0 }
            let stepValues = snapshots.map { Double($0.steps) }
            let energyValues = snapshots.map { Double($0.energyScore) }
            let stressValues = snapshots.map { Double($0.highStressHours) }

            let baseline = PersonalBaseline(
                hrvAvg: safeAverage(hrvValues),
                restingHRAvg: safeAverage(rhrValues),
                sleepMinutesAvg: safeAverage(sleepValues),
                sleepScoreAvg: safeAverage(sleepScoreValues),
                stepsAvg: safeAverage(stepValues),
                energyScoreAvg: safeAverage(energyValues),
                highStressHoursAvg: safeAverage(stressValues),
                dataPointCount: count
            )

            print("📊 Baseline: \(count) jours d'historique | HRV avg=\(String(format: "%.1f", baseline.hrvAvg))ms | Sleep avg=\(String(format: "%.0f", baseline.sleepMinutesAvg))min | Energy avg=\(String(format: "%.0f", baseline.energyScoreAvg))")

            return baseline

        } catch {
            print("⚠️ BaselineManager fetch error: \(error.localizedDescription)")
            return .empty
        }
    }

    /// Sauvegarde ou met à jour le snapshot du jour.
    ///
    /// Si un snapshot existe déjà pour aujourd'hui (même dateKey),
    /// il est mis à jour. Sinon, un nouveau est inséré.
    @MainActor
    static func saveSnapshot(
        _ snapshot: DailySnapshot,
        context: ModelContext
    ) {
        let key = snapshot.dateKey
        let predicate = #Predicate<DailySnapshot> { s in
            s.dateKey == key
        }
        let descriptor = FetchDescriptor<DailySnapshot>(predicate: predicate)

        do {
            let existing = try context.fetch(descriptor)
            if let old = existing.first {
                // Mise à jour du snapshot existant (upsert)
                old.hrvAvg = snapshot.hrvAvg
                old.restingHR = snapshot.restingHR
                old.sleepMinutes = snapshot.sleepMinutes
                old.sleepScore = snapshot.sleepScore
                old.deepSleepPct = snapshot.deepSleepPct
                old.remSleepPct = snapshot.remSleepPct
                old.awakeCount = snapshot.awakeCount
                old.steps = snapshot.steps
                old.calories = snapshot.calories
                old.workoutMinutes = snapshot.workoutMinutes
                old.averageMETs = snapshot.averageMETs
                old.highStressHours = snapshot.highStressHours
                old.meetings = snapshot.meetings
                old.screenTimeMinutes = snapshot.screenTimeMinutes
                old.energyScore = snapshot.energyScore
                old.moodLabel = snapshot.moodLabel
                print("💾 Snapshot mis à jour pour \(key)")
            } else {
                // Nouveau jour → insertion
                context.insert(snapshot)
                print("💾 Nouveau snapshot sauvegardé pour \(key)")
            }
            try context.save()
        } catch {
            print("⚠️ BaselineManager save error: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func safeAverage(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
