//  DataProvider.swift
//  Komo
//
//  All energy data is read through this protocol. Today only `MockDataProvider`
//  exists; a `HealthKitDataProvider` can be dropped in later with zero view
//  changes. Per the brief we do NOT touch HealthKit yet.

import Foundation

protocol EnergyDataProviding {
    /// Today's energy snapshot for the main screen.
    func currentSnapshot() -> EnergySnapshot
    /// The passive signals for the stats scroll.
    func stats() -> [EnergyStat]
    /// The companion's insight lines, voiced in the chosen tone. Tapping the
    /// companion cycles through these.
    func insightLines(for tone: CompanionTone) -> [String]
    /// The single headline insight shown on the main insight card.
    func headlineInsights() -> [String]
    /// Per-factor breakdown of today's energy score (recovery + load items),
    /// shown when the user taps the (i) beside the energy word on Home.
    func energyBreakdown() -> EnergyBreakdown
    /// Data-personalized reflection cards for the home speech bubble.
    /// Returns [] if no data is available — AppState falls back to static pool.
    func personalizedReflections() -> [Reflection]
}

/// Default no-op — MockDataProvider and any future provider that doesn't
/// implement personalizedReflections() returns the static pool via AppState.
extension EnergyDataProviding {
    func personalizedReflections() -> [Reflection] { [] }
}

/// Static, on-device sample data mirroring the prototype exactly.
struct MockDataProvider: EnergyDataProviding {

    func currentSnapshot() -> EnergySnapshot {
        EnergySnapshot(
            word: "High",
            percent: 72,
            daysTogether: 12,
            rechargedBy: "sleep + walk",
            usedBy: "meetings + screen time",
            headlineInsight: "✨ A 15-min walk after dinner usually helps you recharge."
        )
    }

    func stats() -> [EnergyStat] {
        [
            .init(id: "hr", label: "Heart Rate", value: "64", unit: "bpm", sub: "Resting · steady", tone: .good),
            .init(id: "steps", label: "Steps", value: "7,842", unit: "", sub: "78% of your goal", tone: .good),
            .init(id: "sleep", label: "Sleep", value: "7h 24m", unit: "", sub: "Last night · solid", tone: .good),
            .init(id: "stress", label: "Stress", value: "Low", unit: "", sub: "Calm most of the day", tone: .good),
            .init(id: "hrv", label: "HRV Recovery", value: "72", unit: "%", sub: "Well recovered", tone: .good),
            .init(id: "activity", label: "Activity", value: "412", unit: "cal", sub: "Move ring almost closed", tone: .good),
            .init(id: "calendar", label: "Calendar Load", value: "4", unit: "events", sub: "A touch busy this afternoon", tone: .warn),
            .init(id: "screen", label: "Screen Time", value: "3h 12m", unit: "", sub: "A little high today", tone: .warn),
            .init(id: "standing", label: "Standing", value: "9", unit: "hrs", sub: "Goal reached", tone: .good),
        ]
    }

    func headlineInsights() -> [String] {
        [
            "✨ A 15-min walk after dinner usually helps you recharge.",
            "Winding down 20 minutes earlier tonight lifts tomorrow’s energy.",
            "A glass of water now keeps your afternoon feeling steady.",
        ]
    }

    // TODO: replace these mock weights with the real per-factor contributions
    // from the scoring algorithm. Keep `net == percent` once wired.
    func energyBreakdown() -> EnergyBreakdown {
        let contributions: [EnergyContribution] = [
            // Recovery (+84 total)
            .init(label: "Sleep",              detail: "7h20, solid deep sleep", points:  38, kind: .recovery),
            .init(label: "HRV",                detail: "near your baseline",     points:  20, kind: .recovery),
            .init(label: "Resting heart rate", detail: "normal",                 points:  14, kind: .recovery),
            .init(label: "Light movement",     detail: "6,800 steps",            points:  12, kind: .recovery),
            // Load (-12 total)
            .init(label: "Calendar",           detail: "4 meetings",             points:  -6, kind: .load),
            .init(label: "Stress",             detail: "2h elevated",            points:  -4, kind: .load),
            .init(label: "Hard workout",       detail: "none today",             points:  -2, kind: .load),
        ]
        // Net = 84 + (-12) = 72 → matches Home's Steady 72%.
        return EnergyBreakdown(
            percent: 72,
            word: "Steady",
            subtitle: "based on sleep, movement, stress, and calendar load",
            contributions: contributions
        )
    }

    func insightLines(for tone: CompanionTone) -> [String] {
        switch tone.id {
        case "cheerful":
            return [
                "7,842 steps already — you’re practically glowing today ✦",
                "Recovery’s at 72%! Your body is ready for whatever’s next.",
                "Almost closed your move ring — one little walk and it’s yours!",
            ]
        case "wise":
            return [
                "Low stress and high recovery — the body rewards consistency.",
                "Four events today. Protect the space between them; that’s where you breathe.",
                "Screen time’s a touch high. The leaves don’t scroll, and they grow just fine.",
            ]
        case "playful":
            return [
                "72% recovered? Someone’s been treating their body like a VIP 😎",
                "Your couch is jealous of your trainers today. Keep it up!",
                "3 hours of screen time… your eyes filed a gentle complaint.",
            ]
        case "gossip":
            return [
                "Don’t tell the others, but you’re my favorite human today 👀",
                "Psst — recovery’s at 72%. That’s elite-tier, just between us.",
                "I heard your step count bragging to your calendar. It earned it.",
            ]
        default: // gentle
            return [
                "Your heart’s been steady all day. That’s a quiet kind of strong.",
                "You slept well last night — let’s carry that softness forward.",
                "Your afternoon looks full. Maybe a slow breath between meetings?",
            ]
        }
    }
}
