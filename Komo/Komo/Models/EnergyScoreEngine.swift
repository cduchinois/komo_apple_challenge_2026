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
// Implements the documented formula:  E = R × exp(−1.5 × L) × 100
//
// References: Algorithm doc (komo_algorithm_doc.md)
//   R  = S × (0.60·HRVn + 0.32·RHRn + 0.08·An) + WorkoutBoost
//   L  = Stressn + Meetingn − 0.4·Stressn·Meetingn + Wn
//   σ(x) = 1/(1 + e^−x)

final class EnergyScoreEngine {

    static let shared = EnergyScoreEngine()
    private init() {}

    // MARK: - Main entry point

    /// Computes the full energy score for a given DayAnalysis.
    /// Returns `isAvailable = false` when there is no sleep data.
    func compute(from analysis: DayAnalysis) -> EnergyScoreResult {
        guard let sleepAssessment = analysis.sleepAssessment else {
            return EnergyScoreResult(score: 0, R: 0, L: 0,
                                     signals: .zero, isAvailable: false)
        }
        let baseline = PersonalBaseline.stored
        let signals  = normalize(analysis: analysis,
                                 sleepScore: sleepAssessment.score,
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

        // Stressn — high-stress hours / 8  (8h = fully stressed day)
        let Stressn = clamp01(Double(analysis.highStressHours) / 8.0)

        // Meetingn — meetings / 8  (8 meetings = maximum cognitive load)
        let Meetingn = clamp01(Double(analysis.totalMeetings) / 8.0)

        // Wn — workout load (unbounded, METs proxy: assume intensity 1.0 for now)
        //       Wn = intenseMinutes/45 × (METs−6)/3 — approximated without METs
        let Wn: Double = analysis.workoutMinutes > 0
            ? analysis.workoutMinutes / 45.0
            : 0.0

        return EnergyScoreSignals(S: S, HRVn: HRVn, RHRn: RHRn, An: An,
                                  Stressn: Stressn, Meetingn: Meetingn, Wn: Wn)
    }

    // MARK: - Core formula   E = R × exp(−1.5 × L) × 100

    func rawScore(signals: EnergyScoreSignals) -> (score: Double, R: Double, L: Double) {
        let modulator     = 0.60 * signals.HRVn + 0.32 * signals.RHRn + 0.08 * signals.An
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

        let score = R * Foundation.exp(-1.5 * L) * 100.0
        return (score, R, L)
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
