import Foundation
import UserNotifications

// MARK: - NotificationManager

/// Schedules local notifications based on CoreML health analysis.
/// Komo sends proactive messages throughout the day and at end of day.
@MainActor
final class NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
            print("✅ Notifications authorized")
        } catch {
            print("⚠️ Notifications denied: \(error.localizedDescription)")
        }
    }

    // MARK: - Schedule from Analysis

    /// Call this after analyzeToday() — schedules relevant notifications.
    func scheduleInsightNotifications(from analysis: DayAnalysis) async {
        let center = UNUserNotificationCenter.current()

        // Remove previous Komo notifications
        center.removePendingNotificationRequests(withIdentifiers: [
            "komo.stress", "komo.sleep", "komo.anomaly", "komo.evening"
        ])

        // 1. Stress peak notification (immediate if detected)
        if let peak = analysis.peakStressHour {
            let content = UNMutableNotificationContent()
            content.title = "Komo noticed something 🧠"
            content.body = "Your stress peaked at \(peak.hour):00 — HR reached \(Int(peak.meanHR)) BPM. Take a breath."
            content.sound = .default
            content.categoryIdentifier = "KOMO_INSIGHT"

            // Send in 5 seconds for demo, or schedule for actual peak hour
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(identifier: "komo.stress", content: content, trigger: trigger)
            try? await center.add(request)
        }

        // 2. Sleep notification (send at 9am next morning)
        if let sleep = analysis.sleepAssessment, sleep.score < 70 {
            let content = UNMutableNotificationContent()
            content.title = "Komo · Good morning 🌅"
            content.body = sleepMessage(score: sleep.score, hours: sleep.data.totalSleepMinutes / 60)
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = 9
            dateComponents.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(identifier: "komo.sleep", content: content, trigger: trigger)
            try? await center.add(request)
        }

        // 3. Anomaly notification (immediate)
        if let anomaly = analysis.anomalies.first {
            let content = UNMutableNotificationContent()
            content.title = "Komo detected an anomaly ⚠️"
            content.body = anomaly.description
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
            let request = UNNotificationRequest(identifier: "komo.anomaly", content: content, trigger: trigger)
            try? await center.add(request)
        }

        // 4. Evening summary (every day at 9pm)
        let content = UNMutableNotificationContent()
        content.title = "New message from Komo. 💬"
        content.body = eveningSummary(analysis: analysis)
        content.sound = .default
        content.badge = 1

        var dateComponents = DateComponents()
        dateComponents.hour = 21
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "komo.evening", content: content, trigger: trigger)
        try? await center.add(request)

        print("📬 \(analysis.anomalies.isEmpty ? 3 : 4) notifications scheduled")
    }

    /// Send a test notification immediately — useful for demo.
    func sendDemoNotification(insights: [String]) async {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "New message from Komo. 💬"
        content.body = insights.first ?? "Tap to see your daily health summary."
        content.sound = .default
        content.badge = 1

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: "komo.demo", content: content, trigger: trigger)
        try? await center.add(request)
        print("📬 Demo notification scheduled in 3s")
    }

    // MARK: - Message Helpers

    private func sleepMessage(score: Double, hours: Double) -> String {
        if hours < 6 {
            return String(format: "You only slept %.0fh last night. Sleep score: %d/100. Try to rest more tonight.", hours, Int(score))
        } else if score < 50 {
            return String(format: "You slept %.0fh but the quality was poor (%d/100). Less screens before bed?", hours, Int(score))
        } else {
            return String(format: "Sleep score: %d/100. %.0fh of sleep — almost there!", Int(score), hours)
        }
    }

    private func eveningSummary(analysis: DayAnalysis) -> String {
        var parts: [String] = []
        if let sleep = analysis.sleepAssessment {
            parts.append("Sleep: \(Int(sleep.score))/100")
        }
        if analysis.highStressHours > 0 {
            parts.append("\(analysis.highStressHours)h of stress detected")
        }
        if analysis.totalSteps > 0 {
            parts.append("\(analysis.totalSteps) steps")
        }
        return parts.isEmpty
            ? "Tap to see your daily health summary."
            : parts.joined(separator: " · ") + ". Tap for full insights."
    }
}
