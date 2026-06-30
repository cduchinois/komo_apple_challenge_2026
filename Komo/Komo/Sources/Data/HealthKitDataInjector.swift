import Foundation
import HealthKit

// MARK: - HealthKitDataInjector

/// Writes realistic test data directly into HealthKit on the current iPhone.
/// Use for testing WITHOUT an Apple Watch.
///
/// ⚠️ Requires NSHealthUpdateUsageDescription in Info.plist
/// ⚠️ User must grant WRITE access to HR, HRV, Steps, Sleep
@MainActor
final class HealthKitDataInjector {

    static let shared = HealthKitDataInjector()
    private let store = HKHealthStore()
    private init() {}

    // MARK: - Write Types

    private var writeTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate, .heartRateVariabilitySDNN,
            .stepCount, .restingHeartRate, .activeEnergyBurned
        ]
        for id in identifiers {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    // MARK: - Request Write Permission

    func requestWriteAuthorization() async throws {
        try await store.requestAuthorization(toShare: writeTypes, read: writeTypes)
        print("✅ HealthKit write access granted")
    }

    // MARK: - Inject Full Day

    /// Injects a realistic hackathon workday into HealthKit.
    /// Stress peak at 15h, slight sleep deficit, 5 meetings.
    func injectRealisticDay() async throws {
        try await requestWriteAuthorization()

        let calendar = Calendar.current
        let today = Date()
        let startOfDay = calendar.startOfDay(for: today)

        print("💉 Injecting test data into HealthKit...")

        // 1. Heart Rate samples (24h pattern)
        try await injectHeartRate(startOfDay: startOfDay)

        // 2. HRV samples
        try await injectHRV(startOfDay: startOfDay)

        // 3. Steps
        try await injectSteps(startOfDay: startOfDay)

        // 4. Resting Heart Rate
        try await injectRestingHR(date: today, bpm: 58)

        // 5. Sleep (last night)
        try await injectSleep(startOfDay: startOfDay)

        print("✅ Test data injected — tap the avatar to see real CoreML analysis!")
    }

    // MARK: - HR injection

    private func injectHeartRate(startOfDay: Date) async throws {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())

        // Realistic HR profile: low at night, peak at 15h
        let hourlyHR: [(hour: Int, bpm: Double)] = [
            (0,55),(1,52),(2,50),(3,51),(4,53),(5,55),
            (6,68),(7,75),(8,76),(9,80),(10,77),
            (11,82),(12,74),(13,78),(14,85),
            (15,108), // stress peak
            (16,90),(17,78),(18,85),(19,72),(20,68),(21,65),(22,62),(23,58)
        ]

        var samples: [HKQuantitySample] = []
        let calendar = Calendar.current

        for entry in hourlyHR {
            guard let hourStart = calendar.date(byAdding: .hour, value: entry.hour, to: startOfDay) else { continue }
            // 4 samples per hour
            for i in 0..<4 {
                let date = hourStart.addingTimeInterval(Double(i) * 900)
                let noise = Double.random(in: -5...5)
                let quantity = HKQuantity(unit: unit, doubleValue: max(45, entry.bpm + noise))
                samples.append(HKQuantitySample(type: hrType, quantity: quantity, start: date, end: date))
            }
        }

        try await store.save(samples)
        print("   ✅ \(samples.count) HR samples saved")
    }

    // MARK: - HRV injection

    private func injectHRV(startOfDay: Date) async throws {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        let unit = HKUnit.secondUnit(with: .milli)
        let calendar = Calendar.current

        let hourlyHRV: [(hour: Int, sdnn: Double)] = [
            (1,68),(3,72),(5,65),(8,42),(11,38),(14,35),(15,22),(18,48),(21,55),(23,60)
        ]

        var samples: [HKQuantitySample] = []
        for entry in hourlyHRV {
            guard let date = calendar.date(byAdding: .hour, value: entry.hour, to: startOfDay) else { continue }
            let quantity = HKQuantity(unit: unit, doubleValue: entry.sdnn)
            samples.append(HKQuantitySample(type: hrvType, quantity: quantity, start: date, end: date))
        }

        try await store.save(samples)
        print("   ✅ \(samples.count) HRV samples saved")
    }

    // MARK: - Steps injection

    private func injectSteps(startOfDay: Date) async throws {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let unit = HKUnit.count()
        let calendar = Calendar.current

        let hourlySteps: [(hour: Int, steps: Double)] = [
            (7,850),(8,600),(9,200),(10,150),(11,300),(12,1200),
            (13,200),(14,100),(17,900),(18,1200),(19,400),(20,200)
        ]

        var samples: [HKQuantitySample] = []
        for entry in hourlySteps {
            guard let start = calendar.date(byAdding: .hour, value: entry.hour, to: startOfDay),
                  let end = calendar.date(byAdding: .hour, value: entry.hour + 1, to: startOfDay) else { continue }
            let quantity = HKQuantity(unit: unit, doubleValue: entry.steps)
            samples.append(HKQuantitySample(type: stepType, quantity: quantity, start: start, end: end))
        }

        try await store.save(samples)
        print("   ✅ \(samples.count) step samples saved")
    }

    // MARK: - Resting HR

    private func injectRestingHR(date: Date, bpm: Double) async throws {
        guard let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let quantity = HKQuantity(unit: unit, doubleValue: bpm)
        let sample = HKQuantitySample(type: rhrType, quantity: quantity, start: date, end: date)
        try await store.save(sample)
        print("   ✅ Resting HR (\(Int(bpm)) BPM) saved")
    }

    // MARK: - Sleep injection

    private func injectSleep(startOfDay: Date) async throws {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let calendar = Calendar.current

        // Last night: 00:30 → 06:45 (6h15)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay),
              let bedtime = calendar.date(byAdding: .minute, value: 30, to: yesterday),
              let _ = calendar.date(byAdding: .minute, value: 405, to: startOfDay) else { return }

        let stages: [(start: TimeInterval, duration: TimeInterval, value: Int)] = [
            // REM, Core, Deep, Core cycles
            (0,    60*30,  HKCategoryValueSleepAnalysis.asleepREM.rawValue),
            (60*30,  60*90,  HKCategoryValueSleepAnalysis.asleepCore.rawValue),
            (60*120, 60*60,  HKCategoryValueSleepAnalysis.asleepDeep.rawValue),
            (60*180, 60*90,  HKCategoryValueSleepAnalysis.asleepREM.rawValue),
            (60*270, 60*105, HKCategoryValueSleepAnalysis.asleepCore.rawValue),
        ]

        var samples: [HKCategorySample] = []
        for stage in stages {
            let start = bedtime.addingTimeInterval(stage.start)
            let end = start.addingTimeInterval(stage.duration)
            let sample = HKCategorySample(type: sleepType, value: stage.value, start: start, end: end)
            samples.append(sample)
        }

        try await store.save(samples)
        print("   ✅ Sleep stages saved (6h15, \(samples.count) segments)")
    }
}
