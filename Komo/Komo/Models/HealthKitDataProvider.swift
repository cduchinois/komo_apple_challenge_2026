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
    private var cachedDailyInsight: KomoGeneratedInsight?
    private var lastLoadDate: Date?

    private let insightGenerator = KomoInsightGenerator()

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
            headlineInsight: cachedDailyInsight?.observation
                ?? cachedHeadlineInsights.first
                ?? HealthKitL10n.tapBlobAnalyze
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
                HealthKitL10n.tapBlobLoad,
                HealthKitL10n.dataStaysPrivate,
                HealthKitL10n.readyWhenYouAre,
            ]
        }
        return cachedInsightLines
    }

    func headlineInsights() -> [String] {
        if cachedHeadlineInsights.isEmpty {
            return [HealthKitL10n.tapBlobAnalyze]
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

    /// True after a successful loadToday() — used by AppState to decide
    /// whether to switch the active data provider to this one.
    var hasData: Bool { cachedAnalysis != nil }

    /// Requests HealthKit read authorization. Idempotent: the system only
    /// surfaces the permission sheet the first time — subsequent calls resolve
    /// immediately. Safe to call before every load so returning users (who may
    /// not have granted during onboarding) still get their data read.
    func requestPermissions() async {
        try? await hk.requestHealthAuthorization()
    }

    /// Call this on app launch and when the user taps the blob.
    /// Safe to call multiple times — caches for the day.
    func loadToday() async {
        // Ensure we hold read authorization before querying. Without this,
        // HealthKit silently returns empty results for unauthorized types,
        // which surfaces as "no data" everywhere (0% energy, no sleep, etc.).
        await requestPermissions()
        do {
            let summary = try await hk.fetchDailySummary(for: Date())
            let analysis = analyzer.analyzeDay(summary: summary, for: Date())
            cachedSnapshot = summary
            cachedAnalysis = analysis
            lastLoadDate = Date()

            // Fetch 30-day baseline in background so sigmoid uses personal reference
            Task.detached(priority: .background) {
                await HealthKitManager.shared.fetchAndStoreBaseline()
            }

            // AI insight card + companion lines (Foundation Models or rule-based fallback)
            cachedDailyInsight = await insightGenerator.generateDailyInsight(for: analysis)
            let aiLines = await insightGenerator.generateCompanionLines(for: analysis)
            let lines = aiLines.isEmpty
                ? await generateInsightLines(from: analysis)
                : aiLines
            cachedInsightLines = lines
            if let daily = cachedDailyInsight {
                cachedHeadlineInsights = [daily.observation]
            } else {
                cachedHeadlineInsights = [lines.first ?? ""]
            }
        } catch {
            print("⚠️ HealthKitDataProvider: \(error.localizedDescription)")
        }
    }

    // MARK: - Personalized Reflections

    /// Returns data-aware reflection cards built from today's analysis.
    /// Falls back to an empty array (AppState will use its static pool).
    func personalizedReflections() -> [Reflection] {
        guard cachedAnalysis != nil else { return [] }
        var pool: [Reflection] = []

        if let daily = cachedDailyInsight {
            pool.append(daily.asReflection())
        }

        if let analysis = cachedAnalysis {
            let dataCards = buildPersonalizedReflections(from: analysis)
            // Avoid near-duplicate cards if rule-based echoes the AI card.
            for card in dataCards where !pool.contains(where: { $0.observation == card.observation }) {
                pool.append(card)
            }
        }

        return pool
    }

    private func buildPersonalizedReflections(from analysis: DayAnalysis) -> [Reflection] {
        var pool: [Reflection] = []

        if let sleep = analysis.sleepAssessment {
            let h = sleep.data.totalSleepMinutes / 60.0
            let hStr = String(format: "%.1f", h)
            if h < 5 {
                pool.append(.init(
                    type: .remind,
                    observation: HealthKitL10n.sleepBelowThreshold(hours: hStr),
                    suggestion: HealthKitL10n.sleepShortSuggestion,
                    actions: [.remindMe, .save, .next]
                ))
            } else if h < 6.5 {
                pool.append(.init(
                    type: .remind,
                    observation: HealthKitL10n.sleepShort(hours: hStr),
                    suggestion: HealthKitL10n.sleepMediumSuggestion,
                    actions: [.remindMe, .save, .next]
                ))
            } else if h >= 8 {
                pool.append(.init(
                    type: .reflect,
                    observation: HealthKitL10n.sleepSolid(hours: hStr),
                    suggestion: HealthKitL10n.sleepSolidSuggestion,
                    actions: [.save, .writeNote, .next]
                ))
            }
        } else {
            pool.append(.init(
                type: .remind,
                observation: HealthKitL10n.sleepNoDataObservation,
                suggestion: HealthKitL10n.sleepNoDataSuggestion,
                actions: [.remindMe, .next]
            ))
        }

        let steps = analysis.totalSteps
        if steps < 2_000 {
            pool.append(.init(
                type: .start,
                observation: HealthKitL10n.stepsLow(steps.formatted()),
                suggestion: HealthKitL10n.stepsLowSuggestion,
                actions: [.startNow, .remindMe, .next]
            ))
        } else if steps < 5_000 {
            pool.append(.init(
                type: .remind,
                observation: HealthKitL10n.stepsMid(steps.formatted()),
                suggestion: HealthKitL10n.stepsMidSuggestion,
                actions: [.remindMe, .startNow, .next]
            ))
        } else if steps >= 10_000 {
            pool.append(.init(
                type: .reflect,
                observation: HealthKitL10n.stepsHigh(steps.formatted()),
                suggestion: HealthKitL10n.stepsHighSuggestion,
                actions: [.save, .next]
            ))
        }

        let hrv = analysis.averageHRV
        if hrv > 0 {
            if hrv < 30 {
                pool.append(.init(
                    type: .reflect,
                    observation: HealthKitL10n.hrvLow(Int(hrv)),
                    suggestion: HealthKitL10n.hrvLowSuggestion,
                    actions: [.save, .remindMe, .next]
                ))
            } else if hrv > 65 {
                pool.append(.init(
                    type: .start,
                    observation: HealthKitL10n.hrvHigh(Int(hrv)),
                    suggestion: HealthKitL10n.hrvHighSuggestion,
                    actions: [.startNow, .addToCalendar, .next]
                ))
            }
        }

        if let rhr = analysis.restingHeartRate {
            if rhr > 80 {
                pool.append(.init(
                    type: .reflect,
                    observation: HealthKitL10n.rhrElevated(Int(rhr)),
                    suggestion: HealthKitL10n.rhrElevatedSuggestion,
                    actions: [.save, .next]
                ))
            } else if rhr <= 55 {
                pool.append(.init(
                    type: .reflect,
                    observation: HealthKitL10n.rhrStrong(Int(rhr)),
                    suggestion: HealthKitL10n.rhrStrongSuggestion,
                    actions: [.save, .next]
                ))
            }
        }

        if analysis.highStressHours >= 3 {
            pool.append(.init(
                type: .start,
                observation: HealthKitL10n.stressHigh(hours: analysis.highStressHours),
                suggestion: HealthKitL10n.stressHighSuggestion,
                actions: [.startNow, .done, .next]
            ))
        } else if analysis.highStressHours == 0 {
            pool.append(.init(
                type: .reflect,
                observation: HealthKitL10n.stressLowObservation,
                suggestion: HealthKitL10n.stressLowSuggestion,
                actions: [.writeNote, .save, .next]
            ))
        }

        if analysis.totalMeetings >= 5 {
            pool.append(.init(
                type: .add,
                observation: HealthKitL10n.meetingsHeavy(analysis.totalMeetings),
                suggestion: HealthKitL10n.meetingsHeavySuggestion,
                actions: [.addToCalendar, .save, .next]
            ))
        } else if analysis.totalMeetings == 0 {
            pool.append(.init(
                type: .start,
                observation: HealthKitL10n.meetingsClearObservation,
                suggestion: HealthKitL10n.meetingsClearSuggestion,
                actions: [.startNow, .next]
            ))
        }

        return pool
    }

    // MARK: - Build Stats

    private func buildStats(analysis: DayAnalysis, summary: HealthDailySummary) -> [EnergyStat] {
        var stats: [EnergyStat] = []

        // Heart Rate
        if let rhr = analysis.restingHeartRate, rhr > 0 {
            stats.append(.init(
                id: "hr",
                label: HealthKitL10n.statHeartRate,
                value: "\(Int(rhr))",
                unit: HealthKitL10n.unitBPM,
                sub: rhr <= 65 ? HealthKitL10n.restingCalm : HealthKitL10n.restingElevated,
                tone: rhr <= 70 ? .good : .warn
            ))
        }

        let steps = analysis.totalSteps
        if steps > 0 {
            let pct = min(100, steps * 100 / 10_000)
            stats.append(.init(
                id: "steps",
                label: HealthKitL10n.statSteps,
                value: steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000) : "\(steps)",
                unit: "",
                sub: HealthKitL10n.stepsGoalPercent(pct),
                tone: steps >= 6_000 ? .good : .warn
            ))
        }

        if let sleep = analysis.sleepAssessment {
            let h = Int(sleep.data.totalSleepMinutes) / 60
            let m = Int(sleep.data.totalSleepMinutes) % 60
            let label = m > 0 ? "\(h)h \(m)m" : "\(h)h"
            stats.append(.init(
                id: "sleep",
                label: HealthKitL10n.statSleep,
                value: label,
                unit: "",
                sub: HealthKitL10n.sleepScoreSub(score: Int(sleep.score)),
                tone: sleep.score >= 65 ? .good : .warn
            ))
        }

        let stressLabel: String
        let stressTone: StatTone
        switch analysis.highStressHours {
        case 0:     stressLabel = HealthKitL10n.stressNone; stressTone = .good
        case 1:     stressLabel = HealthKitL10n.stressMild; stressTone = .good
        case 2...3: stressLabel = HealthKitL10n.stressModerate; stressTone = .warn
        default:    stressLabel = HealthKitL10n.stressHighLabel; stressTone = .warn
        }
        if !analysis.stressTimeline.isEmpty {
            stats.append(.init(
                id: "stress",
                label: HealthKitL10n.statStress,
                value: stressTone == .good ? HealthKitL10n.stressValueLow : HealthKitL10n.stressValueHigh,
                unit: "",
                sub: stressLabel,
                tone: stressTone
            ))
        }

        let hrv = analysis.averageHRV
        if hrv > 0 {
            stats.append(.init(
                id: "hrv",
                label: HealthKitL10n.statHRV,
                value: "\(Int(hrv))",
                unit: "ms",
                sub: hrv >= 50 ? HealthKitL10n.hrvWellRecovered : hrv >= 30 ? HealthKitL10n.hrvModerate : HealthKitL10n.hrvLowRecovery,
                tone: hrv >= 40 ? .good : .warn
            ))
        }

        let cal = analysis.totalCalories
        if cal > 0 {
            stats.append(.init(
                id: "activity",
                label: HealthKitL10n.statActivity,
                value: "\(cal)",
                unit: HealthKitL10n.unitCal,
                sub: cal >= 400 ? HealthKitL10n.activityRingAlmost : HealthKitL10n.activityKeepMoving,
                tone: cal >= 300 ? .good : .warn
            ))
        }

        let meetings = analysis.totalMeetings
        if meetings > 0 {
            stats.append(.init(
                id: "calendar",
                label: HealthKitL10n.statCalendar,
                value: "\(meetings)",
                unit: HealthKitL10n.calendarEventUnit(meetings),
                sub: meetings >= 5 ? HealthKitL10n.calendarHeavy : HealthKitL10n.calendarManageable,
                tone: meetings <= 4 ? .good : .warn
            ))
        }

        return stats
    }

    // MARK: - Energy Breakdown
    //
    // Delegates to EnergyScoreEngine.buildUserFacingBreakdown — see that type for
    // the scoring rubric (actual contributions, not counterfactual headroom).

    private func buildBreakdown(from analysis: DayAnalysis) -> EnergyBreakdown {
        EnergyScoreEngine.shared.buildUserFacingBreakdown(
            from: analysis,
            subtitle: HealthKitL10n.breakdownSubtitle
        ) ?? .placeholder
    }


    // MARK: - AI Insight Lines (Foundation Models or rule-based)

    private func generateInsightLines(from analysis: DayAnalysis) async -> [String] {
        if let daily = cachedDailyInsight {
            return [daily.observation]
        }
        return ruleBasedInsightLines(from: analysis)
    }

    private func ruleBasedInsightLines(from analysis: DayAnalysis) -> [String] {
        var lines: [String] = []

        if let sleep = analysis.sleepAssessment {
            let h = sleep.data.totalSleepMinutes / 60.0
            let hStr = String(format: "%.1f", h)
            if h >= 7.5 && sleep.score >= 75 {
                lines.append(HealthKitL10n.insightSleepRecovered(hours: hStr))
            } else if h < 6 {
                lines.append(HealthKitL10n.insightSleepShort(hours: hStr))
            } else {
                lines.append(HealthKitL10n.insightSleepDeep(hours: hStr, deepPct: Int(sleep.data.deepSleepPct)))
            }
        }

        if analysis.highStressHours >= 3 {
            lines.append(HealthKitL10n.insightStressLogged(hours: analysis.highStressHours))
        } else if analysis.highStressHours == 0 && !analysis.stressTimeline.isEmpty {
            lines.append(HealthKitL10n.insightStressLow)
        } else if let peak = analysis.peakStressHour {
            lines.append(HealthKitL10n.insightStressPeak(hour: peak.hour, bpm: Int(peak.meanHR)))
        }

        let steps = analysis.totalSteps
        if steps >= 10_000 {
            lines.append(HealthKitL10n.insightStepsStrong(steps))
        } else if steps > 0 {
            let pct = steps * 100 / 10_000
            lines.append(HealthKitL10n.insightStepsProgress(steps: steps, pct: pct))
        }

        if lines.isEmpty {
            lines.append(HealthKitL10n.insightTapBlob)
        }

        return lines
    }

    // MARK: - Helpers

    private func rechargedByString(from analysis: DayAnalysis) -> String {
        var parts: [String] = []
        if let sleep = analysis.sleepAssessment, sleep.score >= 65 { parts.append(HealthKitL10n.partSleep) }
        if analysis.totalSteps >= 6_000 { parts.append(HealthKitL10n.partMovement) }
        if analysis.averageHRV >= 45    { parts.append(HealthKitL10n.partHRV) }
        return parts.isEmpty ? HealthKitL10n.partRest : parts.joined(separator: " + ")
    }

    private func usedByString(from analysis: DayAnalysis) -> String {
        var parts: [String] = []
        if analysis.highStressHours >= 2 { parts.append(HealthKitL10n.partStress) }
        if analysis.totalMeetings >= 4   { parts.append(HealthKitL10n.partMeetings) }
        if let sleep = analysis.sleepAssessment, sleep.data.totalSleepMinutes < 360 { parts.append(HealthKitL10n.partPoorSleep) }
        return parts.isEmpty ? HealthKitL10n.partNormalActivity : parts.joined(separator: " + ")
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
        word: HealthKitL10n.loading,
        percent: 50,
        daysTogether: 1,
        rechargedBy: "—",
        usedBy: "—",
        headlineInsight: HealthKitL10n.tapBlobStartCheckIn
    )
}

private extension EnergyBreakdown {
    static let placeholder = EnergyBreakdown(
        percent: 50,
        word: HealthKitL10n.loading,
        subtitle: "",
        contributions: []
    )
}

private extension EnergyStat {
    static let loadingPlaceholders: [EnergyStat] = [
        .init(id: "hr",    label: HealthKitL10n.statHeartRate, value: "—", unit: HealthKitL10n.unitBPM, sub: HealthKitL10n.loading, tone: .good),
        .init(id: "steps", label: HealthKitL10n.statSteps,      value: "—", unit: "",    sub: HealthKitL10n.loading, tone: .good),
        .init(id: "sleep", label: HealthKitL10n.statSleep,      value: "—", unit: "",    sub: HealthKitL10n.loading, tone: .good),
    ]
}
