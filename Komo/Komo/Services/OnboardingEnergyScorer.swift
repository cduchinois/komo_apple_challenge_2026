//  OnboardingEnergyScorer.swift
//  Komo
//
//  Rule-based energy scorer for the pre-LLM / pre-HealthKit phase. Reads only
//  the three onboarding answers we already collect:
//    - Q2 "how's your energy right now?"           (energyNow)
//    - the Sleep question                           (sleepAnswer)
//    - Q1 "when do you feel most switched on?"      (energyType, peak window)
//  …plus the current time-of-day, so the score can shift during the day.
//
//  Implements `EnergyDataProviding` so it slots into `AppState.data` behind
//  the same protocol as `MockDataProvider` and, later, a real HealthKit-backed
//  scorer. Non-scoring calls (stats, insight lines, headline insights) delegate
//  to a `fallback` provider so nothing else breaks.
//
//  Determinism rules:
//   1. Base score from Q2:      strong 78 · okay 62 · low 38 · running on fumes 16
//   2. Sleep modifier:          slept great +10 · okay +3 · badly -8 · barely slept -14
//   3. Peak window modifier:    inside chosen window +6 · "changes a lot" 0 · outside -3
//   4. Clamp to 0..100 while preserving the "sum of contributions == percent"
//      invariant for the breakdown sheet.
//
//  TODO: replace with the CoreML + Foundation Models scoring pipeline,
//        same EnergyDataProviding interface, keep `net == percent`.

import Foundation

struct OnboardingEnergyScorer: EnergyDataProviding {
    let energyNow: String?
    let sleepAnswer: String?
    let energyType: String?
    let now: () -> Date
    let fallback: EnergyDataProviding

    init(energyNow: String?,
         sleepAnswer: String?,
         energyType: String?,
         now: @escaping () -> Date = Date.init,
         fallback: EnergyDataProviding) {
        self.energyNow = energyNow
        self.sleepAnswer = sleepAnswer
        self.energyType = energyType
        self.now = now
        self.fallback = fallback
    }

    // MARK: - EnergyDataProviding

    func currentSnapshot() -> EnergySnapshot {
        let (percent, _) = score()
        let level = EnergyLevel.from(percent: percent)
        let base = fallback.currentSnapshot()
        return EnergySnapshot(
            word: level.word,
            percent: percent,
            daysTogether: base.daysTogether,
            rechargedBy: base.rechargedBy,
            usedBy: base.usedBy,
            headlineInsight: base.headlineInsight
        )
    }

    func stats() -> [EnergyStat] { fallback.stats() }

    func insightLines(for tone: CompanionTone) -> [String] {
        fallback.insightLines(for: tone)
    }

    func headlineInsights() -> [String] { fallback.headlineInsights() }

    func energyBreakdown() -> EnergyBreakdown {
        let (percent, contributions) = score()
        let level = EnergyLevel.from(percent: percent)
        return EnergyBreakdown(
            percent: percent,
            word: level.word,
            subtitle: "based on how you feel, your sleep, and your rhythm",
            contributions: contributions
        )
    }

    // MARK: - Scoring

    private func score() -> (percent: Int, contributions: [EnergyContribution]) {
        var contributions: [EnergyContribution] = []
        var running = 0

        // 1. Base — Q2 "how's your energy right now?"
        let base = baseFrom(energyNow)
        if let now = energyNow {
            contributions.append(.init(
                label: "how you feel right now",
                detail: now,
                points: Double(base),
                kind: .recovery
            ))
        } else {
            // No Q2 answer — still surface a neutral base so the sheet isn't empty.
            contributions.append(.init(
                label: "how you feel right now",
                detail: nil,
                points: Double(base),
                kind: .recovery
            ))
        }
        running = base

        // 2. Sleep modifier — clamped so we can't fall past 0 or shoot past 100.
        let sleepModRaw = sleepModFrom(sleepAnswer)
        if sleepModRaw != 0 {
            let mod = clampedMod(sleepModRaw, currentTotal: running)
            if mod != 0 {
                contributions.append(.init(
                    label: "last night's sleep",
                    detail: sleepAnswer,
                    points: Double(mod),
                    kind: mod > 0 ? .recovery : .load
                ))
                running += mod
            }
        }

        // 3. Peak window — inside/outside the user's declared peak.
        let (peakModRaw, windowLabel) = peakModAndWindow()
        if peakModRaw != 0 {
            let mod = clampedMod(peakModRaw, currentTotal: running)
            if mod != 0 {
                if mod > 0 {
                    contributions.append(.init(
                        label: "your peak window",
                        detail: "you're in your \(windowLabel) window",
                        points: Double(mod),
                        kind: .recovery
                    ))
                } else {
                    contributions.append(.init(
                        label: "off-peak hours",
                        detail: "outside your \(windowLabel) window",
                        points: Double(mod),
                        kind: .load
                    ))
                }
                running += mod
            }
        }

        let percent = max(0, min(100, running))
        return (percent, contributions)
    }

    // MARK: - Rule tables

    private func baseFrom(_ q2: String?) -> Int {
        switch q2 {
        case "strong":            return 78
        case "okay":              return 62
        case "low":               return 38
        case "running on fumes":  return 16
        default:                  return 50   // neutral if no answer
        }
    }

    private func sleepModFrom(_ ans: String?) -> Int {
        switch ans {
        case "slept great":  return  10
        case "okay":         return   3
        case "badly":        return  -8
        case "barely slept": return -14
        default:             return   0
        }
    }

    /// Returns the ±modifier and the peak window's display name (either the
    /// user's chosen peak, or the current window when the user said
    /// "changes a lot" / didn't answer).
    private func peakModAndWindow() -> (Int, String) {
        let hour = Calendar.current.component(.hour, from: now())
        let currentWindow = window(for: hour)
        guard let peak = energyType, !peak.isEmpty else { return (0, currentWindow) }
        if peak == "changes a lot" { return (0, currentWindow) }
        if peak == currentWindow { return (6, peak) }
        return (-3, peak)
    }

    private func window(for hour: Int) -> String {
        switch hour {
        case 5..<12:  return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default:      return "late night"
        }
    }

    /// Clamps a proposed modifier so `currentTotal + mod` stays in `0...100`,
    /// preserving the "sum of contributions == percent" invariant.
    private func clampedMod(_ mod: Int, currentTotal: Int) -> Int {
        if mod > 0 { return min(mod, 100 - currentTotal) }
        if mod < 0 { return max(mod, 0 - currentTotal) }
        return 0
    }
}
