import Foundation
import Combine
import SwiftData

// MARK: - HealthAvatarEngine

/// Top-level API for the health avatar.
///
/// **This is the single entry point your UI teammate should call.**
///
/// Usage from SwiftUI:
/// ```swift
/// @StateObject private var engine = HealthAvatarEngine.shared
///
/// Button("Analyze My Day") {
///     Task {
///         await engine.analyzeToday()
///     }
/// }
///
/// ForEach(engine.insights, id: \.self) { insight in
///     Text(insight)
/// }
/// ```
@MainActor
final class HealthAvatarEngine: ObservableObject {

    static let shared = HealthAvatarEngine()

    // MARK: - Published State (for SwiftUI binding)

    @Published var isLoading = false
    @Published var isAuthorized = false
    @Published var insights: [String] = []
    @Published var dayAnalysis: DayAnalysis?
    @Published var errorMessage: String?
    @Published var isDemoMode = false
    @Published var isUsingRealHealthData = false
    @Published var personalBaseline: PersonalBaseline?

    // MARK: - Dependencies

    private let healthKit = HealthKitManager.shared
    private let eventKit = EventKitManager.shared
    private let analyzer = HealthAnalyzer.shared
    private let insightGenerator = InsightGenerator.shared

    /// SwiftData model context — set by ContentView via `.environment(\.modelContext)`
    var modelContext: ModelContext?

    private init() {}

    // MARK: - Authorization

    /// Request HealthKit + Calendar permissions. Call once on app launch.
    func requestPermissions() async {
        do {
            try await healthKit.requestAuthorization()
            isAuthorized = true
        } catch {
            isAuthorized = false
            errorMessage = "HealthKit: \(error.localizedDescription)"
        }

        do {
            try await eventKit.requestAuthorization()
        } catch {
            // Calendar is optional — don't block the flow
            print("⚠️ Calendar access denied: \(error.localizedDescription)")
        }
    }

    // MARK: - Main Analysis

    /// Analyze today's health data and generate insights.
    ///
    /// This is the method the avatar calls when the user taps it.
    /// It runs the full pipeline: HealthKit → FeatureEngine → CoreML → Insights.
    func analyzeToday() async {
        await analyze(for: Date())
    }

    /// Analyze a specific day's health data.
    func analyze(for date: Date) async {
        isDemoMode = false
        isLoading = true
        errorMessage = nil
        insights = []
        dayAnalysis = nil
        isUsingRealHealthData = false

        do {
            // Step 1: Collect all health data
            let summary = try await healthKit.fetchDailySummary(for: date)
            isUsingRealHealthData = summary.containsRealHealthSignals

            // Step 2: Run CoreML analysis
            let analysis = analyzer.analyzeDay(summary: summary)
            dayAnalysis = analysis

            // Step 2.5: Compute personal baseline from SwiftData history
            var baseline: PersonalBaseline? = nil
            if let ctx = modelContext {
                baseline = BaselineManager.computeBaseline(context: ctx)
                personalBaseline = baseline
            }

            // Step 3: Generate natural language insights
            if summary.containsRealHealthSignals {
                let generatedInsights = await insightGenerator.generateInsights(from: analysis)
                insights = generatedInsights
            } else {
                insights = ["Aucune donnée HealthKit réelle trouvée pour aujourd'hui. Vérifie les permissions Santé et qu'une Apple Watch ou l'iPhone a enregistré des données."]
            }

            // Step 4: Save daily snapshot to SwiftData (auto, transparent)
            if let ctx = modelContext, summary.containsRealHealthSignals {
                let energyResult = EnergyScoreEngine.score(from: analysis, baseline: baseline)
                let snapshot = DailySnapshot.from(analysis: analysis, energyResult: energyResult)
                BaselineManager.saveSnapshot(snapshot, context: ctx)
            }

        } catch {
            print("❌ HealthKit Error: \(error)")
            errorMessage = error.localizedDescription
            isUsingRealHealthData = false
            // Generate fallback insights even on error
            insights = ["⚠️ Couldn't load all your health data. Check HealthKit permissions."]
        }

        isLoading = false
    }

    // MARK: - Demo Mode

    /// Toggle Demo Mode and provide mock data.
    func analyzeDemo() async {
        isDemoMode.toggle()
        guard isDemoMode else {
            insights = []
            dayAnalysis = nil
            return
        }

        isLoading = true
        errorMessage = nil
        insights = []
        dayAnalysis = nil

        // Simulate thinking delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Mock data
        let demoSleepData = SleepData(
            totalSleepMinutes: 480,
            deepSleepPct: 20.0,
            remSleepPct: 25.0,
            awakeCount: 1,
            awakeMinutes: 10.0,
            sleepOnsetLatencyMin: 15.0,
            restingHRDuringSleep: 55.0,
            respiratoryRate: 14.0,
            bloodOxygenAvg: 98.0,
            bedtimeConsistencyMin: 10.0
        )
        let demoSleepAssessment = SleepAssessment(
            score: 85.0,
            category: .good,
            data: demoSleepData
        )

        let demoAnalysis = DayAnalysis(
            date: Date(),
            stressTimeline: [
                StressReading(hour: 9, level: .high, confidence: 0.85, meanHR: 95.0, hrvSDNN: 30.0),
                StressReading(hour: 10, level: .medium, confidence: 0.70, meanHR: 85.0, hrvSDNN: 40.0)
            ],
            sleepAssessment: demoSleepAssessment,
            anomalies: [],
            totalSteps: 10542,
            totalCalories: 580,
            totalMeetings: 4,
            workoutMinutes: 45,
            restingHeartRate: 58.0,
            screenTimeMinutes: 285,
            averageMETs: 2.0
        )

        dayAnalysis = demoAnalysis
        insights = [
            "💤 Great sleep last night! You got 8 hours with excellent deep sleep.",
            "🧘 Looks like a bit of stress this morning around 9 AM, likely due to your 4 meetings today.",
            "🏃 Awesome activity level overall! You already hit 10k steps."
        ]

        isLoading = false
    }
}
