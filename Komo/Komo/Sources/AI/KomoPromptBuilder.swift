import Foundation

// MARK: - KomoPromptBuilder
//
// Builds developer-owned instructions + a user prompt that injects real
// HealthKit / EnergyScoreEngine data. The model must not invent numbers.

struct KomoPromptBuilder {
    let analysis: DayAnalysis
    let context: KomoInsightContext
    let mood: MoodLabel
    let env: KomoEnvironmentContext

    init?(analysis: DayAnalysis) {
        guard let context = KomoInsightContext.build(from: analysis) else { return nil }
        self.analysis = analysis
        self.context = context
        self.mood = context.mood
        self.env = .current
    }

    // MARK: - System instructions (developer-only)

    func buildSystemPrompt() -> String {
        """
        You are Komo, a private, caring wellness companion running entirely on-device.
        \(MoodLabel.deviceLanguageInstruction)

        Explain why the user feels \(context.energyWord.lowercased()) today (\(context.energyScore)% energy), using ONLY the data in the user message.

        Voice (critical):
        - Write like a warm friend texting, not a health report or AI assistant.
        - Short, simple sentences. Everyday words a non-athlete understands.
        - Never use em-dashes (—) or dash-as-punctuation. Use periods or commas instead.
        - Never use acronyms or medical jargon: no HRV, VFC, HR, FC, bpm, ms, RHR, baseline, cardiovascular, cognitive load.
        - Say "sleep", "walking" or "steps", "stress", "meetings", "workout", "heart at rest", "body recovery", "how you feel".
        - Lowercase-friendly, gentle, direct. No bullet lists in output.

        Data rules:
        - Never invent or change numbers. Repeat only values provided.
        - The primary factor is pre-computed. Align with it; do not pick a different main cause.
        - No medical diagnosis or treatment advice.

        Environment: \(env.promptDescription)
        User mood: \(mood.rawValue). \(mood.firstPersonContext)

        Good example: "tu as bien dormi cette nuit, environ 8 heures. ton corps a eu le temps de se reposer."
        Bad example: "tu as dormi 8.5 heures — bonne récupération."
        Bad example: "ta VFC est basse à 42 ms."
        """
    }

    // MARK: - User prompt (data injection)

    func buildDailyInsightUserMessage() -> String {
        let factor = KomoInsightVoice.humanFactorName(context.mainFactor)
        return """
        Here is today's real health data for this user:

        \(context.serializedDataBlock)

        Generate one insight card:
        - observation: one warm sentence on why they feel \(context.energyWord.lowercased()) today. Focus on \(factor). Plain language only.
        - quickWin: one simple thing they can do in the next hour (max 15 words). No jargon.
        """
    }

    func buildInsightsUserMessage() -> String {
        """
        \(context.serializedDataBlock)

        Generate 3 short companion lines (max 20 words each) about today's energy.
        Plain everyday language. No em-dashes. No HRV/VFC/FC/bpm/ms.
        Start each line with a relevant emoji.
        """
    }
}
