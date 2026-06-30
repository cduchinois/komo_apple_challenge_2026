import Foundation
import HealthKit

// MARK: - Raw Health Data Structures

/// A single heart rate sample with its timestamp.
struct HeartRateSample {
    let bpm: Double
    let date: Date
}

/// A single HRV measurement with its timestamp.
struct HRVSample {
    let sdnn: Double  // milliseconds
    let date: Date
}

/// Aggregated health data for a 1-hour time window.
/// Used as input for the stress classifier's FeatureEngine.
struct HourlyHealthData {
    let hour: Int         // 0–23
    let date: Date
    let heartRateSamples: [HeartRateSample]
    let hrvSamples: [HRVSample]
    let stepCount: Double
    let isWorkout: Bool
    let meetingCount: Int

    /// True if there's enough data to extract meaningful features.
    var hasEnoughData: Bool {
        heartRateSamples.count >= 3
    }
}

/// Sleep data collected overnight. Maps 1:1 to SleepQualityScorer model inputs.
struct SleepData {
    let totalSleepMinutes: Double
    let deepSleepPct: Double       // fraction (0.21 = 21%)
    let remSleepPct: Double        // fraction (0.24 = 24%)
    let awakeCount: Int            // nombre d'épisodes de réveil fusionnés
    let awakeMinutes: Double       // durée totale éveillé pendant la nuit (min)
    let sleepOnsetLatencyMin: Double
    let restingHRDuringSleep: Double
    let respiratoryRate: Double
    let bloodOxygenAvg: Double
    let bedtimeConsistencyMin: Double  // Std dev of bedtimes over past 7 days

    /// Feature vector matching the SleepQualityScorer CoreML model input order.
    var featureVector: [Double] {
        [
            totalSleepMinutes,
            deepSleepPct,
            remSleepPct,
            Double(awakeCount),
            sleepOnsetLatencyMin,
            restingHRDuringSleep,
            respiratoryRate,
            bloodOxygenAvg,
            bedtimeConsistencyMin,
        ]
    }
}

/// Complete health summary for an entire day.
struct DailyHealthSummary {
    let date: Date
    let hourlyData: [HourlyHealthData]
    let sleepData: SleepData?
    let totalSteps: Int
    let totalCalories: Int
    let totalMeetings: Int
    let workoutMinutes: Double
    let restingHeartRate: Double?
    let screenTimeMinutes: Int
    let averageMETs: Double          // Intensité physique moyenne (iOS 17+ / Apple Watch)

    var containsRealHealthSignals: Bool {
        sleepData != nil ||
        totalSteps > 0 ||
        totalCalories > 0 ||
        workoutMinutes > 0 ||
        restingHeartRate != nil ||
        hourlyData.contains { !$0.heartRateSamples.isEmpty || !$0.hrvSamples.isEmpty || $0.stepCount > 0 }
    }
}

// MARK: - ML Model Output Structures

/// Stress level classification for a single time window.
struct StressReading {
    let hour: Int
    let level: StressLevel
    let confidence: Double
    let meanHR: Double
    let hrvSDNN: Double?
}

enum StressLevel: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

/// Sleep quality assessment from the SleepQualityScorer model.
struct SleepAssessment {
    let score: Double        // 0–100
    let category: SleepCategory
    let data: SleepData
}

enum SleepCategory: String, CaseIterable {
    case poor = "Poor"
    case fair = "Fair"
    case good = "Good"
    case excellent = "Excellent"

    init(score: Double) {
        switch score {
        case ..<40: self = .poor
        case ..<60: self = .fair
        case ..<80: self = .good
        default:    self = .excellent
        }
    }
}

/// Anomaly detected by the AnomalyDetector model.
struct HealthAnomaly {
    let hour: Int
    let description: String
    let metric: String       // e.g. "heart_rate", "hrv"
    let value: Double
    let expectedRange: ClosedRange<Double>?
}

// MARK: - Day Analysis (Combined Output)

/// Complete analysis output for one day — fed to Foundation Models for insight generation.
struct DayAnalysis {
    let date: Date
    let stressTimeline: [StressReading]
    let sleepAssessment: SleepAssessment?
    let anomalies: [HealthAnomaly]
    let totalSteps: Int
    let totalCalories: Int
    let totalMeetings: Int
    let workoutMinutes: Double
    let restingHeartRate: Double?
    let screenTimeMinutes: Int
    let averageMETs: Double          // METs moyens du jour — proxy d'intensité direct

    /// Peak stress hour (if any).
    var peakStressHour: StressReading? {
        stressTimeline
            .filter { $0.level == .high }
            .max(by: { $0.meanHR < $1.meanHR })
    }

    /// Average stress across the day.
    var averageStressLevel: StressLevel {
        let scores = stressTimeline.map { reading -> Double in
            switch reading.level {
            case .low: return 0
            case .medium: return 1
            case .high: return 2
            }
        }
        guard !scores.isEmpty else { return .low }
        let avg = scores.reduce(0, +) / Double(scores.count)
        if avg < 0.5 { return .low }
        if avg < 1.5 { return .medium }
        return .high
    }

    /// Number of high-stress hours.
    var highStressHours: Int {
        stressTimeline.filter { $0.level == .high }.count
    }

    /// Average HRV (SDNN) across the day.
    var averageHRV: Double {
        let hrvs = stressTimeline.compactMap { $0.hrvSDNN }
        guard !hrvs.isEmpty else { return 0.0 }
        return hrvs.reduce(0.0, +) / Double(hrvs.count)
    }
}

// MARK: - Calendar Event

/// Simplified calendar event for meeting load analysis.
struct CalendarEvent {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    var durationMinutes: Double {
        endDate.timeIntervalSince(startDate) / 60.0
    }
}
