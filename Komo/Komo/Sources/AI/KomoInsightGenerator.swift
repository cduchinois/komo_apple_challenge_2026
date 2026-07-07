import Foundation

// MARK: - KomoInsightGenerator
//
// On-device AI insights tied to real HealthKit + EnergyScoreEngine data.
// Uses @Generable for structured output; falls back to rule-based context.
//
// Uses SystemLanguageModel (on-device) — NOT PrivateCloudCompute, which
// requires com.apple.developer.private-cloud-compute entitlement.

#if canImport(FoundationModels)
import FoundationModels

@Generable
struct KomoDailyInsightCard {
    @Guide(description: "One warm, simple sentence. Everyday words only. No em-dashes. No HRV, VFC, FC, bpm, ms. Max 22 words.")
    var observation: String

    @Guide(description: "One easy next step for the next hour. Plain language. Max 15 words.")
    var quickWin: String
}

@Generable
struct KomoDailyInsightLines {
    @Guide(description: "2-4 short lines. Emoji at start. Warm friend tone. No em-dashes or medical jargon. Max 20 words each.")
    var lines: [String]
}

final class KomoInsightGenerator {
    private var session: LanguageModelSession?

    func generateDailyInsight(for analysis: DayAnalysis) async -> KomoGeneratedInsight? {
        guard let context = KomoInsightContext.build(from: analysis) else { return nil }
        guard #available(iOS 26.0, *) else { return context.ruleBasedInsight() }

        guard let builder = KomoPromptBuilder(analysis: analysis),
              let s = makeSession(builder: builder) else {
            return context.ruleBasedInsight()
        }
        session = s

        do {
            let response = try await s.respond(
                to: builder.buildDailyInsightUserMessage(),
                generating: KomoDailyInsightCard.self
            )
            let card = response.content
            guard !card.observation.isEmpty, !card.quickWin.isEmpty else {
                return context.ruleBasedInsight()
            }
            return KomoGeneratedInsight(
                observation: KomoInsightVoice.polish(card.observation),
                suggestion: KomoInsightVoice.polish(card.quickWin),
                mainFactor: context.mainFactor,
                energyScore: context.energyScore,
                energyWord: context.energyWord
            )
        } catch {
            return context.ruleBasedInsight()
        }
    }

    func generateCompanionLines(for analysis: DayAnalysis) async -> [String] {
        guard #available(iOS 26.0, *) else { return [] }
        guard let builder = KomoPromptBuilder(analysis: analysis) else { return [] }

        guard let s = session ?? makeSession(builder: builder) else { return [] }
        session = s

        do {
            let response = try await s.respond(
                to: builder.buildInsightsUserMessage(),
                generating: KomoDailyInsightLines.self
            )
            return response.content.lines
                .map { KomoInsightVoice.polish($0) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    func generateInsights(for analysis: DayAnalysis) async -> [String] {
        let lines = await generateCompanionLines(for: analysis)
        return lines.isEmpty ? [] : lines
    }

    @available(iOS 26.0, *)
    private func makeSession(builder: KomoPromptBuilder) -> LanguageModelSession? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        return LanguageModelSession(instructions: builder.buildSystemPrompt())
    }
}

#else

final class KomoInsightGenerator {
    func generateDailyInsight(for analysis: DayAnalysis) async -> KomoGeneratedInsight? {
        KomoInsightContext.build(from: analysis)?.ruleBasedInsight()
    }

    func generateCompanionLines(for analysis: DayAnalysis) async -> [String] { [] }

    func generateInsights(for analysis: DayAnalysis) async -> [String] { [] }
}

#endif
