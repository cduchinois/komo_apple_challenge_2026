import Foundation

// MARK: - EnergyScoreSignals
// 7 normalized signals [0,1] feeding the energy formula.
// Wn (workout load) is unbounded in the formula but capped at 1 for UI bars.

struct EnergyScoreSignals {
    var S: Double         // Sleep score / 100  [0,1]
    var HRVn: Double      // HRV via sigmoid     [0,1]
    var RHRn: Double      // RHR via sigmoid, inverted [0,1]
    var An: Double        // Light activity      [0,1]
    var Stressn: Double   // Hourly stress load  [0,1]
    var Meetingn: Double  // Calendar load       [0,1]
    var Wn: Double        // Workout load        ≥0 (unbounded)

    static let zero = EnergyScoreSignals(S: 0, HRVn: 0.5, RHRn: 0.5,
                                         An: 0, Stressn: 0, Meetingn: 0, Wn: 0)
}

// MARK: - EnergyScoreResult

struct EnergyScoreResult {
    let score: Double          // 0–100 (clamped)
    let R: Double              // Recovery [0,1]
    let L: Double              // Load (unbounded ≥0)
    let signals: EnergyScoreSignals
    let isAvailable: Bool      // false when sleepAssessment is nil
}

// MARK: - EnergyDriver
// One factor produced by counterfactual analysis.

struct EnergyDriver {
    let label: String
    let detail: String
    let normalizedValue: Double   // [0,1] (Wn capped for UI bars)
    let deltaE: Double            // counterfactual gain if set to ideal value
    let kind: Kind

    enum Kind { case recovery, load }
}

// MARK: - PersonalBaseline
// 30-day rolling average stored in UserDefaults.
// Used for personalised HRVn / RHRn sigmoid instead of population median.

struct PersonalBaseline {
    let HRVavg: Double    // 30-day mean HRV SDNN (ms)
    let RHRavg: Double    // 30-day mean resting HR (bpm)

    // Returns nil when no baseline has been stored yet.
    static var stored: PersonalBaseline? {
        let hrv = UserDefaults.standard.double(forKey: "komo_baseline_hrv")
        let rhr = UserDefaults.standard.double(forKey: "komo_baseline_rhr")
        guard hrv > 1, rhr > 1 else { return nil }
        return PersonalBaseline(HRVavg: hrv, RHRavg: rhr)
    }

    func save() {
        UserDefaults.standard.set(HRVavg, forKey: "komo_baseline_hrv")
        UserDefaults.standard.set(RHRavg, forKey: "komo_baseline_rhr")
    }
}

// MARK: - EnergyScoreEngine
//
// Implements the documented formula:  E = R × exp(−1.0 × L) × 100
//
// References: Algorithm doc (komo_algorithm_doc.md)
//   R  = S × (0.53·HRVn + 0.32·RHRn + 0.15·An) + WorkoutBoost
//   L  = Stressn + Meetingn − 0.4·Stressn·Meetingn + Wn
//   σ(x) = 1/(1 + e^−x)

final class EnergyScoreEngine {

    static let shared = EnergyScoreEngine()
    private init() {}

    // MARK: - Main entry point

    /// Neutral sleep proxy used when the night wasn't tracked, so the score can
    /// still reflect HRV / RHR / steps instead of collapsing to zero.
    private static let neutralSleepScore: Double = 60.0

    /// Computes the full energy score for a given DayAnalysis.
    /// Returns `isAvailable = false` only when there is NO usable signal at all
    /// (no sleep, no HRV, no RHR, no steps, no calories, no workout, no meetings).
    /// When sleep is missing but other signals exist, a neutral sleep proxy keeps
    /// the score meaningful rather than zeroing everything out.
    func compute(from analysis: DayAnalysis) -> EnergyScoreResult {
        let hasSleep = analysis.sleepAssessment != nil
        let hasAnySignal = hasSleep
            || analysis.averageHRV > 0
            || (analysis.restingHeartRate ?? 0) > 0
            || analysis.totalSteps > 0
            || analysis.totalCalories > 0
            || analysis.workoutMinutes > 0
            || analysis.totalMeetings > 0
            || !analysis.stressTimeline.isEmpty

        guard hasAnySignal else {
            return EnergyScoreResult(score: 0, R: 0, L: 0,
                                     signals: .zero, isAvailable: false)
        }

        let sleepScore = analysis.sleepAssessment?.score ?? Self.neutralSleepScore
        let baseline = PersonalBaseline.stored
        let signals  = normalize(analysis: analysis,
                                 sleepScore: sleepScore,
                                 baseline: baseline)
        let (score, R, L) = rawScore(signals: signals)
        return EnergyScoreResult(
            score:       Swift.min(100, Swift.max(0, score)),
            R:           R,
            L:           L,
            signals:     signals,
            isAvailable: true
        )
    }

    // MARK: - Signal normalisation  [0, 1]

    func normalize(analysis: DayAnalysis,
                   sleepScore: Double,
                   baseline: PersonalBaseline?) -> EnergyScoreSignals {

        // S — sleep score directly
        let S = sleepScore / 100.0

        // HRVn — sigmoid around personal baseline or population median (50 ms)
        let HRVn: Double
        if analysis.averageHRV > 0 {
            if let bl = baseline, bl.HRVavg > 1 {
                HRVn = sigmoid(12.0 * (analysis.averageHRV / bl.HRVavg - 1.0))
            } else {
                HRVn = sigmoid((analysis.averageHRV - 50.0) / 12.0)
            }
        } else {
            HRVn = 0.5   // neutral when no HRV data
        }

        // RHRn — inverted sigmoid (lower RHR = better recovery)
        let RHRn: Double
        if let rhr = analysis.restingHeartRate, rhr > 0 {
            if let bl = baseline, bl.RHRavg > 1 {
                RHRn = sigmoid(12.0 * (bl.RHRavg - rhr) / bl.RHRavg)
            } else {
                // Population: 65 bpm → neutral (σ = 0.5)
                RHRn = sigmoid((65.0 - rhr) / 8.0)
            }
        } else {
            RHRn = 0.5   // neutral when no RHR data
        }

        // An — light activity:  0.80 × (steps/7500) + 0.20 × (lightWorkoutMin/30)
        // workoutMinutes used as light workout proxy (no METs available yet)
        let An = clamp01(0.80 * Double(analysis.totalSteps) / 7500.0
                       + 0.20 * analysis.workoutMinutes / 30.0)

        // Stressn — high-stress hours / 10  (10h = very heavy day)
        let Stressn = clamp01(Double(analysis.highStressHours) / 10.0)

        // Meetingn — meetings / 10  (10 meetings = very heavy day)
        let Meetingn = clamp01(Double(analysis.totalMeetings) / 10.0)

        // Wn — workout load. Denominator 90 min = 1 unit (not 45) so a standard
        // gym session contributes ~0.5 instead of 1.0. Capped at 0.55 so even
        // a 2-hour workout doesn't collapse the score to near zero.
        let Wn: Double = analysis.workoutMinutes > 0
            ? Swift.min(analysis.workoutMinutes / 90.0, 0.55)
            : 0.0

        return EnergyScoreSignals(S: S, HRVn: HRVn, RHRn: RHRn, An: An,
                                  Stressn: Stressn, Meetingn: Meetingn, Wn: Wn)
    }

    // MARK: - Core formula   E = R × exp(−0.65 × L) × 100

    private static let loadDecay: Double = 0.65
    private static let recoveryWeights = (sleep: 40.0, body: 25.0, heart: 20.0, move: 15.0)

    func rawScore(signals: EnergyScoreSignals) -> (score: Double, R: Double, L: Double) {
        // HRV: 0.53, RHR: 0.32, Activity: 0.15  (sums to 1.00)
        // Activity weight raised from 0.08 so steps contribute visibly to recovery.
        let modulator     = 0.53 * signals.HRVn + 0.32 * signals.RHRn + 0.15 * signals.An
        let readinessBase = signals.S * modulator

        // WorkoutBoost: only fires when readiness is already high (> 0.5).
        // Adds up to +15% of S — capped at S so sleep remains the ceiling.
        let workoutBoost: Double
        if signals.Wn > 0, readinessBase > 0.5 {
            workoutBoost = (readinessBase - 0.4) * 0.15
        } else {
            workoutBoost = 0.0
        }
        let R = Swift.min(signals.S, readinessBase + signals.S * workoutBoost)

        // Load: stress + meetings with −0.4·Sn·Mn interaction damper + workout load
        let interaction = 0.4 * signals.Stressn * signals.Meetingn
        let L = Swift.max(0, signals.Stressn + signals.Meetingn - interaction + signals.Wn)

        // Softer load curve: great recovery days can still reach ~90–100 when load is low.
        let score = R * Foundation.exp(-Self.loadDecay * L) * 100.0
        return (score, R, L)
    }

    // MARK: - User-facing breakdown
    //
    // Shows what each signal ACTUALLY contributed today (not counterfactual headroom).
    // Recovery rows sum to R×100; load rows sum to −(R×100 − E). Net equals E.

    func buildUserFacingBreakdown(from analysis: DayAnalysis,
                                  subtitle: String) -> EnergyBreakdown? {
        let result = compute(from: analysis)
        guard result.isAvailable else { return nil }

        let sig = result.signals
        let Rpts = result.R * 100.0
        let loadLoss = Rpts - result.score
        let w = Self.recoveryWeights

        // When the night wasn't tracked we don't fabricate a "Sleep" row — the
        // score still uses a neutral sleep proxy, but the breakdown only lists
        // the signals we actually measured (HRV / heart / movement).
        var rawRecovery: [(label: String, detail: String, raw: Double)] = []
        if analysis.sleepAssessment != nil {
            rawRecovery.append(
                (HealthKitL10n.breakdownSleep, sleepDetail(analysis), sig.S * w.sleep))
        }
        rawRecovery.append(contentsOf: [
            (HealthKitL10n.breakdownRecovery, bodyRecoveryDetail(analysis, signal: sig.HRVn),
             sig.S * sig.HRVn * w.body),
            (HealthKitL10n.breakdownHeart, heartDetail(analysis, signal: sig.RHRn),
             sig.S * sig.RHRn * w.heart),
            (HealthKitL10n.breakdownMovement, movementDetail(analysis),
             sig.S * sig.An * w.move),
        ])

        let rawRecSum = rawRecovery.map(\.raw).reduce(0, +)
        let recScale = rawRecSum > 0 ? Rpts / rawRecSum : 0
        var contributions: [EnergyContribution] = rawRecovery
            .sorted { $0.raw > $1.raw }
            .map { item in
                EnergyContribution(
                    label: item.label,
                    detail: item.detail,
                    points: (item.raw * recScale).rounded(),
                    kind: .recovery
                )
            }

        contributions = fixRoundedSum(contributions, targetTotal: Rpts)

        if loadLoss > 0.5 {
            var loadParts: [(label: String, detail: String, weight: Double)] = []
            if sig.Stressn > 0.01 {
                loadParts.append((HealthKitL10n.breakdownStress, stressDetail(analysis), sig.Stressn))
            }
            if sig.Meetingn > 0.01 {
                loadParts.append((HealthKitL10n.breakdownCalendar, calendarDetail(analysis), sig.Meetingn))
            }
            if sig.Wn > 0.01 {
                loadParts.append((HealthKitL10n.breakdownWorkoutLoad, workoutDetail(analysis), sig.Wn))
            }

            let weightSum = loadParts.map(\.weight).reduce(0, +)
            if weightSum > 0 {
                var loadRows: [EnergyContribution] = loadParts
                    .sorted { $0.weight > $1.weight }
                    .map { part in
                        EnergyContribution(
                            label: part.label,
                            detail: part.detail,
                            points: -((part.weight / weightSum) * loadLoss).rounded(),
                            kind: .load
                        )
                    }
                loadRows = fixRoundedSum(loadRows, targetTotal: -loadLoss)
                contributions.append(contentsOf: loadRows)
            }
        } else {
            contributions.append(EnergyContribution(
                label: HealthKitL10n.noSignificantLoad,
                detail: HealthKitL10n.calmDayDetail,
                points: 0,
                kind: .load
            ))
        }

        let percent = Int(result.score.rounded())
        let reconciled = fixRoundedSum(contributions, targetTotal: Double(percent))
        return EnergyBreakdown(
            percent: percent,
            word: EnergyLevel.from(percent: percent).word,
            subtitle: subtitle,
            contributions: reconciled
        )
    }

    private func sleepDetail(_ analysis: DayAnalysis) -> String {
        guard let sleep = analysis.sleepAssessment else { return HealthKitL10n.breakdownNoData }
        let h = String(format: "%.1f", sleep.data.totalSleepMinutes / 60.0)
        return HealthKitL10n.breakdownSleepDetail(hours: h, score: Int(sleep.score))
    }

    private func bodyRecoveryDetail(_ analysis: DayAnalysis, signal: Double) -> String {
        if analysis.averageHRV <= 0 { return HealthKitL10n.breakdownNoData }
        return HealthKitL10n.breakdownRecoveryLevel(level: recoveryLevel(signal))
    }

    private func heartDetail(_ analysis: DayAnalysis, signal: Double) -> String {
        guard analysis.restingHeartRate != nil else { return HealthKitL10n.breakdownNoData }
        return HealthKitL10n.breakdownHeartLevel(level: recoveryLevel(signal))
    }

    private func movementDetail(_ analysis: DayAnalysis) -> String {
        HealthKitL10n.breakdownSteps(analysis.totalSteps)
    }

    private func stressDetail(_ analysis: DayAnalysis) -> String {
        analysis.highStressHours > 0
            ? HealthKitL10n.breakdownStressHours(analysis.highStressHours)
            : HealthKitL10n.breakdownCalmDay
    }

    private func calendarDetail(_ analysis: DayAnalysis) -> String {
        analysis.totalMeetings > 0
            ? HealthKitL10n.breakdownMeetings(analysis.totalMeetings)
            : HealthKitL10n.breakdownNoMeetings
    }

    private func workoutDetail(_ analysis: DayAnalysis) -> String {
        HealthKitL10n.breakdownWorkoutMinutes(Int(analysis.workoutMinutes))
    }

    private func recoveryLevel(_ signal: Double) -> Int {
        switch signal {
        case 0.75...: return 3
        case 0.45..<0.75: return 2
        default: return 1
        }
    }

    private func fixRoundedSum(_ rows: [EnergyContribution],
                               targetTotal: Double) -> [EnergyContribution] {
        guard !rows.isEmpty else { return rows }
        let target = Int(targetTotal.rounded())
        var ints = rows.map { Int($0.points.rounded()) }
        var delta = target - ints.reduce(0, +)
        guard delta != 0 else { return rows }

        let order = rows.indices.sorted {
            abs(rows[$0].points) > abs(rows[$1].points)
        }
        var i = 0
        while delta != 0, i < order.count * 4 {
            let idx = order[i % order.count]
            ints[idx] += delta > 0 ? 1 : -1
            delta += delta > 0 ? -1 : 1
            i += 1
        }

        return zip(rows, ints).map { row, pts in
            EnergyContribution(label: row.label, detail: row.detail, points: Double(pts), kind: row.kind)
        }
    }

    // MARK: - Counterfactual driver analysis
    //
    // For each signal f, we compute:   ΔE_f = E(f → ideal) − E_actual
    // Ideal = 1.0 for recovery signals, 0.0 for load signals.
    // The driver with the largest |ΔE| is the biggest lever to improve energy.

    func analyzeDrivers(from result: EnergyScoreResult,
                        analysis: DayAnalysis) -> [EnergyDriver] {
        guard result.isAvailable else { return [] }

        let sig   = result.signals
        let E_act = result.score
        var drivers: [EnergyDriver] = []

        // --- Recovery drivers (ideal = 1.0) ---

        let sleepH = analysis.sleepAssessment
            .map { $0.data.totalSleepMinutes / 60.0 } ?? 0
        let sleepDetail = String(format: "%.1fh, score %d/100",
                                 sleepH,
                                 Int(analysis.sleepAssessment?.score ?? 0))
        drivers.append(recoveryDriver(label: "Sleep", detail: sleepDetail,
                                      signals: sig, actualScore: E_act, keyPath: \.S))

        let hrvDetail = analysis.averageHRV > 0
            ? String(format: "%.0f ms SDNN", analysis.averageHRV)
            : "no data"
        drivers.append(recoveryDriver(label: "HRV", detail: hrvDetail,
                                      signals: sig, actualScore: E_act, keyPath: \.HRVn))

        let rhrDetail = analysis.restingHeartRate
            .map { "\(Int($0)) bpm" } ?? "no data"
        drivers.append(recoveryDriver(label: "Resting HR", detail: rhrDetail,
                                      signals: sig, actualScore: E_act, keyPath: \.RHRn))

        let actDetail = "\(analysis.totalSteps.formatted()) steps"
        drivers.append(recoveryDriver(label: "Movement", detail: actDetail,
                                      signals: sig, actualScore: E_act, keyPath: \.An))

        // --- Load drivers (ideal = 0.0) ---

        let stressDetail = analysis.highStressHours > 0
            ? "\(analysis.highStressHours)h elevated HR"
            : "calm all day"
        drivers.append(loadDriver(label: "Stress", detail: stressDetail,
                                  signals: sig, actualScore: E_act, keyPath: \.Stressn))

        let meet = analysis.totalMeetings
        let meetDetail = meet > 0 ? "\(meet) meeting\(meet == 1 ? "" : "s")" : "no meetings"
        drivers.append(loadDriver(label: "Calendar", detail: meetDetail,
                                  signals: sig, actualScore: E_act, keyPath: \.Meetingn))

        if sig.Wn > 0 {
            let wrkDetail = String(format: "%.0f min", analysis.workoutMinutes)
            drivers.append(loadDriver(label: "Workout", detail: wrkDetail,
                                      signals: sig, actualScore: E_act, keyPath: \.Wn))
        }

        return drivers
    }

    // MARK: - Private counterfactual helpers

    private func recoveryDriver(label: String, detail: String,
                                signals: EnergyScoreSignals, actualScore: Double,
                                keyPath: WritableKeyPath<EnergyScoreSignals, Double>) -> EnergyDriver {
        var ideal = signals
        ideal[keyPath: keyPath] = 1.0
        let (idealScore, _, _) = rawScore(signals: ideal)
        return EnergyDriver(label: label, detail: detail,
                            normalizedValue: signals[keyPath: keyPath],
                            deltaE: idealScore - actualScore,
                            kind: .recovery)
    }

    private func loadDriver(label: String, detail: String,
                            signals: EnergyScoreSignals, actualScore: Double,
                            keyPath: WritableKeyPath<EnergyScoreSignals, Double>) -> EnergyDriver {
        var ideal = signals
        ideal[keyPath: keyPath] = 0.0
        let (idealScore, _, _) = rawScore(signals: ideal)
        return EnergyDriver(label: label, detail: detail,
                            normalizedValue: Swift.min(1.0, signals[keyPath: keyPath]),
                            deltaE: idealScore - actualScore,   // positive = reducing load improves score
                            kind: .load)
    }

    // MARK: - Math utilities

    func sigmoid(_ x: Double) -> Double {
        1.0 / (1.0 + Foundation.exp(-Swift.max(-500, Swift.min(500, x))))
    }

    func clamp01(_ x: Double) -> Double { Swift.max(0, Swift.min(1, x)) }
}
