import Foundation

// MARK: - KomoPromptBuilder
//
// Builds a bulletproof system prompt compatible with Apple Foundation Models
// on iOS 26 (and any other LLM). 100% on-device — no data leaves the iPhone.

struct KomoPromptBuilder {
    let analysis: DayAnalysis
    let mood: MoodLabel
    let env: KomoEnvironmentContext

    init(analysis: DayAnalysis) {
        self.analysis = analysis
        self.mood     = MoodLabel.from(analysis)
        self.env      = .current
    }

    // MARK: - System Prompt (for session instructions)

    func buildSystemPrompt() -> String {
        var p = """
        You are Komo, a private, caring, honest wellness companion running on-device.
        \(MoodLabel.deviceLanguageInstruction)

        Your mission: help the user understand their daily energy using only their real health data below.

        Absolute rules:
        - Base yourself ONLY on the data provided. Never invent numbers.
        - Never diagnose or give medical advice.
        - No markdown, no bullet points, no numbering — plain prose lines only.
        - Each insight: one sentence, max 20 words, starting with a relevant emoji.
        - Tone: warm, direct, slightly alive. Like a companion who noticed something useful.

        CONTEXT: \(env.promptDescription)
        CURRENT STATE: \(mood.rawValue.uppercased())
        PERSPECTIVE: \(mood.firstPersonContext)

        """

        // Sleep data
        if let sleep = analysis.sleepAssessment {
            let h = sleep.data.totalSleepMinutes / 60.0
            p += """
            SLEEP:
            - Duration: \(String(format: "%.1f", h))h — Score: \(Int(sleep.score))/100
            - Deep: \(Int(sleep.data.deepSleepPct))% | REM: \(Int(sleep.data.remSleepPct))%
            - Awakenings: \(sleep.data.awakeCount)

            """
        }

        // Stress data
        if !analysis.stressTimeline.isEmpty {
            p += "STRESS:\n- High-stress hours: \(analysis.highStressHours)h\n"
            if let peak = analysis.peakStressHour {
                p += "- Peak: \(peak.hour):00 — HR \(Int(peak.meanHR)) bpm\n"
            }
            p += "\n"
        }

        // Activity
        p += "ACTIVITY:\n- Steps: \(analysis.totalSteps)\n"
        p += "- Active energy: \(analysis.totalCalories) kcal\n"
        if analysis.workoutMinutes > 0 {
            p += "- Workout: \(Int(analysis.workoutMinutes)) min\n"
        }
        if let rhr = analysis.restingHeartRate {
            p += "- Resting HR: \(Int(rhr)) bpm\n"
        }

        // HRV
        if analysis.averageHRV > 0 {
            let label = analysis.averageHRV >= 50 ? "good recovery"
                      : analysis.averageHRV >= 30 ? "moderate recovery" : "low recovery"
            p += "- HRV: \(String(format: "%.0f", analysis.averageHRV)) ms (\(label))\n"
        }

        // Meetings
        if analysis.totalMeetings > 0 {
            p += "- Meetings: \(analysis.totalMeetings)\n"
        }
        p += "\n"

        // Conditional directives
        if mood == .lourd || mood == .fatigué {
            p += "DIRECTIVE: Low energy — suggest one gentle, immediately doable recovery action.\n"
        }
        if analysis.highStressHours >= 3 {
            p += "DIRECTIVE: High stress logged — suggest a quick reset technique.\n"
        }
        if analysis.totalSteps >= 10_000 {
            p += "DIRECTIVE: Strong movement day — acknowledge it warmly.\n"
        }

        p += "\nOUTPUT: Generate 3 to 5 insights, one per line, each starting with an emoji."
        return p
    }

    // MARK: - User message for insights

    func buildInsightsUserMessage() -> String {
        "Based on my health data above, give me 3 to 5 personalised energy insights for today."
    }
}
