import Foundation
import HealthKit

// MARK: - DayAnalysis
// Intermediate value type produced by HealthAnalyzer from raw HealthKit samples.
// It's the single truth that feeds HealthKitDataProvider, KomoPromptBuilder,
// and MoodLabel. All numeric types use Double for easy arithmetic.

struct SleepData {
    var totalSleepMinutes: Double   // total time asleep (all stages)
    var deepSleepPct: Double        // % of sleep in HKCategoryValueSleepAnalysis.asleepDeep
    var remSleepPct: Double         // % of sleep in HKCategoryValueSleepAnalysis.asleepREM
    var awakeCount: Int             // wake-up events during the night
}

struct SleepAssessment {
    var data: SleepData
    var score: Double   // 0–100 composite
}

struct StressHour {
    var hour: Int       // 0–23
    var meanHR: Double  // mean heart rate for that hour
    var hrv: Double     // mean SDNN for that hour (0 if unavailable)
}

struct DayAnalysis {
    // Sleep (nil if no sample available)
    var sleepAssessment: SleepAssessment?

    // Heart metrics
    var restingHeartRate: Double?   // bpm (nil if no resting HR sample)
    var averageHRV: Double          // SDNN ms; 0 if unavailable

    // Stress timeline (one entry per hour with elevated HR)
    var stressTimeline: [StressHour]
    var highStressHours: Int        // count of hours where HR > personal threshold

    // Peak stress hour (highest meanHR in stressTimeline, nil if empty)
    var peakStressHour: StressHour? {
        stressTimeline.max(by: { $0.meanHR < $1.meanHR })
    }

    // Activity
    var totalSteps: Int
    var totalCalories: Int          // active energy (kcal)
    var workoutMinutes: Double      // total workout duration

    // Calendar load (injected from EventKit via HealthKitManager)
    var totalMeetings: Int
}

// MARK: - Lightweight sample types (used by HealthKitManager → HealthAnalyzer)

struct HRSample {
    let date: Date
    let bpm: Double
}

struct HRVSample {
    let date: Date
    let ms: Double
}

// MARK: - HealthDailySummary (raw, pre-analysis HealthKit data)

struct HealthDailySummary {
    var steps: Int
    var activeCalories: Int
    var heartRateSamples: [HRSample]
    var hrvSamples: [HRVSample]
    var restingHR: Double?
    var sleepSamples: [HKCategorySample]
    var workoutMinutes: Double
    var meetingCount: Int
}
