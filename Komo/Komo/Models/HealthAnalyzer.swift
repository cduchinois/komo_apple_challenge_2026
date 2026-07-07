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

    func analyzeDay(summary: HealthDailySummary, for date: Date = Date()) -> DayAnalysis {
        let sleepAssessment = analyzeSleep(summary.sleepSamples, wakeDay: date)

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

    private func analyzeSleep(_ samples: [HKCategorySample], wakeDay: Date) -> SleepAssessment? {
        guard !samples.isEmpty else { return nil }

        // Filter to actual sleep stages (not "in bed" / awake)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        let awakeValue = HKCategoryValueSleepAnalysis.awake.rawValue

        let daySamples = samplesForWakeDay(samples, wakeDay: wakeDay)
        let asleepSamples = daySamples.filter { asleepValues.contains($0.value) }
        let awakeSamples  = daySamples.filter { $0.value == awakeValue }

        guard !asleepSamples.isEmpty else { return nil }

        // Merge overlapping intervals so duplicate sources (Watch + phone) are
        // not double-counted — matches Apple Health "time asleep" aggregation.
        let totalMin = mergedAsleepMinutes(from: asleepSamples)
        guard totalMin > 0 else { return nil }

        // Deep + REM percentages (from merged asleep time)
        let deepMin = mergedAsleepMinutes(from: daySamples
            .filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue })
        let remMin = mergedAsleepMinutes(from: daySamples
            .filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue })

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

    /// Keeps samples that belong to the night ending on `wakeDay` (Apple Health
    /// attributes sleep to the day you wake up). If the window filters out every
    /// sample, we fall back to the samples we were given — `HealthKitManager`
    /// already scoped the query to last night, so an empty result here would
    /// throw away real sleep just because of a window edge case.
    private func samplesForWakeDay(_ samples: [HKCategorySample], wakeDay: Date) -> [HKCategorySample] {
        let calendar = Calendar.current
        let startOfWakeDay = calendar.startOfDay(for: wakeDay)
        guard let windowStart = calendar.date(byAdding: .hour, value: -8, to: startOfWakeDay),
              let windowEnd = calendar.date(byAdding: .hour, value: 18, to: startOfWakeDay) else {
            return samples
        }

        let windowed = samples.filter { sample in
            let overlapStart = max(sample.startDate, windowStart)
            let overlapEnd = min(sample.endDate, windowEnd)
            return overlapEnd > overlapStart
        }
        return windowed.isEmpty ? samples : windowed
    }

    /// Union-merge overlapping asleep intervals, then sum duration in minutes.
    private func mergedAsleepMinutes(from samples: [HKCategorySample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let intervals = samples
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }

        var merged: [(Date, Date)] = []
        for interval in intervals {
            if let last = merged.last, interval.0 <= last.1 {
                merged[merged.count - 1] = (last.0, max(last.1, interval.1))
            } else {
                merged.append(interval)
            }
        }

        return merged.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) / 60.0 }
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
