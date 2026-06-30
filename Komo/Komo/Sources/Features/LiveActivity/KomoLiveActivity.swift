import ActivityKit
import SwiftUI

// MARK: - Komo Live Activity Attributes

/// Defines the data model for the Dynamic Island / Lock Screen Live Activity.
///
/// To enable: In Xcode, add a Widget Extension target named "KomoWidget"
/// and reference KomoLiveActivityAttributes from it.
struct KomoLiveActivityAttributes: ActivityAttributes {

    // MARK: - Static data (set at launch, doesn't change)

    public struct ContentState: Codable, Hashable {
        // Dynamic data that updates throughout the day
        var stressLevel: ActivityStressLevel
        var currentHR: Int
        var message: String
        var progress: Double  // 0.0 to 1.0 for progress bar
        var emoji: String
    }

    // Static: user name
    var userName: String
}

// MARK: - Stress Level

enum ActivityStressLevel: String, Codable, Hashable {
    case calm = "Calm"
    case moderate = "Moderate"
    case high = "High stress"
    case analyzing = "Analyzing…"
}

// MARK: - KomoActivityManager

/// Manages the Dynamic Island Live Activity lifecycle.
@MainActor
final class KomoActivityManager {

    static let shared = KomoActivityManager()
    private var currentActivity: Activity<KomoLiveActivityAttributes>?
    private init() {}

    // MARK: - Start Activity

    /// Start the Dynamic Island — call this when analysis begins or user taps avatar.
    func startActivity(userName: String = "Sacha") async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activities not enabled on this device")
            return
        }

        // End any existing activity first
        await endActivity()

        let attributes = KomoLiveActivityAttributes(userName: userName)
        let initialState = KomoLiveActivityAttributes.ContentState(
            stressLevel: .analyzing,
            currentHR: 0,
            message: "Komo is analysing your day…",
            progress: 0.0,
            emoji: "🧠"
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            print("✅ Dynamic Island started: \(currentActivity?.id ?? "unknown")")
        } catch {
            print("❌ Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    // MARK: - Update from Analysis

    /// Update the Dynamic Island with real CoreML results.
    func updateActivity(from analysis: DayAnalysis) async {
        guard let activity = currentActivity else { return }

        let stressLevel: ActivityStressLevel
        let emoji: String
        let message: String

        switch analysis.highStressHours {
        case 0:
            stressLevel = .calm
            emoji = "😌"
            message = "You're doing great today!"
        case 1...2:
            stressLevel = .moderate
            emoji = "😐"
            message = "Some stress detected. Take it easy."
        default:
            stressLevel = .high
            emoji = "😤"
            message = "High stress day — \(analysis.highStressHours)h detected."
        }

        // Progress: steps toward 10k goal
        let stepsProgress = min(1.0, Double(analysis.totalSteps) / 10_000.0)

        let updatedState = KomoLiveActivityAttributes.ContentState(
            stressLevel: stressLevel,
            currentHR: Int(analysis.stressTimeline.last?.meanHR ?? 0),
            message: message,
            progress: stepsProgress,
            emoji: emoji
        )

        await activity.update(.init(state: updatedState, staleDate: nil))
        print("✅ Dynamic Island updated: \(stressLevel.rawValue)")
    }

    /// Update during analysis to show a focus mode countdown.
    func updateFocusMode(minutesRemaining: Int) async {
        guard let activity = currentActivity else { return }

        let progress = max(0.0, 1.0 - Double(minutesRemaining) / 25.0)
        let updatedState = KomoLiveActivityAttributes.ContentState(
            stressLevel: .moderate,
            currentHR: 0,
            message: "Focus Mode: \(minutesRemaining) min remaining",
            progress: progress,
            emoji: "🎯"
        )

        await activity.update(.init(state: updatedState, staleDate: nil))
    }

    // MARK: - End Activity

    func endActivity() async {
        for activity in Activity<KomoLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        print("✅ Dynamic Island ended")
    }
}
