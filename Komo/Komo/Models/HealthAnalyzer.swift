import Foundation
import HealthKit

// MARK: - HealthAnalyzer
//
// Converts raw HealthDailySummary samples into the high-level DayAnalysis
// value type that HealthKitDataProvider and KomoPromptBuilder consume.
// Pure computation — no HealthKit/network calls, fully synchronous.

final class HealthAnalyzer {

    static let shared = HealthAnalyzer()
    private init() {}

    // MARK: - Main entry point

    func analyzeDay(summary: HealthDailySummary) -> DayAnalysis {
        let sleepAssessment = analyzeSleep(summary.sleepSamples)

        let daySDNN = summary.hrvSamples.isEmpty ? nil
            : summary.hrvSamples.map(\.ms).reduce(0, +) / Double(summary.hrvSamples.count)

        let (stressTimeline, highStressHours) = analyzeStress(
            hrSamples: summary.heartRateSamples,
            daySDNN:   daySDNN,
            restingHR: summary.restingHR
        )

        let avgHRV = daySDNN ?? 0.0

        return DayAnalysis(
            sleepAssessment:  sleepAssessment,
            restingHeartRate: summary.restingHR,
            averageHRV:       avgHRV,
            stressTimeline:   stressTimeline,
            highStressHours:  highStressHours,
            totalSteps:       summary.steps,
            totalCalories:    summary.activeCalories,
            workoutMinutes:   summary.workoutMinutes,
            totalMeetings:    summary.meetingCount
        )
    }

    // MARK: - Sleep Analysis
    //
    // Implements the documented rule-based formula:
    //   S_score = D_dur + D_deep + D_rem + D_frag  ∈ [0, 100]
    //
    // References: Walker (2017), Tasali et al. (2008), Carskadon & Dement (2005)

    private func analyzeSleep(_ samples: [HKCategorySample]) -> SleepAssessment? {
        guard !samples.isEmpty else { return nil }

        // Filter to actual sleep stages (not "in bed" / awake)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        let awakeValue = HKCategoryValueSleepAnalysis.awake.rawValue

        let asleepSamples = samples.filter { asleepValues.contains($0.value) }
        let awakeSamples  = samples.filter { $0.value == awakeValue }

        guard !asleepSamples.isEmpty else { return nil }

        // Total sleep duration (minutes)
        let totalMin = asleepSamples.reduce(0.0) {
            $0 + $1.endDate.timeIntervalSince($1.startDate) / 60.0
        }
        guard totalMin > 0 else { return nil }

        // Deep + REM percentages
        let deepMin = samples
            .filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60.0 }
        let remMin = samples
            .filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60.0 }

        let deepPct = (deepMin / totalMin) * 100.0
        let remPct  = (remMin  / totalMin) * 100.0

        let data = SleepData(
            totalSleepMinutes: totalMin,
            deepSleepPct: deepPct,
            remSleepPct:  remPct,
            awakeCount:   awakeSamples.count
        )

        // ── Documented formula (no starting baseline) ────────────────────────
        // D_dur  : ≥8h = 40, 7–8h = 38, linear below 7h → max 40
        let hours   = totalMin / 60.0
        let D_dur: Double
        if hours >= 8    { D_dur = 40 }
        else if hours >= 7 { D_dur = 38 }
        else if hours >  0 { D_dur = Swift.max(0, 38 * hours / 7) }
        else               { D_dur = 0 }

        // D_deep : target 13–23% = full 20 pts; 10–12% = partial; else 0
        let D_deep: Double
        if   (13...23).contains(Int(deepPct)) { D_deep = 20 }
        else if deepPct >= 10                  { D_deep = 8  }
        else                                   { D_deep = 0  }

        // D_rem  : target 20–25% = full 20 pts; 12–19% = partial; else 0
        let D_rem: Double
        if   (20...25).contains(Int(remPct))   { D_rem = 20 }
        else if remPct >= 12                   { D_rem = 8  }
        else                                   { D_rem = 0  }

        // D_frag : 0 wakeups = 20 pts; −4 per wakeup; floor 0
        let D_frag = Swift.max(0, 20.0 - Double(awakeSamples.count) * 4.0)

        let score = Swift.min(100, D_dur + D_deep + D_rem + D_frag)
        // ─────────────────────────────────────────────────────────────────────

        return SleepAssessment(data: data, score: score)
    }


    // MARK: - Stress Analysis (CoreML-powered, fallback to HR threshold)
    //
    // Groups HR samples by hour, then classifies each hour via
    // StressClassifierWrapper (CoreML). If the model is unavailable,
    // the wrapper falls back to the original HR-threshold rule.

    private func analyzeStress(
        hrSamples: [HRSample],
        daySDNN:   Double?,
        restingHR: Double?
    ) -> (timeline: [StressHour], highHours: Int) {
        guard !hrSamples.isEmpty else { return ([], 0) }

        let wrapper  = StressClassifierWrapper.shared
        let calendar = Calendar.current

        // Group by hour
        var hourBuckets: [Int: [Double]] = [:]
        for sample in hrSamples {
            let h = calendar.component(.hour, from: sample.date)
            hourBuckets[h, default: []].append(sample.bpm)
        }

        var timeline: [StressHour] = []
        for (hour, bpms) in hourBuckets {
            guard wrapper.isStressedHour(hrSamples: bpms, daySDNN: daySDNN, restingHR: restingHR) else { continue }
            let mean = bpms.reduce(0, +) / Double(bpms.count)
            timeline.append(StressHour(hour: hour, meanHR: mean, hrv: daySDNN ?? 0))
        }

        timeline.sort { $0.hour < $1.hour }
        return (timeline, timeline.count)
    }
}
