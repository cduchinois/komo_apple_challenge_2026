//  InsightSequencer.swift
//  Komo
//
//  Rule-based matcher that personalizes the FIRST TWO cards of the Reflect
//  pool based on onboarding answers (Q3 recharges, Q4 drains), then leaves
//  the remaining cards in their original order.
//
//  The public surface is a protocol — a real reasoning engine (Foundation
//  Models / on-device LLM) can slot in behind the same API later.
//  TODO: replace RuleBasedInsightSequencer with the Foundation Models
//        reasoning engine, same InsightSequencing protocol.

import Foundation

/// Reorders a pool of Reflection cards so the first two feel personal.
///
/// Rules (Rule-based implementation):
/// - **Card 1** = first pool card whose `topics` intersect the user's drains,
///   iterating drains in the user's selection order. Fallback: card at index 9
///   (`your energy looks low right now`).
/// - **Card 2** = first `.reflect` card whose `topics` intersect the user's
///   recharges, iterating recharges in the user's selection order, excluding
///   whatever Card 1 already picked. Fallback: card at index 1 (`you slept 7+
///   hours…`, universally positive).
/// - **Rest** = the remaining cards, keeping original pool order, minus the
///   two already used.
///
/// The `drains` / `recharges` inputs are ordered arrays because priority
/// follows the order the user selected them in.
protocol InsightSequencing {
    func orderedPool(from cards: [Reflection],
                     drains: [Topic],
                     recharges: [Topic]) -> [Reflection]
}

/// Deterministic first-match matcher. Simple, testable, replaceable.
struct RuleBasedInsightSequencer: InsightSequencing {

    /// Index into the pool used as the "generic low energy" fallback for card 1
    /// (matches the 10th card in the seeded pool).
    private let genericFallbackIndex = 9
    /// Index into the pool used as the "universally positive" fallback for
    /// card 2 (matches the 2nd card in the seeded pool — sleep streak).
    private let positiveFallbackIndex = 1

    func orderedPool(from cards: [Reflection],
                     drains: [Topic],
                     recharges: [Topic]) -> [Reflection] {

        // MARK: Card 1 — first drain match (any type)
        var first: Reflection? = nil
        for drainTopic in drains {
            if let match = cards.first(where: { $0.topics.contains(drainTopic) }) {
                first = match
                break
            }
        }
        if first == nil, cards.indices.contains(genericFallbackIndex) {
            first = cards[genericFallbackIndex]
        }

        // MARK: Card 2 — first REFLECT card that matches a recharge topic,
        //                excluding whatever Card 1 already picked.
        var second: Reflection? = nil
        for rechargeTopic in recharges {
            if let match = cards.first(where: {
                $0.type == .reflect
                    && $0.topics.contains(rechargeTopic)
                    && $0.id != first?.id
            }) {
                second = match
                break
            }
        }
        if second == nil,
           cards.indices.contains(positiveFallbackIndex),
           cards[positiveFallbackIndex].id != first?.id {
            second = cards[positiveFallbackIndex]
        }

        // MARK: Rest — original order minus the two picked cards.
        let rest = cards.filter { $0.id != first?.id && $0.id != second?.id }

        var result: [Reflection] = []
        if let first { result.append(first) }
        if let second { result.append(second) }
        result.append(contentsOf: rest)
        return result
    }
}
