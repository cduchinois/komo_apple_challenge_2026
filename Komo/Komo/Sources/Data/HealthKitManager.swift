import Foundation
import HealthKit
import Combine

// MARK: - HealthKit Errors

enum HealthKitError: LocalizedError {
    case healthDataNotAvailable
    case authorizationFailed
    case queryFailed(String)
    case invalidQuantityType
    case noData

    var errorDescription: String? {
        switch self {
        case .healthDataNotAvailable:
            return "HealthKit is not available on this device."
        case .authorizationFailed:
            return "HealthKit authorization was denied."
        case .queryFailed(let reason):
            return "HealthKit query failed: \(reason)"
        case .invalidQuantityType:
            return "Invalid quantity type requested."
        case .noData:
            return "No health data found for the requested period."
        }
    }
}

// MARK: - HealthKitManager

/// Central service for HealthKit authorization and data queries.
/// Provides async/await APIs for all health metrics consumed by CoreML models.
@MainActor
final class HealthKitManager: ObservableObject {

    // MARK: - Singleton

    static let shared = HealthKitManager()

    // MARK: - Published State

    @Published var isAuthorized = false

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()

    private init() {}

    // MARK: - Read Types

    /// All HealthKit types the app needs read access to.
    private var readTypes: Set<HKObjectType> {
        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .stepCount,
            .activeEnergyBurned,
            .respiratoryRate,
            .oxygenSaturation,
            .physicalEffort,          // METs — intensité réelle (iOS 17+)
            .walkingHeartRateAverage, // FC marche — utile pour le modèle stress
            .flightsClimbed,          // Étages — signal activité supplémentaire
        ]

        var types = Set<HKObjectType>()

        for identifier in quantityTypes {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        if let standType = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
            types.insert(standType)
        }

        types.insert(HKWorkoutType.workoutType())

        return types
    }

    // MARK: - Authorization

    /// Requests read authorization for all required HealthKit data types.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.healthDataNotAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        isAuthorized = true
    }

    // MARK: - Heart Rate

    /// Fetches heart rate samples within the given date range.
    func fetchHeartRateSamples(from startDate: Date, to endDate: Date) async throws -> [HeartRateSample] {
        guard let sampleType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitError.invalidQuantityType
        }

        let samples: [HKQuantitySample] = try await querySamples(
            type: sampleType,
            from: startDate,
            to: endDate
        )

        return samples.map { sample in
            HeartRateSample(
                bpm: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                date: sample.startDate
            )
        }
    }

    // MARK: - HRV

    /// Fetches HRV (SDNN) samples within the given date range.
    func fetchHRVSamples(from startDate: Date, to endDate: Date) async throws -> [HRVSample] {
        guard let sampleType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.invalidQuantityType
        }

        let samples: [HKQuantitySample] = try await querySamples(
            type: sampleType,
            from: startDate,
            to: endDate
        )

        return samples.map { sample in
            HRVSample(
                sdnn: sample.quantity.doubleValue(for: .secondUnit(with: .milli)),
                date: sample.startDate
            )
        }
    }

    // MARK: - Sleep

    /// Fetches and aggregates sleep data for the night before the given date.
    ///
    /// Queries the window from 6 PM the previous day to noon of the given day
    /// to capture the full overnight sleep session.
    func fetchSleepData(for date: Date) async throws -> SleepData? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let previousEvening = calendar.date(byAdding: .hour, value: -18, to: noon)!

        let samples: [HKCategorySample] = try await querySamples(
            type: sleepType,
            from: previousEvening,
            to: noon
        )

        guard !samples.isEmpty else { return nil }

        // Classify samples by sleep stage
        var totalSleepSeconds: TimeInterval = 0
        var deepSleepSeconds: TimeInterval = 0
        var remSleepSeconds: TimeInterval = 0
        var awakeSamples: [(start: Date, end: Date)] = []  // pour fusionner les épisodes
        var firstInBedDate: Date?
        var firstAsleepDate: Date?
        var sleepWindowStart: Date?
        var sleepWindowEnd: Date?

        for sample in samples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)

            switch value {
            case .inBed:
                if firstInBedDate == nil || sample.startDate < firstInBedDate! {
                    firstInBedDate = sample.startDate
                }
            case .asleepCore:
                totalSleepSeconds += duration
                if firstAsleepDate == nil || sample.startDate < firstAsleepDate! {
                    firstAsleepDate = sample.startDate
                }
            case .asleepDeep:
                totalSleepSeconds += duration
                deepSleepSeconds += duration
                if firstAsleepDate == nil || sample.startDate < firstAsleepDate! {
                    firstAsleepDate = sample.startDate
                }
            case .asleepREM:
                totalSleepSeconds += duration
                remSleepSeconds += duration
                if firstAsleepDate == nil || sample.startDate < firstAsleepDate! {
                    firstAsleepDate = sample.startDate
                }
            case .awake:
                // Accumule les samples éveillés — on fusionnera ensuite en épisodes
                awakeSamples.append((start: sample.startDate, end: sample.endDate))
            default:
                break
            }

            // Track overall sleep window
            if value == .asleepCore || value == .asleepDeep || value == .asleepREM {
                if sleepWindowStart == nil || sample.startDate < sleepWindowStart! {
                    sleepWindowStart = sample.startDate
                }
                if sleepWindowEnd == nil || sample.endDate > sleepWindowEnd! {
                    sleepWindowEnd = sample.endDate
                }
            }
        }

        // Fusionne les samples éveillés contigus en épisodes distincts
        // (gap < 5 min entre deux samples = même réveil)
        let sortedAwake = awakeSamples.sorted { $0.start < $1.start }
        var awakeEpisodes: [(start: Date, end: Date)] = []
        var totalAwakeSeconds: TimeInterval = 0
        for sample in sortedAwake {
            if let last = awakeEpisodes.last,
               sample.start.timeIntervalSince(last.end) < 5 * 60 {
                // Fusionne avec le dernier épisode
                awakeEpisodes[awakeEpisodes.count - 1].end = max(last.end, sample.end)
            } else {
                awakeEpisodes.append(sample)
            }
            totalAwakeSeconds += sample.end.timeIntervalSince(sample.start)
        }
        let awakeCount = awakeEpisodes.count
        let awakeMinutes = totalAwakeSeconds / 60.0

        let totalSleepMinutes = totalSleepSeconds / 60.0
        // ⚠️ FIX: le SleepQualityScorer attend des fractions (0.21), PAS des pourcentages (21)
        let deepSleepPct = totalSleepSeconds > 0 ? deepSleepSeconds / totalSleepSeconds : 0
        let remSleepPct  = totalSleepSeconds > 0 ? remSleepSeconds  / totalSleepSeconds : 0

        // Sleep onset latency: time from first inBed to first asleep
        let sleepOnsetLatencyMin: Double
        if let inBed = firstInBedDate, let asleep = firstAsleepDate, asleep > inBed {
            sleepOnsetLatencyMin = asleep.timeIntervalSince(inBed) / 60.0
        } else {
            sleepOnsetLatencyMin = 0
        }

        // Resting HR during sleep window
        let restingHRDuringSleep: Double
        if let windowStart = sleepWindowStart, let windowEnd = sleepWindowEnd {
            let hrSamples = try await fetchHeartRateSamples(from: windowStart, to: windowEnd)
            restingHRDuringSleep = hrSamples.isEmpty
                ? 0
                : hrSamples.map(\.bpm).reduce(0, +) / Double(hrSamples.count)
        } else {
            restingHRDuringSleep = 0
        }

        // Respiratory rate during sleep window
        let respiratoryRateValue: Double
        if let windowStart = sleepWindowStart, let windowEnd = sleepWindowEnd {
            respiratoryRateValue = try await fetchAverageQuantity(
                identifier: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                from: windowStart,
                to: windowEnd
            )
        } else {
            respiratoryRateValue = 0
        }

        // Blood oxygen during sleep window
        let bloodOxygenAvg: Double
        if let windowStart = sleepWindowStart, let windowEnd = sleepWindowEnd {
            bloodOxygenAvg = try await fetchAverageQuantity(
                identifier: .oxygenSaturation,
                unit: .percent(),
                from: windowStart,
                to: windowEnd
            )
            // HealthKit retourne SpO2 en fraction (0.97), le modèle attend une fraction — pas de * 100
        } else {
            bloodOxygenAvg = 0
        }

        // Bedtime consistency: std dev of bedtimes over the past 7 nights
        let bedtimeConsistencyMin = try await computeBedtimeConsistency(relativeTo: date, nights: 7)

        return SleepData(
            totalSleepMinutes: totalSleepMinutes,
            deepSleepPct: deepSleepPct,
            remSleepPct: remSleepPct,
            awakeCount: awakeCount,
            awakeMinutes: awakeMinutes,
            sleepOnsetLatencyMin: sleepOnsetLatencyMin,
            restingHRDuringSleep: restingHRDuringSleep,
            respiratoryRate: respiratoryRateValue,
            bloodOxygenAvg: bloodOxygenAvg,
            bedtimeConsistencyMin: bedtimeConsistencyMin
        )
    }

    // MARK: - Steps

    /// Fetches cumulative step count for the given date range.
    func fetchStepCount(from startDate: Date, to endDate: Date) async throws -> Double {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.invalidQuantityType
        }

        let statistics = try await queryStatistics(
            type: stepType,
            from: startDate,
            to: endDate,
            options: .cumulativeSum
        )

        return statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
    }

    // MARK: - Physical Effort (METs)

    /// Fetches the average METs (Physical Effort) for the given date range.
    ///
    /// METs (Metabolic Equivalents) est la mesure d'intensité directe fournie par Apple Watch (iOS 17+).
    /// Classification :
    ///   < 1.5 : sédentaire
    ///   1.5-3 : léger (Zone 1-2) → Récupération
    ///   3-6   : modéré (Zone 2-3) → Récup partielle
    ///   6-9   : vigoureux (Zone 3-4) → neutre
    ///   > 9   : très vigoureux (Zone 4-5) → Charge
    func fetchAverageMETs(from startDate: Date, to endDate: Date) async throws -> Double {
        guard let metsType = HKQuantityType.quantityType(forIdentifier: .physicalEffort) else {
            return 1.0  // Fallback : sédentaire
        }

        let statistics = try await queryStatistics(
            type: metsType,
            from: startDate,
            to: endDate,
            options: .discreteAverage
        )

        // METs en kcal/(kg·h) dans HealthKit
        let unit = HKUnit.kilocalorie().unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .hour()))
        return statistics?.averageQuantity()?.doubleValue(for: unit) ?? 1.0
    }

    // MARK: - Active Energy

    /// Fetches the total active energy burned (kcal) for the given date range.
    func fetchActiveEnergy(from startDate: Date, to endDate: Date) async throws -> Double {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.invalidQuantityType
        }

        let statistics = try await queryStatistics(
            type: energyType,
            from: startDate,
            to: endDate,
            options: .cumulativeSum
        )

        return statistics?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0.0
    }

    // MARK: - Resting Heart Rate

    /// Fetches the latest resting heart rate sample for the given day.
    func fetchRestingHeartRate(for date: Date) async throws -> Double? {
        guard let sampleType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthKitError.invalidQuantityType
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let samples: [HKQuantitySample] = try await querySamples(
            type: sampleType,
            from: startOfDay,
            to: endOfDay,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)],
            limit: 1
        )

        return samples.first?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    // MARK: - Workouts

    /// Fetches total workout duration in minutes for the given day.
    func fetchWorkoutMinutes(for date: Date) async throws -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let workouts: [HKWorkout] = try await querySamples(
            type: HKWorkoutType.workoutType(),
            from: startOfDay,
            to: endOfDay
        )

        return workouts.reduce(0) { $0 + $1.duration / 60.0 }
    }

    // MARK: - Hourly Aggregation

    /// Aggregates health data into hourly buckets for the given day.
    /// Each bucket includes heart rate, HRV, steps, workout status, and meeting count.
    func fetchHourlyData(for date: Date) async throws -> [HourlyHealthData] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        // Fetch full-day data in bulk to avoid 24 individual queries
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        async let hrSamplesTask = fetchHeartRateSamples(from: startOfDay, to: endOfDay)
        async let hrvSamplesTask = fetchHRVSamples(from: startOfDay, to: endOfDay)
        async let workoutsTask: [HKWorkout] = querySamples(
            type: HKWorkoutType.workoutType(),
            from: startOfDay,
            to: endOfDay
        )

        let hrSamples = (try? await hrSamplesTask) ?? []
        let hrvSamples = (try? await hrvSamplesTask) ?? []
        let workouts = (try? await workoutsTask) ?? []

        // Fetch meeting events for the day
        let events = (try? await EventKitManager.shared.fetchEvents(for: date)) ?? []

        var hourlyData: [HourlyHealthData] = []

        for hour in 0..<24 {
            let hourStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay)!
            let hourEnd = calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay)!

            // Filter HR samples for this hour
            let hourHR = hrSamples.filter { $0.date >= hourStart && $0.date < hourEnd }

            // Filter HRV samples for this hour
            let hourHRV = hrvSamples.filter { $0.date >= hourStart && $0.date < hourEnd }

            // Step count for this hour (requires a separate statistics query)
            let steps = try await fetchStepCount(from: hourStart, to: hourEnd)

            // Check if any workout overlaps with this hour
            let isWorkout = workouts.contains { workout in
                workout.startDate < hourEnd && workout.endDate > hourStart
            }

            // Count meetings that overlap with this hour
            let meetingCount = events.filter { event in
                event.startDate < hourEnd && event.endDate > hourStart && !event.isAllDay
            }.count

            hourlyData.append(
                HourlyHealthData(
                    hour: hour,
                    date: hourStart,
                    heartRateSamples: hourHR,
                    hrvSamples: hourHRV,
                    stepCount: steps,
                    isWorkout: isWorkout,
                    meetingCount: meetingCount
                )
            )
        }

        return hourlyData
    }

    // MARK: - Daily Summary

    /// Builds a complete daily health summary combining all data sources.
    func fetchDailySummary(for date: Date) async throws -> DailyHealthSummary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Run independent queries concurrently
        async let hourlyDataTask = fetchHourlyData(for: date)
        async let sleepDataTask = fetchSleepData(for: date)
        async let stepsTask = fetchStepCount(from: startOfDay, to: endOfDay)
        async let energyTask = fetchActiveEnergy(from: startOfDay, to: endOfDay)
        async let workoutMinutesTask = fetchWorkoutMinutes(for: date)
        async let restingHRTask = fetchRestingHeartRate(for: date)
        async let metsTask = fetchAverageMETs(from: startOfDay, to: endOfDay)

        let hourlyData = (try? await hourlyDataTask) ?? []
        let sleepData = try? await sleepDataTask
        let totalSteps = (try? await stepsTask) ?? 0.0
        let totalCalories = (try? await energyTask) ?? 0.0
        let workoutMinutes = (try? await workoutMinutesTask) ?? 0.0
        let restingHR = try? await restingHRTask
        let averageMETs = (try? await metsTask) ?? 1.0

        let totalMeetings = hourlyData.reduce(0) { $0 + $1.meetingCount }

        return DailyHealthSummary(
            date: date,
            hourlyData: hourlyData,
            sleepData: sleepData,
            totalSteps: Int(totalSteps),
            totalCalories: Int(totalCalories),
            totalMeetings: totalMeetings,
            workoutMinutes: workoutMinutes,
            restingHeartRate: restingHR,
            screenTimeMinutes: 285,
            averageMETs: averageMETs
        )
    }

    // MARK: - Generic Sample Query

    /// Generic async wrapper around `HKSampleQuery`.
    ///
    /// - Parameters:
    ///   - type: The `HKSampleType` to query.
    ///   - from: Start of the date range.
    ///   - to: End of the date range.
    ///   - sortDescriptors: Optional sort descriptors.
    ///   - limit: Maximum number of results. Defaults to `HKObjectQueryNoLimit`.
    /// - Returns: Array of samples cast to the requested type.
    private func querySamples<T: HKSample>(
        type: HKSampleType,
        from startDate: Date,
        to endDate: Date,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> [T] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sortDescriptors
            ) { _, results, error in
                if let error {
                    if (error as NSError).code == 11 || error.localizedDescription.contains("No data available") {
                         continuation.resume(returning: [])
                         return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                let typedSamples = (results as? [T]) ?? []
                continuation.resume(returning: typedSamples)
            }

            self.healthStore.execute(query)
        }
    }

    // MARK: - Statistics Query

    /// Async wrapper around `HKStatisticsQuery`.
    ///
    /// - Parameters:
    ///   - type: The `HKQuantityType` to aggregate.
    ///   - from: Start of the date range.
    ///   - to: End of the date range.
    ///   - options: Statistics options (e.g., `.cumulativeSum`, `.discreteAverage`).
    /// - Returns: The resulting `HKStatistics`, or `nil` if no data exists.
    private func queryStatistics(
        type: HKQuantityType,
        from startDate: Date,
        to endDate: Date,
        options: HKStatisticsOptions
    ) async throws -> HKStatistics? {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, error in
                if let error {
                    // HKStatisticsQuery returns an error if no data matches instead of just empty stats.
                    // We treat this as a success with nil stats.
                    if (error as NSError).code == 11 || error.localizedDescription.contains("No data available") {
                         continuation.resume(returning: nil)
                         return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                continuation.resume(returning: statistics)
            }

            self.healthStore.execute(query)
        }
    }

    // MARK: - Sleep Helpers

    /// Computes the average of a quantity type over a date range using `.discreteAverage`.
    private func fetchAverageQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async throws -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.invalidQuantityType
        }

        let statistics = try await queryStatistics(
            type: quantityType,
            from: startDate,
            to: endDate,
            options: .discreteAverage
        )

        return statistics?.averageQuantity()?.doubleValue(for: unit) ?? 0
    }

    /// Computes bedtime consistency as the standard deviation of bedtimes over the last N nights.
    ///
    /// Looks for the earliest `.inBed` category sample each night. Returns the
    /// standard deviation in minutes across all nights that have data.
    private func computeBedtimeConsistency(relativeTo date: Date, nights: Int) async throws -> Double {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return 0
        }

        let calendar = Calendar.current
        var bedtimeMinutesFromMidnight: [Double] = []

        for dayOffset in 1...nights {
            let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: date)!
            let eveningStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: targetDate)!
            let morningEnd = calendar.date(byAdding: .hour, value: 18, to: eveningStart)!

            let samples: [HKCategorySample] = try await querySamples(
                type: sleepType,
                from: eveningStart,
                to: morningEnd
            )

            // Find earliest inBed sample for this night
            let inBedSamples = samples.filter {
                HKCategoryValueSleepAnalysis(rawValue: $0.value) == .inBed
            }

            if let earliest = inBedSamples.min(by: { $0.startDate < $1.startDate }) {
                // Express bedtime as minutes since the night's midnight reference
                let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: targetDate)!)
                let minutesFromMidnight = earliest.startDate.timeIntervalSince(midnight) / 60.0
                bedtimeMinutesFromMidnight.append(minutesFromMidnight)
            }
        }

        guard bedtimeMinutesFromMidnight.count >= 2 else { return 0 }

        // Standard deviation
        let mean = bedtimeMinutesFromMidnight.reduce(0, +) / Double(bedtimeMinutesFromMidnight.count)
        let variance = bedtimeMinutesFromMidnight.reduce(0) { $0 + pow($1 - mean, 2) }
            / Double(bedtimeMinutesFromMidnight.count)
        return sqrt(variance)
    }
}
