import Foundation
import HealthKit
import EventKit

// MARK: - HealthKitManager
//
// Centralises all HealthKit + EventKit reads. All functions are async and
// return on the calling context. Types HRSample, HRVSample and
// HealthDailySummary are defined in DayAnalysis.swift (same module).
//
// Authorization: call requestAuthorization() once per app session.
// Data fetch: call fetchDailySummary(for:) to get a HealthDailySummary.

final class HealthKitManager {

    static let shared = HealthKitManager()
    private let store = HKHealthStore()
    private let eventStore = EKEventStore()

    private init() {}

    // MARK: - Types to read

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        let ids: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .stepCount,
            .activeEnergyBurned,
        ]
        for id in ids {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)

        // Calendar read access
        if #available(iOS 17, *) {
            _ = try? await eventStore.requestFullAccessToEvents()
        } else {
            eventStore.requestAccess(to: .event) { _, _ in }
        }
    }

    // MARK: - Daily summary fetch

    func fetchDailySummary(for date: Date) async throws -> HealthDailySummary {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end   = calendar.date(byAdding: .day, value: 1, to: start) ?? date

        async let steps      = fetchSteps(from: start, to: end)
        async let calories   = fetchActiveCalories(from: start, to: end)
        async let hrSamples  = fetchHeartRate(from: start, to: end)
        async let hrvSamples = fetchHRV(from: start, to: end)
        async let rhr        = fetchRestingHR(from: start, to: end)
        async let sleep      = fetchSleep(from: start, to: end)
        async let workouts   = fetchWorkoutMinutes(from: start, to: end)
        async let meetings   = fetchMeetingCount(from: start, to: end)

        return HealthDailySummary(
            steps:              (try? await steps)      ?? 0,
            activeCalories:     (try? await calories)   ?? 0,
            heartRateSamples:   (try? await hrSamples)  ?? [],
            hrvSamples:         (try? await hrvSamples) ?? [],
            restingHR:          (try? await rhr),
            sleepSamples:       (try? await sleep)      ?? [],
            workoutMinutes:     (try? await workouts)   ?? 0,
            meetingCount:       await meetings
        )
    }

    // MARK: - Steps

    private func fetchSteps(from start: Date, to end: Date) async throws -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred,
                                      options: .cumulativeSum) { _, stats, error in
                if let error { cont.resume(throwing: error); return }
                let count = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                cont.resume(returning: Int(count))
            }
            store.execute(q)
        }
    }

    // MARK: - Active Calories

    private func fetchActiveCalories(from start: Date, to end: Date) async throws -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred,
                                      options: .cumulativeSum) { _, stats, error in
                if let error { cont.resume(throwing: error); return }
                let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                cont.resume(returning: Int(kcal))
            }
            store.execute(q)
        }
    }

    // MARK: - Heart Rate

    private func fetchHeartRate(from start: Date, to end: Date) async throws -> [HRSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let bpmUnit = HKUnit(from: "count/min")
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let result = (samples as? [HKQuantitySample])?.map {
                    HRSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: bpmUnit))
                } ?? []
                cont.resume(returning: result)
            }
            store.execute(q)
        }
    }

    // MARK: - HRV

    private func fetchHRV(from start: Date, to end: Date) async throws -> [HRVSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let msUnit = HKUnit.secondUnit(with: .milli)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let result = (samples as? [HKQuantitySample])?.map {
                    HRVSample(date: $0.startDate, ms: $0.quantity.doubleValue(for: msUnit))
                } ?? []
                cont.resume(returning: result)
            }
            store.execute(q)
        }
    }

    // MARK: - Resting Heart Rate

    private func fetchRestingHR(from start: Date, to end: Date) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let bpmUnit = HKUnit(from: "count/min")
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let rhr = (samples as? [HKQuantitySample])?.first?
                    .quantity.doubleValue(for: bpmUnit)
                cont.resume(returning: rhr)
            }
            store.execute(q)
        }
    }

    // MARK: - Sleep

    private func fetchSleep(from start: Date, to end: Date) async throws -> [HKCategorySample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let nightStart = Calendar.current.date(byAdding: .hour, value: -12, to: start) ?? start
        let pred = HKQuery.predicateForSamples(withStart: nightStart, end: end)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
    }

    // MARK: - Workout Minutes

    private func fetchWorkoutMinutes(from start: Date, to end: Date) async throws -> Double {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(), predicate: pred,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let total = (samples as? [HKWorkout])?.reduce(0) { $0 + $1.duration / 60.0 } ?? 0
                cont.resume(returning: total)
            }
            store.execute(q)
        }
    }

    // MARK: - Calendar Meetings (EventKit)

    func fetchMeetingCount(from start: Date, to end: Date) async -> Int {
        let pred   = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: pred)
        return events.filter { !$0.isAllDay && $0.endDate.timeIntervalSince($0.startDate) > 300 }.count
    }

    // MARK: - 30-day Personal Baseline (HRV + RHR rolling averages)
    //
    // Fetches the last 30 days of HRV SDNN and resting HR samples, computes
    // their means, and persists them via PersonalBaseline.save() so the
    // EnergyScoreEngine sigmoid uses personal reference points instead of
    // the population median (50 ms / 65 bpm).

    func fetchAndStoreBaseline() async {
        let calendar  = Calendar.current
        let end       = Date()
        let start     = calendar.date(byAdding: .day, value: -30, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        // ── HRV SDNN ──────────────────────────────────────────────────────────
        let avgHRV: Double
        if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            let msUnit = HKUnit.secondUnit(with: .milli)
            avgHRV = await withCheckedContinuation { cont in
                let q = HKSampleQuery(
                    sampleType: hrvType, predicate: predicate,
                    limit: HKObjectQueryNoLimit, sortDescriptors: nil
                ) { _, samples, _ in
                    let vals = (samples as? [HKQuantitySample])?
                        .map { $0.quantity.doubleValue(for: msUnit) } ?? []
                    let avg = vals.isEmpty ? 0.0 : vals.reduce(0, +) / Double(vals.count)
                    cont.resume(returning: avg)
                }
                store.execute(q)
            }
        } else { avgHRV = 0 }

        // ── Resting HR ────────────────────────────────────────────────────────
        let avgRHR: Double
        if let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            let bpmUnit = HKUnit(from: "count/min")
            avgRHR = await withCheckedContinuation { cont in
                let q = HKSampleQuery(
                    sampleType: rhrType, predicate: predicate,
                    limit: HKObjectQueryNoLimit, sortDescriptors: nil
                ) { _, samples, _ in
                    let vals = (samples as? [HKQuantitySample])?
                        .map { $0.quantity.doubleValue(for: bpmUnit) } ?? []
                    let avg = vals.isEmpty ? 0.0 : vals.reduce(0, +) / Double(vals.count)
                    cont.resume(returning: avg)
                }
                store.execute(q)
            }
        } else { avgRHR = 0 }

        // Persist only when we have meaningful data (> 1 reading)
        if avgHRV > 1 || avgRHR > 1 {
            PersonalBaseline(HRVavg: avgHRV, RHRavg: avgRHR).save()
        }
    }
}
