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

@MainActor
final class DebugTestDataInjector {
    static let shared = DebugTestDataInjector()

    private static let storageKey = "komo.debug.injectedDataIDs.v1"
    private static let metadataMarkerKey = "komo.debug.injected"
    private static let workoutTypeKey = "HKWorkoutType"

    private let healthStore = HKHealthStore()
    private let eventStore = EKEventStore()
    private let calendar = Calendar.current
    private let defaults = UserDefaults.standard

    private init() {}

    func resetAndInject() async throws -> DebugTestDataInjectionResult {
        try await requestPermissions()

        let deletedCounts = try await deletePreviousInjectedData()
        let healthObjects = try makeHealthObjects()
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

    private func makeHealthObjects() throws -> [HKObject] {
        var objects: [HKObject] = []
        let today = Date()
        let bpmUnit = HKUnit(from: "count/min")
        let msUnit = HKUnit.secondUnit(with: .milli)

        for dayOffset in stride(from: 6, through: 0, by: -1) {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) ?? today
            let startOfDay = calendar.startOfDay(for: day)
            let activeStart = date(on: startOfDay, hour: 7, minute: Int.random(in: 0...30))
            let activeEnd = date(on: startOfDay, hour: 22, minute: Int.random(in: 0...20))
            let profile = DailyProfile.random()

            objects.append(try quantitySample(.stepCount, unit: .count(), value: profile.steps, start: activeStart, end: activeEnd))
            objects.append(try quantitySample(.activeEnergyBurned, unit: .kilocalorie(), value: profile.activeCalories, start: activeStart, end: activeEnd))
            objects.append(try quantitySample(.restingHeartRate, unit: bpmUnit, value: profile.restingHeartRate, start: date(on: startOfDay, hour: 6, minute: 40), end: date(on: startOfDay, hour: 6, minute: 45)))
            objects.append(try quantitySample(.heartRateVariabilitySDNN, unit: msUnit, value: profile.hrv, start: date(on: startOfDay, hour: 6, minute: 46), end: date(on: startOfDay, hour: 6, minute: 47)))

            for hour in stride(from: 8, through: 21, by: 2) {
                let start = date(on: startOfDay, hour: hour, minute: Int.random(in: 0...45))
                let end = calendar.date(byAdding: .minute, value: 1, to: start) ?? start
                let workdayLift = (10...16).contains(hour) ? Double.random(in: 4...22) : Double.random(in: -4...8)
                let bpm = (profile.restingHeartRate + 12 + workdayLift).clamped(to: 58...138)
                objects.append(try quantitySample(.heartRate, unit: bpmUnit, value: bpm, start: start, end: end))
            }

            objects.append(contentsOf: try sleepSamples(for: startOfDay, profile: profile))

            if dayOffset % 2 == 0 || Bool.random() {
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
        let sleepStart = date(on: previousDay, hour: 23, minute: Int.random(in: 0...35))
        let totalMinutes = profile.sleepMinutes
        let awakeMinutes = Int.random(in: 4...24)
        let deepMinutes = Int(Double(totalMinutes) * Double.random(in: 0.12...0.22))
        let remMinutes = Int(Double(totalMinutes) * Double.random(in: 0.18...0.28))
        let coreMinutes = max(60, totalMinutes - awakeMinutes - deepMinutes - remMinutes)

        let segments: [(Int, HKCategoryValueSleepAnalysis)] = [
            (coreMinutes / 2, .asleepCore),
            (deepMinutes, .asleepDeep),
            (awakeMinutes, .awake),
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
        let activities: [HKWorkoutActivityType] = [.walking, .running, .traditionalStrengthTraining, .cycling]
        let durationMinutes = Double.random(in: 22...58)
        let start = date(on: startOfDay, hour: Int.random(in: 7...19), minute: Int.random(in: 0...45))
        let end = calendar.date(byAdding: .minute, value: Int(durationMinutes), to: start) ?? start
        let activity = activities.randomElement() ?? .walking
        let energy = HKQuantity(unit: .kilocalorie(), doubleValue: min(profile.activeCalories * 0.55, Double.random(in: 110...430)))
        let distance: HKQuantity? = activity == .traditionalStrengthTraining ? nil : HKQuantity(unit: .meter(), doubleValue: Double.random(in: 1800...8500))

        return HKWorkout(
            activityType: activity,
            start: start,
            end: end,
            duration: durationMinutes * 60,
            totalEnergyBurned: energy,
            totalDistance: distance,
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

private struct DailyProfile {
    let steps: Double
    let activeCalories: Double
    let restingHeartRate: Double
    let hrv: Double
    let sleepMinutes: Int

    static func random() -> DailyProfile {
        DailyProfile(
            steps: Double(Int.random(in: 2_400...14_500)),
            activeCalories: Double(Int.random(in: 150...920)),
            restingHeartRate: Double.random(in: 52...78),
            hrv: Double.random(in: 24...92),
            sleepMinutes: Int.random(in: 330...535)
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
