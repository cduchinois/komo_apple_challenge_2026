import Foundation

// MARK: - FeatureEngine

/// Transforms raw HealthKit data into the exact feature vectors expected by CoreML models.
struct FeatureEngine {

    // MARK: - Stress Features (20 features)

    /// Computes the 20 features expected by the StressClassifier model.
    ///
    /// Feature order:
    /// ```
    /// mean_hr, std_hr, max_hr, min_hr,
    /// mean_ibi, sdnn, rmssd, pnn50, ibi_range,
    /// eda_mean, eda_std, eda_max, eda_min, eda_range, eda_slope,
    /// temp_mean, temp_std, temp_slope,
    /// acc_magnitude_mean, acc_magnitude_std
    /// ```
    ///
    /// - Note: Apple Watch lacks EDA and skin temperature sensors.
    ///   EDA features default to 0.0; temperature defaults to physiological baselines.
    ///   Accelerometer features are estimated from step count.
    ///
    /// - Parameter hourlyData: The hourly health data snapshot.
    /// - Returns: A dictionary of feature name → value, or `nil` if fewer than 3 HR samples.
    static func stressFeatures(from hourlyData: HourlyHealthData) -> [String: Double]? {
        let bpmValues = hourlyData.heartRateSamples.map(\.bpm)

        // Require at least 3 HR samples for meaningful stats
        guard bpmValues.count >= 3 else { return nil }

        // -- Heart Rate features --
        let meanHR = bpmValues.mean
        let stdHR = bpmValues.std(ddof: 1)
        let maxHR = bpmValues.max()!
        let minHR = bpmValues.min()!

        // -- IBI features (approximate from BPM) --
        let ibiValues = bpmValues.map { 60_000.0 / $0 }
        let meanIBI = ibiValues.mean
        let sdnn = ibiValues.std(ddof: 1)

        // RMSSD: sqrt(mean(diff(ibi)^2))
        let diffs = zip(ibiValues.dropFirst(), ibiValues).map { $0 - $1 }
        let squaredDiffs = diffs.map { $0 * $0 }
        let rmssd = sqrt(squaredDiffs.mean)

        // pNN50: percentage of successive IBI differences > 50ms
        let pnn50Count = diffs.filter { abs($0) > 50.0 }.count
        let pnn50 = diffs.isEmpty ? 0.0 : Double(pnn50Count) / Double(diffs.count) * 100.0

        let ibiRange = ibiValues.max()! - ibiValues.min()!

        // -- EDA features (unavailable on Apple Watch → neutral defaults) --
        let edaMean = 0.0
        let edaStd = 0.0
        let edaMax = 0.0
        let edaMin = 0.0
        let edaRange = 0.0
        let edaSlope = 0.0

        // -- Temperature features (unavailable → physiological baseline) --
        let tempMean = 33.0
        let tempStd = 0.0
        let tempSlope = 0.0

        // -- Accelerometer features (estimated from step count) --
        // Higher steps in an hour implies more motion
        let stepsPerHour = hourlyData.stepCount
        let accMagnitudeMean = estimateAccMagnitude(from: stepsPerHour)
        let accMagnitudeStd = accMagnitudeMean * 0.3 // approximate variability

        return [
            "mean_hr": meanHR,
            "std_hr": stdHR,
            "max_hr": maxHR,
            "min_hr": minHR,
            "mean_ibi": meanIBI,
            "sdnn": sdnn,
            "rmssd": rmssd,
            "pnn50": pnn50,
            "ibi_range": ibiRange,
            "eda_mean": edaMean,
            "eda_std": edaStd,
            "eda_max": edaMax,
            "eda_min": edaMin,
            "eda_range": edaRange,
            "eda_slope": edaSlope,
            "temp_mean": tempMean,
            "temp_std": tempStd,
            "temp_slope": tempSlope,
            "acc_magnitude_mean": accMagnitudeMean,
            "acc_magnitude_std": accMagnitudeStd,
        ]
    }

    // MARK: - Stress Feature Scaling

    /// Applies StandardScaler normalization: `(value - mean) / scale` using parameters
    /// from `StressClassifier_scaler.json`.
    ///
    /// - Parameters:
    ///   - features: The raw feature dictionary from `stressFeatures(from:)`.
    ///   - scalerJSON: Parsed JSON dictionary containing `"mean"` and `"scale"` arrays,
    ///     both ordered to match the canonical feature order.
    /// - Returns: A scaled feature vector in the canonical order.
    static func scaleStressFeatures(_ features: [String: Double], scalerJSON: [String: Any]) -> [Double] {
        let featureOrder = [
            "mean_hr", "std_hr", "max_hr", "min_hr",
            "mean_ibi", "sdnn", "rmssd", "pnn50", "ibi_range",
            "eda_mean", "eda_std", "eda_max", "eda_min", "eda_range", "eda_slope",
            "temp_mean", "temp_std", "temp_slope",
            "acc_magnitude_mean", "acc_magnitude_std",
        ]

        let means = scalerJSON["mean"] as? [Double] ?? Array(repeating: 0.0, count: featureOrder.count)
        let scales = scalerJSON["scale"] as? [Double] ?? Array(repeating: 1.0, count: featureOrder.count)

        return featureOrder.enumerated().map { index, name in
            let value = features[name] ?? 0.0
            let mean = index < means.count ? means[index] : 0.0
            let scale = index < scales.count ? scales[index] : 1.0
            return scale != 0.0 ? (value - mean) / scale : 0.0
        }
    }

    // MARK: - Sleep Features (9 features)

    /// Returns the pre-computed sleep feature vector from `SleepData`.
    ///
    /// Feature order:
    /// ```
    /// total_sleep_minutes, deep_sleep_pct, rem_sleep_pct, awake_count,
    /// sleep_onset_latency_min, resting_hr_sleep, respiratory_rate,
    /// blood_oxygen_avg, bedtime_consistency_min
    /// ```
    ///
    /// - Parameter sleepData: The sleep data containing a pre-computed feature vector.
    /// - Returns: The feature vector as `[Double]`.
    static func sleepFeatures(from sleepData: SleepData) -> [Double] {
        return sleepData.featureVector
    }

    // MARK: - Anomaly Features (7 features)

    /// Computes the 7 features for the AnomalyDetector model.
    ///
    /// Feature order:
    /// ```
    /// mean_hr, max_hr, hr_std, hrv_sdnn, step_count, is_active, hour_of_day
    /// ```
    ///
    /// - Parameter hourlyData: The hourly health data snapshot.
    /// - Returns: A feature vector of 7 doubles, or `nil` if not enough HR data.
    static func anomalyFeatures(from hourlyData: HourlyHealthData) -> [Double]? {
        let bpmValues = hourlyData.heartRateSamples.map(\.bpm)

        // Require at least 2 HR samples
        guard bpmValues.count >= 2 else { return nil }

        let meanHR = bpmValues.mean
        let maxHR = bpmValues.max()!
        let hrStd = bpmValues.std(ddof: 1)

        // HRV SDNN: prefer actual HRV samples, fall back to estimation from HR
        let hrvSDNN: Double
        if !hourlyData.hrvSamples.isEmpty {
            hrvSDNN = hourlyData.hrvSamples.map(\.sdnn).mean
        } else {
            // Estimate SDNN from IBI derived from BPM
            let ibiValues = bpmValues.map { 60_000.0 / $0 }
            hrvSDNN = ibiValues.std(ddof: 1)
        }

        let stepCount = hourlyData.stepCount
        let isActive: Double = (stepCount > 200 || hourlyData.isWorkout) ? 1.0 : 0.0
        let hourOfDay = Double(hourlyData.hour)

        return [meanHR, maxHR, hrStd, hrvSDNN, stepCount, isActive, hourOfDay]
    }
}

// MARK: - Private Helpers

private extension FeatureEngine {

    /// Estimates accelerometer magnitude from step count.
    /// Maps steps to a gravity-based magnitude (1.0g at rest → higher with motion).
    static func estimateAccMagnitude(from steps: Double) -> Double {
        // At rest (~0 steps/hour): ~1.0g (gravity only)
        // Light activity (~500 steps): ~1.2g
        // High activity (~2000+ steps): ~1.8g
        let normalizedSteps = min(steps / 2000.0, 1.0)
        return 1.0 + normalizedSteps * 0.8
    }
}

// MARK: - Array Statistics Helpers

private extension Array where Element == Double {

    /// Arithmetic mean.
    var mean: Double {
        guard !isEmpty else { return 0.0 }
        return reduce(0.0, +) / Double(count)
    }

    /// Standard deviation with configurable degrees of freedom.
    /// - Parameter ddof: Delta degrees of freedom (0 for population, 1 for sample).
    func std(ddof: Int = 0) -> Double {
        guard count > ddof else { return 0.0 }
        let avg = mean
        let variance = map { ($0 - avg) * ($0 - avg) }.reduce(0.0, +) / Double(count - ddof)
        return sqrt(variance)
    }
}
