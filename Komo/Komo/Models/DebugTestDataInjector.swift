#if DEBUG
import Foundation
import HealthKit
import EventKit

struct DebugTestDataInjectionResult {
    let deletedHealthCount: Int
    let deletedEventCount: Int
    let insertedHealthCount: Int
    let insertedEventCount: Int

    var message: String {
        "Anciennes donnees supprimees: \(deletedHealthCount) HealthKit, \(deletedEventCount) Calendar. Nouvelles donnees injectees: \(insertedHealthCount) HealthKit, \(insertedEventCount) Calendar."
    }
}

enum DebugTestDataInjectionError: LocalizedError {
    case healthUnavailable
    case healthTypeUnavailable(String)
    case healthAuthorizationFailed
    case calendarAccessDenied
    case calendarUnavailable
    case healthSaveFailed
    case healthDeleteFailed

    var errorDescription: String? {
        switch self {
        case .healthUnavailable:
            return "HealthKit is not available on this device."
        case .healthTypeUnavailable(let identifier):
            return "HealthKit type is unavailable: \(identifier)."
        case .healthAuthorizationFailed:
            return "HealthKit write authorization was not granted."
        case .calendarAccessDenied:
            return "Calendar access was denied."
        case .calendarUnavailable:
            return "No writable calendar is available."
        case .healthSaveFailed:
            return "HealthKit did not save the debug samples."
        case .healthDeleteFailed:
            return "HealthKit did not delete the previous debug samples."
        }
    }
}

// MARK: - DebugScenario

enum DebugScenario: CaseIterable {
    /// Poor sleep (~47/100), 2 stress hours, moderate HRV/RHR → target ~15% "Drained"
    case badA
    /// Mediocre sleep (~56/100), 1 stress hour, slightly better bio-markers → target ~24% "Low"
    case badB
    /// Excellent sleep (100/100), no stress, high HRV, low RHR → target ~77% "Steady/Charged"
    case good

    var buttonLabel: String {
        switch self {
        case .badA: return "Injecter : Mauvaise énergie (1)"
        case .badB: return "Injecter : Mauvaise énergie (2)"
        case .good: return "Injecter : Bonne énergie"
        }
    }

    var scenarioLabel: String {
        switch self {
        case .badA: return "Mauvaise énergie 1"
        case .badB: return "Mauvaise énergie 2"
        case .good: return "Bonne énergie"
        }
    }

    fileprivate var profile: DailyProfile {
        switch self {
        case .badA: return .badEnergyA
        case .badB: return .badEnergyB
        case .good: return .goodEnergy
        }
    }
}

// MARK: - Injector

@MainActor
final class DebugTestDataInjector {
    static let shared = DebugTestDataInjector()

    private static let storageKey = "komo.debug.injectedDataIDs.v1"
    private static let metadataMarkerKey = HealthKitManager.debugMetadataKey
    private static let workoutTypeKey = "HKWorkoutType"

    private let healthStore = HKHealthStore()
    private let eventStore = EKEventStore()
    private let calendar = Calendar.current
    private let defaults = UserDefaults.standard

    private init() {}

    func resetAndInject(scenario: DebugScenario) async throws -> DebugTestDataInjectionResult {
        try await requestPermissions()

        let deletedCounts = try await deletePreviousInjectedData()
        let healthObjects = try makeHealthObjects(profile: scenario.profile)
        try await saveHealthObjects(healthObjects)
        saveHealthObjectIDs(healthObjects)

        let events = try makeCalendarEvents()
        let insertedEventIDs = try saveCalendarEvents(events)
        saveCalendarEventIDs(insertedEventIDs)

        return DebugTestDataInjectionResult(
            deletedHealthCount: deletedCounts.health,
            deletedEventCount: deletedCounts.events,
            insertedHealthCount: healthObjects.count,
            insertedEventCount: insertedEventIDs.count
        )
    }

    private func requestPermissions() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw DebugTestDataInjectionError.healthUnavailable
        }

        try await healthStore.requestAuthorization(toShare: healthSampleTypes, read: healthObjectTypes)

        let calendarGranted: Bool
        if #available(iOS 17.0, *) {
            calendarGranted = try await eventStore.requestFullAccessToEvents()
        } else {
            calendarGranted = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }

        guard calendarGranted else {
            throw DebugTestDataInjectionError.calendarAccessDenied
        }
    }

    private var healthObjectTypes: Set<HKObjectType> {
        Set(healthSampleTypes.map { $0 as HKObjectType })
    }

    private var healthSampleTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        for identifier in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    private var quantityIdentifiers: [HKQuantityTypeIdentifier] {
        [
            .stepCount,
            .activeEnergyBurned,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
        ]
    }

    private func deletePreviousInjectedData() async throws -> (health: Int, events: Int) {
        let stored = loadStoredIDs()
        var healthDeleted = 0

        for (typeKey, ids) in stored.healthObjectIDsByType {
            guard let objectType = objectType(for: typeKey) else { continue }
            let uuids = ids.compactMap(UUID.init(uuidString:))
            healthDeleted += try await deleteHealthObjects(type: objectType, uuids: uuids)
        }

        var eventsDeleted = 0
        for id in stored.calendarEventIDs {
            guard let event = eventStore.event(withIdentifier: id) else { continue }
            try eventStore.remove(event, span: .thisEvent, commit: false)
            eventsDeleted += 1
        }
        if eventsDeleted > 0 {
            try eventStore.commit()
        }

        clearStoredIDs()
        return (healthDeleted, eventsDeleted)
    }

    private func saveHealthObjects(_ objects: [HKObject]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(objects) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DebugTestDataInjectionError.healthSaveFailed)
                }
            }
        }
    }

    private func deleteHealthObjects(type: HKObjectType, uuids: [UUID]) async throws -> Int {
        guard !uuids.isEmpty else { return 0 }
        let predicate = HKQuery.predicateForObjects(with: Set(uuids))
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            healthStore.deleteObjects(of: type, predicate: predicate) { success, deletedCount, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: deletedCount)
                } else {
                    continuation.resume(throwing: DebugTestDataInjectionError.healthDeleteFailed)
                }
            }
        }
    }

    private func makeHealthObjects(profile: DailyProfile) throws -> [HKObject] {
        var objects: [HKObject] = []
        let today = Date()
        let bpmUnit = HKUnit(from: "count/min")
        let msUnit = HKUnit.secondUnit(with: .milli)
        // HR samples above this trigger stress classification (fallback rule: mean > RHR + 20)
        let stressThreshold = profile.restingHeartRate + 20

        for dayOffset in stride(from: 6, through: 0, by: -1) {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) ?? today
            let startOfDay = calendar.startOfDay(for: day)
            let activeStart = date(on: startOfDay, hour: 7, minute: Int.random(in: 0...30))
            let activeEnd   = date(on: startOfDay, hour: 22, minute: Int.random(in: 0...20))

            objects.append(try quantitySample(.stepCount, unit: .count(), value: profile.steps, start: activeStart, end: activeEnd))
            objects.append(try quantitySample(.activeEnergyBurned, unit: .kilocalorie(), value: profile.activeCalories, start: activeStart, end: activeEnd))
            objects.append(try quantitySample(.restingHeartRate, unit: bpmUnit, value: profile.restingHeartRate, start: date(on: startOfDay, hour: 6, minute: 40), end: date(on: startOfDay, hour: 6, minute: 45)))
            objects.append(try quantitySample(.heartRateVariabilitySDNN, unit: msUnit, value: profile.hrv, start: date(on: startOfDay, hour: 6, minute: 46), end: date(on: startOfDay, hour: 6, minute: 47)))

            // One sample per hour so every hour bucket has data for stress classification.
            // Stress hours land clearly above threshold; rest hours land clearly below.
            for hour in 8...21 {
                let start = date(on: startOfDay, hour: hour, minute: Int.random(in: 0...45))
                let end   = calendar.date(byAdding: .minute, value: 1, to: start) ?? start
                let bpm: Double
                if profile.stressHours.contains(hour) {
                    bpm = (stressThreshold + Double.random(in: 8...18)).clamped(to: 60...160)
                } else {
                    bpm = (profile.restingHeartRate + Double.random(in: 4...12)).clamped(to: 50...160)
                }
                objects.append(try quantitySample(.heartRate, unit: bpmUnit, value: bpm, start: start, end: end))
            }

            objects.append(contentsOf: try sleepSamples(for: startOfDay, profile: profile))

            if profile.hasWorkout {
                objects.append(try workoutSample(for: startOfDay, profile: profile))
            }
        }

        return objects
    }

    private func quantitySample(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, value: Double, start: Date, end: Date) throws -> HKQuantitySample {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw DebugTestDataInjectionError.healthTypeUnavailable(identifier.rawValue)
        }
        return HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: start,
            end: end,
            metadata: debugMetadata()
        )
    }

    private func sleepSamples(for startOfDay: Date, profile: DailyProfile) throws -> [HKCategorySample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw DebugTestDataInjectionError.healthTypeUnavailable(HKCategoryTypeIdentifier.sleepAnalysis.rawValue)
        }

        let previousDay = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        let sleepStart  = date(on: previousDay, hour: 23, minute: Int.random(in: 0...35))

        // Deterministic durations so the HealthAnalyzer scores match the intended scenario.
        // HealthAnalyzer counts non-awake sleep for D_dur; deep/rem percentages for D_deep/D_rem;
        // number of HKCategorySample .awake objects for D_frag (each costs 4 pts from 20).
        let deepMinutes  = Int(Double(profile.sleepMinutes) * profile.deepSleepFraction)
        let remMinutes   = Int(Double(profile.sleepMinutes) * profile.remSleepFraction)
        let awakeMinutes = profile.awakePeriods * 8   // 8 min per wakeup period
        let coreMinutes  = max(60, profile.sleepMinutes - awakeMinutes - deepMinutes - remMinutes)

        // Layout: core → deep → [awake breaks] → core → rem
        var segments: [(Int, HKCategoryValueSleepAnalysis)] = [
            (coreMinutes / 2, .asleepCore),
            (deepMinutes,     .asleepDeep),
        ]
        for _ in 0..<profile.awakePeriods {
            segments.append((8, .awake))
        }
        segments += [
            (coreMinutes - (coreMinutes / 2), .asleepCore),
            (remMinutes, .asleepREM),
        ]

        var samples: [HKCategorySample] = []
        var cursor = sleepStart
        for (minutes, value) in segments where minutes > 0 {
            let end = calendar.date(byAdding: .minute, value: minutes, to: cursor) ?? cursor
            samples.append(HKCategorySample(type: sleepType, value: value.rawValue, start: cursor, end: end, metadata: debugMetadata()))
            cursor = end
        }
        return samples
    }

    private func workoutSample(for startOfDay: Date, profile: DailyProfile) throws -> HKWorkout {
        let durationMinutes = profile.workoutMinutes
        let start  = date(on: startOfDay, hour: 17, minute: 30)
        let end    = calendar.date(byAdding: .minute, value: Int(durationMinutes), to: start) ?? start
        let energy = HKQuantity(unit: .kilocalorie(), doubleValue: durationMinutes * 8)
        return HKWorkout(
            activityType: .running,
            start: start,
            end: end,
            duration: durationMinutes * 60,
            totalEnergyBurned: energy,
            totalDistance: nil,
            metadata: debugMetadata()
        )
    }

    private func makeCalendarEvents() throws -> [EKEvent] {
        guard let targetCalendar = eventStore.defaultCalendarForNewEvents else {
            throw DebugTestDataInjectionError.calendarUnavailable
        }

        let templates: [(String, Int, Int, String?)] = [
            ("Team sync", 10, 30, "Komo debug sample"),
            ("Deep work block", 14, 90, "Focus window generated by debug injection"),
            ("Project review", 16, 45, "Komo debug sample"),
            ("Coffee with Alex", 11, 45, "Komo debug sample"),
            ("Gym session", 18, 60, "Komo debug sample"),
            ("Planning tomorrow", 17, 30, "Komo debug sample"),
        ].shuffled()

        return templates.prefix(Int.random(in: 4...6)).enumerated().map { index, template in
            let day = calendar.date(byAdding: .day, value: index, to: Date()) ?? Date()
            let startOfDay = calendar.startOfDay(for: day)
            let start = date(on: startOfDay, hour: template.1, minute: [0, 15, 30, 45].randomElement() ?? 0)
            let end = calendar.date(byAdding: .minute, value: template.2, to: start) ?? start
            let event = EKEvent(eventStore: eventStore)
            event.calendar = targetCalendar
            event.title = template.0
            event.startDate = start
            event.endDate = end
            event.notes = template.3
            event.location = Bool.random() ? ["Home", "Office", "Gym", "Cafe"][Int.random(in: 0...3)] : nil
            return event
        }
    }

    private func saveCalendarEvents(_ events: [EKEvent]) throws -> [String] {
        var ids: [String] = []
        for event in events {
            try eventStore.save(event, span: .thisEvent, commit: false)
            if let id = event.eventIdentifier {
                ids.append(id)
            }
        }
        if !events.isEmpty {
            try eventStore.commit()
        }
        return ids
    }

    private func saveHealthObjectIDs(_ objects: [HKObject]) {
        var stored = loadStoredIDs()
        stored.healthObjectIDsByType = Dictionary(grouping: objects) { object in
            typeKey(for: object)
        }.mapValues { groupedObjects in
            groupedObjects.map { $0.uuid.uuidString }
        }
        saveStoredIDs(stored)
    }

    private func saveCalendarEventIDs(_ ids: [String]) {
        var stored = loadStoredIDs()
        stored.calendarEventIDs = ids
        saveStoredIDs(stored)
    }

    private func debugMetadata() -> [String: Any] {
        [
            Self.metadataMarkerKey: true,
            HKMetadataKeyExternalUUID: UUID().uuidString,
            HKMetadataKeyWasUserEntered: true,
        ]
    }

    private func date(on day: Date, hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func typeKey(for object: HKObject) -> String {
        if object is HKWorkout {
            return Self.workoutTypeKey
        }
        if let sample = object as? HKSample {
            return sample.sampleType.identifier
        }
        return String(describing: type(of: object))
    }

    private func objectType(for key: String) -> HKObjectType? {
        if key == Self.workoutTypeKey {
            return HKObjectType.workoutType()
        }
        if key == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        }
        let identifier = HKQuantityTypeIdentifier(rawValue: key)
        return HKQuantityType.quantityType(forIdentifier: identifier)
    }

    private func loadStoredIDs() -> StoredDebugIDs {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(StoredDebugIDs.self, from: data) else {
            return StoredDebugIDs()
        }
        return stored
    }

    private func saveStoredIDs(_ stored: StoredDebugIDs) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func clearStoredIDs() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

private struct StoredDebugIDs: Codable {
    var healthObjectIDsByType: [String: [String]] = [:]
    var calendarEventIDs: [String] = []
}

// MARK: - DailyProfile

private struct DailyProfile {
    let steps: Double
    let activeCalories: Double
    let restingHeartRate: Double
    let hrv: Double
    let sleepMinutes: Int
    /// Fraction of total sleep that is deep sleep (controls D_deep in score formula).
    let deepSleepFraction: Double
    /// Fraction of total sleep that is REM sleep (controls D_rem in score formula).
    let remSleepFraction: Double
    /// Number of awake interruptions (each costs 4 pts from D_frag = 20).
    let awakePeriods: Int
    /// Hours of the day where HR samples will be clearly above the stress threshold (RHR + 20).
    let stressHours: Set<Int>
    let hasWorkout: Bool
    let workoutMinutes: Double

    // ── Scenario A: poor sleep, 2 stress hours ───────────────────────────────
    // Expected: sleep ~47/100, HRVn=0.60, RHRn=0.41, Stressn=0.25 → E ~15%
    static let badEnergyA = DailyProfile(
        steps: 5_000,
        activeCalories: 250,
        restingHeartRate: 68,
        hrv: 55,
        sleepMinutes: 315,          // 5h 15m total
        deepSleepFraction: 0.111,   // 11.1% → D_deep = 8 (target range: 10–12%)
        remSleepFraction: 0.089,    // 8.9%  → D_rem  = 0 (< 12%)
        awakePeriods: 2,            // D_frag = 12
        stressHours: [9, 10],
        hasWorkout: false,
        workoutMinutes: 0
    )

    // ── Scenario B: mediocre sleep, 1 stress hour ────────────────────────────
    // Expected: sleep ~56/100, HRVn=0.66, RHRn=0.47, Stressn=0.125 → E ~24%
    static let badEnergyB = DailyProfile(
        steps: 6_500,
        activeCalories: 330,
        restingHeartRate: 66,
        hrv: 58,
        sleepMinutes: 360,          // 6h total
        deepSleepFraction: 0.108,   // 10.8% → D_deep = 8 (target range: 10–12%)
        remSleepFraction: 0.080,    // 8.0%  → D_rem  = 0 (< 12%)
        awakePeriods: 1,            // D_frag = 16
        stressHours: [11],
        hasWorkout: false,
        workoutMinutes: 0
    )

    // ── Scenario C: great sleep, no stress, best bio-markers ─────────────────
    // Expected: sleep 100/100, HRVn=0.92, RHRn=0.84, Stressn=0 → E ~77%
    static let goodEnergy = DailyProfile(
        steps: 11_500,
        activeCalories: 585,
        restingHeartRate: 52,
        hrv: 79,
        sleepMinutes: 510,          // 8h 30m total → D_dur = 40
        deepSleepFraction: 0.18,    // 18%  → D_deep = 20 (target range: 13–23%)
        remSleepFraction: 0.22,     // 22%  → D_rem  = 20 (target range: 20–25%)
        awakePeriods: 0,            // D_frag = 20
        stressHours: [],
        hasWorkout: false,
        workoutMinutes: 0
    )
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
