import CoreML
import Foundation

// MARK: - HealthAnalyzer

/// Unified CoreML inference engine that wraps all 3 models
/// (StressClassifier, SleepQualityScorer, AnomalyDetector)
/// and produces a complete DayAnalysis.
class HealthAnalyzer {

    static let shared = HealthAnalyzer()

    // MARK: - CoreML Models (lazy-loaded)

    private var stressModel: MLModel?
    private var sleepScorer: MLModel?
    private var anomalyDetector: MLModel?

    // MARK: - Scaler Parameters

    private var scalerFeatureNames: [String] = []
    private var scalerMeans: [Double] = []
    private var scalerScales: [Double] = []

    // MARK: - Init

    init() {
        loadModels()
        loadScalerParams()
    }

    // MARK: - Main Analysis

    /// Analyze an entire day's health data through all CoreML models.
    ///
    /// - Parameter summary: Complete daily health summary from HealthKitManager.
    /// - Returns: Full day analysis with stress timeline, sleep assessment, and anomalies.
    func analyzeDay(summary: DailyHealthSummary) -> DayAnalysis {
        var stressTimeline: [StressReading] = []
        var anomalies: [HealthAnomaly] = []

        // --- Process each hour ---
        for hourlyData in summary.hourlyData {
            guard hourlyData.hasEnoughData else { continue }

            // Stress classification
            if let features = FeatureEngine.stressFeatures(from: hourlyData) {
                let scaledFeatures = FeatureEngine.scaleStressFeatures(
                    features,
                    scalerJSON: [
                        "mean": scalerMeans,
                        "scale": scalerScales,
                    ]
                )
                let (level, confidence) = classifyStress(features: scaledFeatures)
                let reading = StressReading(
                    hour: hourlyData.hour,
                    level: level,
                    confidence: confidence,
                    meanHR: features["mean_hr"] ?? 0,
                    hrvSDNN: features["sdnn"]
                )
                stressTimeline.append(reading)
            }

            // Anomaly detection
            if let anomalyFeatures = FeatureEngine.anomalyFeatures(from: hourlyData) {
                if detectAnomaly(features: anomalyFeatures) {
                    let bpms = hourlyData.heartRateSamples.map(\.bpm)
                    let anomaly = HealthAnomaly(
                        hour: hourlyData.hour,
                        description: describeAnomaly(bpms: bpms, hour: hourlyData.hour),
                        metric: "heart_rate",
                        value: bpms.max() ?? 0,
                        expectedRange: 50...120
                    )
                    anomalies.append(anomaly)
                }
            }
        }

        // --- Sleep assessment ---
        var sleepAssessment: SleepAssessment? = nil
        if let sleepData = summary.sleepData {
            let score = scoreSleepDirect(from: sleepData)
            sleepAssessment = SleepAssessment(
                score: score,
                category: SleepCategory(score: score),
                data: sleepData
            )
        }

        return DayAnalysis(
            date: summary.date,
            stressTimeline: stressTimeline,
            sleepAssessment: sleepAssessment,
            anomalies: anomalies,
            totalSteps: summary.totalSteps,
            totalCalories: summary.totalCalories,
            totalMeetings: summary.totalMeetings,
            workoutMinutes: summary.workoutMinutes,
            restingHeartRate: summary.restingHeartRate,
            screenTimeMinutes: summary.screenTimeMinutes,
            averageMETs: summary.averageMETs
        )
    }

    // MARK: - Model Inference

    /// Classify stress level from scaled features.
    private func classifyStress(features: [Double]) -> (level: StressLevel, confidence: Double) {
        guard let model = stressModel else {
            // Fallback: rule-based stress from mean HR
            return fallbackStressClassification(features: features)
        }

        let featureOrder = [
            "mean_hr", "std_hr", "max_hr", "min_hr",
            "mean_ibi", "sdnn", "rmssd", "pnn50", "ibi_range",
            "eda_mean", "eda_std", "eda_max", "eda_min", "eda_range", "eda_slope",
            "temp_mean", "temp_std", "temp_slope",
            "acc_magnitude_mean", "acc_magnitude_std",
        ]

        do {
            var featureDict: [String: MLFeatureValue] = [:]
            for (index, name) in featureOrder.enumerated() {
                let value = index < features.count ? features[index] : 0.0
                featureDict[name] = MLFeatureValue(double: value)
            }

            let featureProvider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: featureProvider)

            // Binary model: 0 = non-stress, 1 = stress
            if let classLabel = prediction.featureValue(for: "stress_level")?.int64Value {
                let level: StressLevel = classLabel == 1 ? .high : .low
                // Try to get confidence from probabilities
                let confidence = prediction.featureValue(for: "stress_levelProbability")?
                    .dictionaryValue[classLabel as NSNumber]?.doubleValue ?? 0.8
                return (level, confidence)
            }
        } catch {
            print("⚠️ Stress model inference failed: \(error.localizedDescription)")
        }

        return fallbackStressClassification(features: features)
    }

    /// Calcule le score de qualité du sommeil (0-100) directement depuis les données brutes.
    ///
    /// Bypasse le SleepQualityScorer CoreML qui n'est pas fiable sans
    /// les données EDA/température du dataset WESAD original.
    ///
    /// Formule basée sur :
    /// - Walker (2017) "Why We Sleep" — durée optimale 7-9h
    /// - Tasali et al. (2008) — sommeil profond 13-23%
    /// - Carskadon & Dement (2005) — REM 20-25%
    /// - Espie et al. — fragmentations nocturnes
    private func scoreSleepDirect(from data: SleepData) -> Double {

        // 1. DURATION (0-40 pts)
        // deepSleepPct et remSleepPct sont des fractions (0.21 = 21%)
        let hours = data.totalSleepMinutes / 60.0
        let durationScore: Double
        switch hours {
        case 8...:         durationScore = 40
        case 7..<8:        durationScore = 38
        case 6..<7:        durationScore = 28 + (hours - 6.0) * 10.0
        case 5..<6:        durationScore = 15 + (hours - 5.0) * 13.0
        default:           durationScore = max(0, hours / 5.0 * 15.0)
        }

        // 2. DEEP SLEEP % (0-20 pts) — cible 13-23%
        let deepPct = data.deepSleepPct * 100.0  // fraction → pourcentage
        let deepScore: Double
        switch deepPct {
        case 13...23:      deepScore = 20
        case 23...:        deepScore = max(14, 20 - (deepPct - 23) * 0.5)
        case 8..<13:       deepScore = 10 + (deepPct - 8) / 5.0 * 10.0
        default:           deepScore = max(0, deepPct / 8.0 * 10.0)
        }

        // 3. REM % (0-20 pts) — cible 20-25%
        let remPct = data.remSleepPct * 100.0
        let remScore: Double
        switch remPct {
        case 20...25:      remScore = 20
        case 25...:        remScore = max(14, 20 - (remPct - 25) * 0.5)
        case 12..<20:      remScore = 10 + (remPct - 12) / 8.0 * 10.0
        default:           remScore = max(0, remPct / 12.0 * 10.0)
        }

        // 4. FRAGMENTATIONS (0-20 pts)
        let awakeScore: Double
        switch data.awakeCount {
        case 0:            awakeScore = 20
        case 1:            awakeScore = 17
        case 2:            awakeScore = 13
        case 3:            awakeScore = 9
        case 4:            awakeScore = 6
        default:           awakeScore = max(0, 6 - Double(data.awakeCount - 4) * 2)
        }

        let total = durationScore + deepScore + remScore + awakeScore
        print("   😴 Sleep score (rule-based): \(Int(total.rounded())) | dur=\(Int(durationScore)) deep=\(Int(deepScore)) rem=\(Int(remScore)) awake=\(Int(awakeScore)) | \(String(format: "%.1f", hours))h \(Int(deepPct))%deep \(Int(remPct))%rem")
        return min(max(total, 0), 100)
    }

    /// Score sleep quality from features via CoreML.
    /// NOTE: this function is kept but no longer called — use scoreSleepDirect instead.
    private func scoreSleep(features: [Double]) -> Double {
        guard let model = sleepScorer else {
            return min(max(features[0] / 480.0 * 100.0, 0), 100)
        }

        do {
            let featureNames = [
                "total_sleep_minutes", "deep_sleep_pct", "rem_sleep_pct",
                "awake_count", "sleep_onset_latency_min",
                "resting_hr_sleep", "respiratory_rate",
                "blood_oxygen_avg", "bedtime_consistency_min",
            ]

            var dict: [String: MLFeatureValue] = [:]
            for (i, name) in featureNames.enumerated() {
                dict[name] = MLFeatureValue(double: features[i])
            }

            let featureProvider = try MLDictionaryFeatureProvider(dictionary: dict)
            let prediction = try model.prediction(from: featureProvider)

            if let score = prediction.featureValue(for: "sleep_quality_score")?.doubleValue {
                return min(max(score, 0), 100)
            }
        } catch {
            print("⚠️ Sleep model inference failed: \(error.localizedDescription)")
        }

        return min(max(features[0] / 480.0 * 100.0, 0), 100)
    }

    /// Detect anomaly from features.
    /// - Returns: `true` if anomaly detected (class 0), `false` if normal (class 1).
    private func detectAnomaly(features: [Double]) -> Bool {
        guard let model = anomalyDetector else {
            // Fallback: simple threshold on mean HR
            return features[0] > 120 || features[0] < 40
        }

        do {
            // The anomaly model was trained as a simple threshold or single-feature model
            // taking 'anomaly_score' instead of the raw 7 features.
            let featureProvider = try MLDictionaryFeatureProvider(
                dictionary: ["anomaly_score": MLFeatureValue(double: features[0])]
            )

            let prediction = try model.prediction(from: featureProvider)

            if let label = prediction.featureValue(for: "anomaly_label")?.int64Value {
                return label == 0  // 0 = anomaly, 1 = normal
            }
        } catch {
            print("⚠️ Anomaly model inference failed: \(error.localizedDescription)")
        }

        return features[0] > 120 || features[0] < 40
    }

    // MARK: - Model Loading

    private func loadModels() {
        stressModel = loadModel(named: "StressClassifier")
        sleepScorer = loadModel(named: "SleepQualityScorer")
        anomalyDetector = loadModel(named: "AnomalyDetector")
    }

    private func loadModel(named name: String) -> MLModel? {
        // First try compiled model (.mlmodelc), then raw model (.mlmodel)
        if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            do {
                return try MLModel(contentsOf: url)
            } catch {
                print("⚠️ Failed to load \(name).mlmodelc: \(error.localizedDescription)")
            }
        }

        // Compile from .mlmodel at runtime (dev fallback)
        if let url = Bundle.main.url(forResource: name, withExtension: "mlmodel") {
            do {
                let compiledURL = try MLModel.compileModel(at: url)
                return try MLModel(contentsOf: compiledURL)
            } catch {
                print("⚠️ Failed to compile \(name).mlmodel: \(error.localizedDescription)")
            }
        }

        print("⚠️ CoreML model \(name) not found in bundle — using fallback rules")
        return nil
    }

    // MARK: - Scaler Loading

    private func loadScalerParams() {
        guard let url = Bundle.main.url(forResource: "StressClassifier_scaler", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let featureNames = json["feature_names"] as? [String],
              let means = json["means"] as? [Double],
              let scales = json["scales"] as? [Double]
        else {
            print("⚠️ StressClassifier_scaler.json not found — stress features won't be scaled")
            return
        }

        scalerFeatureNames = featureNames
        scalerMeans = means
        scalerScales = scales
    }

    // MARK: - Fallback Helpers

    private func fallbackStressClassification(features: [Double]) -> (StressLevel, Double) {
        // Rule-based: use mean HR (first feature after scaling → approximate from raw)
        // Without scaler, we can't recover raw HR, so use thresholds on scaled values
        // Positive scaled mean_hr → higher than average → more stressed
        let scaledMeanHR = features.isEmpty ? 0 : features[0]
        if scaledMeanHR > 1.5 {
            return (.high, 0.7)
        } else if scaledMeanHR > 0.5 {
            return (.medium, 0.6)
        }
        return (.low, 0.6)
    }

    private func describeAnomaly(bpms: [Double], hour: Int) -> String {
        let maxBPM = bpms.max() ?? 0
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"

        let calendar = Calendar.current
        let hourDate = calendar.date(
            bySettingHour: hour, minute: 0, second: 0,
            of: Date()
        )
        let timeString = hourDate.map { formatter.string(from: $0) } ?? "\(hour):00"

        if maxBPM > 120 {
            return "Unusually high heart rate (\(Int(maxBPM)) BPM) at \(timeString)"
        } else if maxBPM < 50 {
            return "Unusually low heart rate (\(Int(maxBPM)) BPM) at \(timeString)"
        }
        return "Unusual heart rate pattern at \(timeString)"
    }
}
