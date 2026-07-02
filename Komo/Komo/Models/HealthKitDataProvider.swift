//  HealthKitDataProvider.swift
//  Komo
//
//  Real-data implementation of EnergyDataProviding backed by HealthKit + CoreML.
//  Drop-in replacement for MockDataProvider — zero view code changes.
//
//  On iOS 26+ the insightLines and headlineInsights methods are enriched by
//  Apple Foundation Models (on-device, private). On older OS they fall back
//  to deterministic rule-based strings derived from the live health snapshot.

import Foundation
import HealthKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - HealthKitDataProvider

final class HealthKitDataProvider: EnergyDataProviding {

    // MARK: Shared singleton
    static let shared = HealthKitDataProvider()

    // MARK: Internal cache — refreshed each time loadTodayIfNeeded() is called
    private var cachedSnapshot: HealthDailySummary?
    private var cachedAnalysis: DayAnalysis?
    private var cachedInsightLines: [String] = []
    private var cachedHeadlineInsights: [String] = []
    private var lastLoadDate: Date?

    // MARK: Sub-engines
    private let hk = HealthKitManager.shared
    private let analyzer = HealthAnalyzer.shared

    private init() {}

    // MARK: - EnergyDataProviding

    func currentSnapshot() -> EnergySnapshot {
        guard let analysis = cachedAnalysis else {
            return .placeholder
        }
        // Use the breakdown as the single source of truth for the percent.
        // EnergyScoreEngine computes E = R × exp(−1.5L) × 100,
        // and buildBreakdown normalizes ΔE values to sum exactly to that percent.
        let breakdown = buildBreakdown(from: analysis)
        let level = EnergyLevel.from(percent: breakdown.percent)

        // Recharged/used text from actual driver rankings
        let engineResult = EnergyScoreEngine.shared.compute(from: analysis)
        let drivers = EnergyScoreEngine.shared.analyzeDrivers(from: engineResult, analysis: analysis)
        let recharged = drivers.filter { $0.kind == .recovery && $0.deltaE > 1 }
                               .sorted { $0.deltaE > $1.deltaE }
                               .prefix(2)
                               .map { $0.label.lowercased() }
                               .joined(separator: " + ")
        let used = drivers.filter { $0.kind == .load && $0.deltaE > 1 }
                          .sorted { $0.deltaE > $1.deltaE }
                          .first?.label.lowercased() ?? ""

        return EnergySnapshot(
            word: level.word,
            percent: breakdown.percent,
            daysTogether: daysTogether(),
            rechargedBy: recharged.isEmpty ? rechargedByString(from: analysis) : recharged,
            usedBy: used.isEmpty ? usedByString(from: analysis) : used,
            headlineInsight: cachedHeadlineInsights.first ?? "Tap the blob to analyze your day."
        )
    }

    func stats() -> [EnergyStat] {
        guard let analysis = cachedAnalysis,
              let summary = cachedSnapshot else {
            return EnergyStat.loadingPlaceholders
        }
        return buildStats(analysis: analysis, summary: summary)
    }

    func insightLines(for tone: CompanionTone) -> [String] {
        if cachedInsightLines.isEmpty {
            return [
                "Tap the blob to load today's energy.",
                "Your data stays private on this device.",
                "Ready when you are."
            ]
        }
        return cachedInsightLines
    }

    func headlineInsights() -> [String] {
        if cachedHeadlineInsights.isEmpty {
            return ["Tap the blob to analyze your day."]
        }
        return cachedHeadlineInsights
    }

    func energyBreakdown() -> EnergyBreakdown {
        guard let analysis = cachedAnalysis else {
            return .placeholder
        }
        return buildBreakdown(from: analysis)
    }

    // MARK: - Public refresh

    /// Call this on app launch and when the user taps the blob.
    /// Safe to call multiple times — caches for the day.
    func loadToday() async {
        do {
            let summary = try await hk.fetchDailySummary(for: Date())
            let analysis = analyzer.analyzeDay(summary: summary)
            cachedSnapshot = summary
            cachedAnalysis = analysis
            lastLoadDate = Date()

            // Fetch 30-day baseline in background so sigmoid uses personal reference
            Task.detached(priority: .background) {
                await HealthKitManager.shared.fetchAndStoreBaseline()
            }

            // Generate AI insight lines (Foundation Models or rule-based fallback)
            let lines = await generateInsightLines(from: analysis)
            cachedInsightLines = lines
            cachedHeadlineInsights = [lines.first ?? ""]
        } catch {
            print("⚠️ HealthKitDataProvider: \(error.localizedDescription)")
        }
    }

    func requestPermissions() async {
        try? await hk.requestAuthorization()
    }

    // MARK: - Personalized Reflections

    /// Returns data-aware reflection cards built from today's analysis.
    /// Falls back to an empty array (AppState will use its static pool).
    func personalizedReflections() -> [Reflection] {
        guard let analysis = cachedAnalysis else { return [] }
        return buildPersonalizedReflections(from: analysis)
    }

    private func buildPersonalizedReflections(from analysis: DayAnalysis) -> [Reflection] {
        var pool: [Reflection] = []

        // — Sleep
        if let sleep = analysis.sleepAssessment {
            let h = sleep.data.totalSleepMinutes / 60.0
            let hStr = String(format: "%.1f", h)
            if h < 5 {
                pool.append(.init(
                    type: .remind,
                    observation: "you only slept \(hStr) hours last night — that's below your recovery threshold.",
                    suggestion: "try to be in bed 45 minutes earlier tonight to recover.",
                    actions: [.remindMe, .save, .next]
                ))
            } else if h < 6.5 {
                pool.append(.init(
                    type: .remind,
                    observation: "you slept \(hStr) hours — a little short for full recovery.",
                    suggestion: "a 15-minute nap this afternoon or an earlier bedtime tonight would help.",
                    actions: [.remindMe, .save, .next]
                ))
            } else if h >= 8 {
                pool.append(.init(
                    type: .reflect,
                    observation: "you slept \(hStr) hours last night — solid recovery.",
                    suggestion: "your body had time to restore. use that clarity for something that matters.",
                    actions: [.save, .writeNote, .next]
                ))
            }
        } else {
            // No sleep data tracked
            pool.append(.init(
                type: .remind,
                observation: "komo couldn't read your sleep data last night.",
                suggestion: "make sure your Apple Watch or iPhone is charging nearby while you sleep.",
                actions: [.remindMe, .next]
            ))
        }

        // — Steps / Movement
        let steps = analysis.totalSteps
        if steps < 2_000 {
            pool.append(.init(
                type: .start,
                observation: "you've only moved \(steps.formatted()) steps so far today.",
                suggestion: "a 10-minute walk right now would reset your body and your focus.",
                actions: [.startNow, .remindMe, .next]
            ))
        } else if steps < 5_000 {
            pool.append(.init(
                type: .remind,
                observation: "\(steps.formatted()) steps so far — you're halfway to your daily goal.",
                suggestion: "try a short walk before your next task to hit 5,000.",
                actions: [.remindMe, .startNow, .next]
            ))
        } else if steps >= 10_000 {
            pool.append(.init(
                type: .reflect,
                observation: "\(steps.formatted()) steps today — you're well above your movement goal.",
                suggestion: "your body is active. let the evening be for recovery, not another workout.",
                actions: [.save, .next]
            ))
        }

        // — HRV
        let hrv = analysis.averageHRV
        if hrv > 0 {
            if hrv < 30 {
                pool.append(.init(
                    type: .reflect,
                    observation: "your HRV is at \(Int(hrv)) ms — lower than your typical baseline.",
                    suggestion: "your nervous system is under load. keep today light and protect sleep tonight.",
                    actions: [.save, .remindMe, .next]
                ))
            } else if hrv > 65 {
                pool.append(.init(
                    type: .start,
                    observation: "your HRV is high at \(Int(hrv)) ms — your body is well recovered.",
                    suggestion: "this is a good window for a workout or deep focus work.",
                    actions: [.startNow, .addToCalendar, .next]
                ))
            }
        }

        // — Resting HR
        if let rhr = analysis.restingHeartRate {
            if rhr > 80 {
                pool.append(.init(
                    type: .reflect,
                    observation: "your resting heart rate is \(Int(rhr)) bpm — elevated for you.",
                    suggestion: "this can signal fatigue or stress. slow the pace today if you can.",
                    actions: [.save, .next]
                ))
            } else if rhr <= 55 {
                pool.append(.init(
                    type: .reflect,
                    observation: "your resting HR is \(Int(rhr)) bpm — strong cardiovascular recovery.",
                    suggestion: "a low resting HR is a good sign. your body is adapting well.",
                    actions: [.save, .next]
                ))
            }
        }

        // — Stress
        if analysis.highStressHours >= 3 {
            pool.append(.init(
                type: .start,
                observation: "your heart rate has been elevated for \(analysis.highStressHours) hours today.",
                suggestion: "take 3 minutes now to breathe. your nervous system will thank you.",
                actions: [.startNow, .done, .next]
            ))
        } else if analysis.highStressHours == 0 {
            pool.append(.init(
                type: .reflect,
                observation: "your stress levels have been low all day.",
                suggestion: "a calm day is a gift. notice what made it easier and try to repeat it.",
                actions: [.writeNote, .save, .next]
            ))
        }

        // — Meetings
        if analysis.totalMeetings >= 5 {
            pool.append(.init(
                type: .add,
                observation: "you have \(analysis.totalMeetings) meetings today — a heavy cognitive load.",
                suggestion: "block a 10-minute gap between your meetings to decompress.",
                actions: [.addToCalendar, .save, .next]
            ))
        } else if analysis.totalMeetings == 0 {
            pool.append(.init(
                type: .start,
                observation: "no meetings on your calendar today — a clear runway.",
                suggestion: "protect the focus time. start with the one thing that matters most.",
                actions: [.startNow, .next]
            ))
        }

        // If pool is too small, return empty → fall back to static pool in AppState
        return pool.count >= 2 ? pool : []
    }

    // MARK: - Build Stats

    private func buildStats(analysis: DayAnalysis, summary: HealthDailySummary) -> [EnergyStat] {
        var stats: [EnergyStat] = []

        // Heart Rate
        if let rhr = analysis.restingHeartRate, rhr > 0 {
            stats.append(.init(
                id: "hr",
                label: "Heart Rate",
                value: "\(Int(rhr))",
                unit: "bpm",
                sub: rhr <= 65 ? "Resting · calm" : "Resting · a little elevated",
                tone: rhr <= 70 ? .good : .warn
            ))
        }

        // Steps
        let steps = analysis.totalSteps
        if steps > 0 {
            let pct = min(100, steps * 100 / 10_000)
            stats.append(.init(
                id: "steps",
                label: "Steps",
                value: steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000) : "\(steps)",
                unit: "",
                sub: "\(pct)% of your goal",
                tone: steps >= 6_000 ? .good : .warn
            ))
        }

        // Sleep
        if let sleep = analysis.sleepAssessment {
            let h = Int(sleep.data.totalSleepMinutes) / 60
            let m = Int(sleep.data.totalSleepMinutes) % 60
            let label = m > 0 ? "\(h)h \(m)m" : "\(h)h"
            stats.append(.init(
                id: "sleep",
                label: "Sleep",
                value: label,
                unit: "",
                sub: "Last night · score \(Int(sleep.score))/100",
                tone: sleep.score >= 65 ? .good : .warn
            ))
        }

        // Stress
        let stressLabel: String
        let stressTone: StatTone
        switch analysis.highStressHours {
        case 0:     stressLabel = "No stress spikes"; stressTone = .good
        case 1:     stressLabel = "Mild tension"; stressTone = .good
        case 2...3: stressLabel = "Moderate load"; stressTone = .warn
        default:    stressLabel = "High stress"; stressTone = .warn
        }
        if !analysis.stressTimeline.isEmpty {
            stats.append(.init(
                id: "stress",
                label: "Stress",
                value: stressTone == .good ? "Low" : "High",
                unit: "",
                sub: stressLabel,
                tone: stressTone
            ))
        }

        // HRV
        let hrv = analysis.averageHRV
        if hrv > 0 {
            stats.append(.init(
                id: "hrv",
                label: "HRV Recovery",
                value: "\(Int(hrv))",
                unit: "ms",
                sub: hrv >= 50 ? "Well recovered" : hrv >= 30 ? "Moderate" : "Low recovery",
                tone: hrv >= 40 ? .good : .warn
            ))
        }

        // Calories
        let cal = analysis.totalCalories
        if cal > 0 {
            stats.append(.init(
                id: "activity",
                label: "Activity",
                value: "\(cal)",
                unit: "cal",
                sub: cal >= 400 ? "Move ring almost closed" : "Keep moving",
                tone: cal >= 300 ? .good : .warn
            ))
        }

        // Meetings (Calendar)
        let meetings = analysis.totalMeetings
        if meetings > 0 {
            stats.append(.init(
                id: "calendar",
                label: "Calendar Load",
                value: "\(meetings)",
                unit: meetings == 1 ? "event" : "events",
                sub: meetings >= 5 ? "Heavy meeting day" : "Manageable load",
                tone: meetings <= 4 ? .good : .warn
            ))
        }

        return stats
    }

    // MARK: - Energy Breakdown
    //
    // Uses EnergyScoreEngine to compute E = R × exp(−1.5L) × 100, then
    // produces individual contribution points by normalizing counterfactual ΔEs:
    //
    //   recoverySum = R × 100   (budget before load)
    //   loadLoss    = R × 100 − E  (how much load reduced the budget)
    //
    // Each ΔE is scaled proportionally so:
    //   sum(recovery_pts) + sum(load_pts) ≈ percent  (net == percent ✓)

    private func buildBreakdown(from analysis: DayAnalysis) -> EnergyBreakdown {
        // 1. Run the documented formula
        let result  = EnergyScoreEngine.shared.compute(from: analysis)
        guard result.isAvailable else { return .placeholder }

        // 2. Counterfactual driver analysis
        let drivers = EnergyScoreEngine.shared.analyzeDrivers(from: result, analysis: analysis)

        // 3. Normalise ΔE values so contributions sum exactly to percent
        let R_pts    = result.R * 100.0         // recovery budget before load
        let loadLoss = R_pts - result.score     // positive: load's damage in score-points

        let recoveryDrivers = drivers.filter { $0.kind == .recovery }
        let loadDrivers     = drivers.filter { $0.kind == .load }

        let rawRecSum = recoveryDrivers.map { max(0, $0.deltaE) }.reduce(0, +)
        let rawLdSum  = loadDrivers.filter { $0.deltaE > 0.5 }.map { $0.deltaE }.reduce(0, +)

        var contributions: [EnergyContribution] = []

        // Recovery contributions (sorted by importance, highest first)
        for d in recoveryDrivers.sorted(by: { $0.deltaE > $1.deltaE }) {
            let pts = rawRecSum > 0 ? (max(0, d.deltaE) / rawRecSum) * R_pts : 0
            contributions.append(.init(label: d.label, detail: d.detail,
                                       points: pts.rounded(), kind: .recovery))
        }

        // Load contributions: only show actual drains (deltaE > 0.5 threshold)
        // Zero-load items (no stress, no meetings, no workout) are omitted —
        // a missing row is cleaner than an invisible bar with "+0".
        for d in loadDrivers.sorted(by: { $0.deltaE > $1.deltaE }) where d.deltaE > 0.5 {
            guard rawLdSum > 0 else { continue }
            let pts = -((d.deltaE / rawLdSum) * loadLoss).rounded()
            contributions.append(.init(label: d.label, detail: d.detail,
                                       points: pts, kind: .load))
        }

        // If NOTHING drew it down today, add a single positive summary row
        // so the "WHAT DREW IT DOWN" section isn't completely empty.
        let hasAnyLoad = loadDrivers.contains { $0.deltaE > 0.5 }
        if !hasAnyLoad {
            contributions.append(.init(
                label: "No significant load",
                detail: "calm day — stress, calendar & workout all low",
                points: 0,
                kind: .load
            ))
        }

        let percent = Int(result.score.rounded())
        let word    = EnergyLevel.from(percent: percent).word
        return EnergyBreakdown(percent: percent, word: word, contributions: contributions)
    }


    // MARK: - AI Insight Lines (Foundation Models or rule-based)

    private func generateInsightLines(from analysis: DayAnalysis) async -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if let lines = await generateWithAI(analysis: analysis) {
                return lines
            }
        }
        #endif
        return ruleBasedInsightLines(from: analysis)
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private func generateWithAI(analysis: DayAnalysis) async -> [String]? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let builder = KomoPromptBuilder(analysis: analysis)
        do {
            let session = LanguageModelSession(instructions: builder.buildSystemPrompt())
            let response = try await session.respond(to: builder.buildInsightsUserMessage())
            let lines = response.content
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count > 8 }
            return lines.isEmpty ? nil : Array(lines.prefix(5))
        } catch {
            print("⚠️ Foundation Models: \(error)")
            return nil
        }
    }
    #endif

    private func ruleBasedInsightLines(from analysis: DayAnalysis) -> [String] {
        var lines: [String] = []

        if let sleep = analysis.sleepAssessment {
            let h = sleep.data.totalSleepMinutes / 60.0
            if h >= 7.5 && sleep.score >= 75 {
                lines.append("You slept \(String(format: "%.1f", h)) hours last night — your body had time to recover.")
            } else if h < 6 {
                lines.append("Only \(String(format: "%.1f", h)) hours of sleep. A short nap this afternoon could help.")
            } else {
                lines.append("\(String(format: "%.1f", h)) hours of sleep — decent, but your deep sleep was \(Int(sleep.data.deepSleepPct))%.")
            }
        }

        if analysis.highStressHours >= 3 {
            lines.append("Your system logged \(analysis.highStressHours) hours of high stress — a breath break would help right now.")
        } else if analysis.highStressHours == 0 && !analysis.stressTimeline.isEmpty {
            lines.append("Low stress all day. That's rare — notice how it feels.")
        } else if let peak = analysis.peakStressHour {
            lines.append("Stress peaked around \(peak.hour):00, HR at \(Int(peak.meanHR)) bpm.")
        }

        let steps = analysis.totalSteps
        if steps >= 10_000 {
            lines.append("\(steps) steps today — one of your stronger days for movement.")
        } else if steps > 0 {
            let pct = steps * 100 / 10_000
            lines.append("At \(steps) steps you're \(pct)% of the way to your goal.")
        }

        if lines.isEmpty {
            lines.append("Tap the blob to load today's energy data.")
        }

        return lines
    }

    // MARK: - Helpers

    private func rechargedByString(from analysis: DayAnalysis) -> String {
        var parts: [String] = []
        if let sleep = analysis.sleepAssessment, sleep.score >= 65 { parts.append("sleep") }
        if analysis.totalSteps >= 6_000 { parts.append("movement") }
        if analysis.averageHRV >= 45    { parts.append("HRV recovery") }
        return parts.isEmpty ? "rest" : parts.joined(separator: " + ")
    }

    private func usedByString(from analysis: DayAnalysis) -> String {
        var parts: [String] = []
        if analysis.highStressHours >= 2 { parts.append("stress") }
        if analysis.totalMeetings >= 4   { parts.append("meetings") }
        if let sleep = analysis.sleepAssessment, sleep.data.totalSleepMinutes < 360 { parts.append("poor sleep") }
        return parts.isEmpty ? "normal activity" : parts.joined(separator: " + ")
    }

    private func daysTogether() -> Int {
        // TODO: persist first-launch date via UserDefaults
        return UserDefaults.standard.integer(forKey: "komo_days_together").clamped(to: 1...999)
    }
}

// MARK: - Int clamped helper
private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

// MARK: - Placeholder extensions (shown before HealthKit data loads)

private extension EnergySnapshot {
    static let placeholder = EnergySnapshot(
        word: "Loading…",
        percent: 50,
        daysTogether: 1,
        rechargedBy: "—",
        usedBy: "—",
        headlineInsight: "Tap the blob to start your first check-in."
    )
}

private extension EnergyBreakdown {
    static let placeholder = EnergyBreakdown(
        percent: 50,
        word: "Loading",
        contributions: []
    )
}

private extension EnergyStat {
    static let loadingPlaceholders: [EnergyStat] = [
        .init(id: "hr",    label: "Heart Rate", value: "—", unit: "bpm", sub: "Loading…", tone: .good),
        .init(id: "steps", label: "Steps",      value: "—", unit: "",    sub: "Loading…", tone: .good),
        .init(id: "sleep", label: "Sleep",      value: "—", unit: "",    sub: "Loading…", tone: .good),
    ]
}
