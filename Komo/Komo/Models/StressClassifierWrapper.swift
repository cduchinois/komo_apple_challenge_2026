import CoreML
import Foundation

// MARK: - StressClassifierWrapper
//
// Bridges HealthKit HR/HRV samples to the CoreML StressClassifier.
//
// The model was trained on 20 physiological features. HealthKit only
// provides HR and HRV (SDNN), so features for EDA, temperature, and
// accelerometer are substituted with their training-set means, which
// maps to 0 after StandardScaler → the model treats them as neutral.

final class StressClassifierWrapper {

    static let shared = StressClassifierWrapper()

    private var model: MLModel?
    private var featureNames: [String] = []
    private var means: [Double] = []
    private var scales: [Double] = []

    private init() {
        loadScaler()
        loadModel()
    }

    // MARK: - Public API

    /// Returns true when the hour window is classified as stressed.
    /// `daySDNN` is the daily mean SDNN from HealthKit HRV samples (ms).
    /// `restingHR` is used as fallback threshold when CoreML is unavailable.
    func isStressedHour(
        hrSamples: [Double],
        daySDNN: Double?,
        restingHR: Double?
    ) -> Bool {
        guard !hrSamples.isEmpty else { return false }

        if let model, !featureNames.isEmpty {
            let raw = buildFeatureVector(hrSamples: hrSamples, daySDNN: daySDNN)
            if let result = runModel(model, rawFeatures: raw) {
                return result
            }
        }

        // Fallback: personalised HR threshold (mirrors original HealthAnalyzer rule)
        let mean = hrSamples.reduce(0, +) / Double(hrSamples.count)
        let threshold = (restingHR ?? 65) + 20.0
        return mean > threshold || mean > 95
    }

    // MARK: - Feature construction

    private func buildFeatureVector(hrSamples: [Double], daySDNN: Double?) -> [Double] {
        let n = Double(hrSamples.count)
        let meanHR = hrSamples.reduce(0, +) / n
        let variance = hrSamples.map { ($0 - meanHR) * ($0 - meanHR) }.reduce(0, +) / max(1, n - 1)
        let stdHR  = sqrt(variance)
        let maxHR  = hrSamples.max() ?? meanHR
        let minHR  = hrSamples.min() ?? meanHR

        // Inter-beat intervals (ms) derived from HR
        let ibis   = hrSamples.map { 60_000.0 / $0 }
        let meanIBI = ibis.reduce(0, +) / n
        let maxIBI = ibis.max() ?? meanIBI
        let minIBI = ibis.min() ?? meanIBI
        let ibiRange = maxIBI - minIBI

        // SDNN: use HealthKit daily HRV if available, else estimate from IBI σ
        let sdnn: Double
        if let hrv = daySDNN, hrv > 0 {
            sdnn = hrv
        } else if ibis.count > 1 {
            let v = ibis.map { ($0 - meanIBI) * ($0 - meanIBI) }.reduce(0, +) / Double(ibis.count - 1)
            sdnn = sqrt(v)
        } else {
            sdnn = trainingMean(at: 5)
        }

        // RMSSD from successive IBI differences
        let rmssd: Double
        if ibis.count > 1 {
            let sq = zip(ibis, ibis.dropFirst()).map { ($1 - $0) * ($1 - $0) }
            rmssd = sqrt(sq.reduce(0, +) / Double(sq.count))
        } else {
            rmssd = trainingMean(at: 6)
        }

        // pNN50: % of successive IBI differences > 50 ms
        let pnn50: Double
        if ibis.count > 1 {
            let diffs = zip(ibis, ibis.dropFirst()).map { abs($1 - $0) }
            pnn50 = Double(diffs.filter { $0 > 50 }.count) / Double(diffs.count) * 100.0
        } else {
            pnn50 = trainingMean(at: 7)
        }

        // Unavailable sensors → training mean (= 0 after scaling → neutral)
        return [
            meanHR, stdHR, maxHR, minHR,
            meanIBI, sdnn, rmssd, pnn50, ibiRange,
            trainingMean(at: 9),  trainingMean(at: 10), trainingMean(at: 11), // eda_mean/std/max
            trainingMean(at: 12), trainingMean(at: 13), trainingMean(at: 14), // eda_min/range/slope
            trainingMean(at: 15), trainingMean(at: 16), trainingMean(at: 17), // temp
            trainingMean(at: 18), trainingMean(at: 19)                         // acc
        ]
    }

    // MARK: - CoreML inference

    private func runModel(_ model: MLModel, rawFeatures: [Double]) -> Bool? {
        var dict: [String: MLFeatureValue] = [:]
        for (i, name) in featureNames.enumerated() {
            guard i < rawFeatures.count, i < means.count, i < scales.count else { break }
            let scaled = (rawFeatures[i] - means[i]) / scales[i]
            dict[name] = MLFeatureValue(double: scaled)
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: dict),
              let output   = try? model.prediction(from: provider) else { return nil }

        // coremltools exports classLabel as int64 (0/1) or string
        if let label = output.featureValue(for: "classLabel") {
            switch label.type {
            case .int64:  return label.int64Value == 1
            case .string:
                let s = label.stringValue.lowercased()
                return s.contains("stress") && !s.contains("no")
            default: break
            }
        }
        return nil
    }

    // MARK: - Loader helpers

    private func loadScaler() {
        guard let url  = Bundle.main.url(forResource: "StressClassifier_scaler", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let names   = json["feature_names"] as? [String],
              let meanArr = json["means"]         as? [Double],
              let scaleArr = json["scales"]       as? [Double]
        else { return }
        featureNames = names
        means  = meanArr
        scales = scaleArr
    }

    private func loadModel() {
        guard let url = Bundle.main.url(forResource: "StressClassifier", withExtension: "mlmodelc")
        else { return }
        model = try? MLModel(contentsOf: url)
    }

    private func trainingMean(at index: Int) -> Double {
        index < means.count ? means[index] : 0
    }
}
