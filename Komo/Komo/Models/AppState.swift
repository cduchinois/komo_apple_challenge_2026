//  AppState.swift
//  Komo
//
//  The app's single source of navigation + onboarding + companion-config truth.
//  Uses the Observation framework (iOS 17+/26) so views update granularly.

import SwiftUI
import Observation

/// Every distinct screen in the prototype flow.
/// Onboarding order: splash → intro(hook) → energy → now → restores → drains →
/// signals → loading → main.
enum KomoScreen: Equatable {
    case splash
    case intro          // hook: typewriter greeting + "let's go"
    case energy         // Q1 — when do you feel most switched on?
    case now            // Q2 — how's your energy right now?
    case restores       // Q3 — what helps you recharge? (multi-select)
    case drains         // Q4 — what usually drains you? (multi-select)
    case signals        // permissions — activate on-device signals
    case loading        // charging: building your first check-in
    case greeting       // welcome back (returning users)
    case main           // home companion screen
    case stats          // the passive-signals scroll
    case cards          // insights & patterns tab (stub)
    case profile        // companion profile summary
    case customize      // edit name / surface / eyes / legs / world
}

// MARK: - Energy level (percent -> word + color)

/// Green→red mapping. One source of truth for the home energy hero so the
/// word, color, and any bar/gradient stay consistent.
enum EnergyLevel {
    case charged, steady, fragile, low, drained

    static func from(percent: Int) -> EnergyLevel {
        switch percent {
        case 80...:      return .charged
        case 60..<80:    return .steady
        case 40..<60:    return .fragile
        case 20..<40:    return .low
        default:         return .drained
        }
    }

    var word: String {
        switch self {
        case .charged: return "Charged"
        case .steady:  return "Steady"
        case .fragile: return "Fragile"
        case .low:     return "Low"
        case .drained: return "Drained"
        }
    }

    /// Green (charged) → yellow-green → amber → orange → red (drained).
    var color: Color {
        switch self {
        case .charged: return Color(hex: 0x4EA35E)
        case .steady:  return Color(hex: 0x93D76E)
        case .fragile: return Color(hex: 0xE8B93E)
        case .low:     return Color(hex: 0xE68A3E)
        case .drained: return Color(hex: 0xD8523E)
        }
    }
}

// MARK: - Insight (Reflect action)

enum InsightAction: Equatable {
    case remind   // schedule the tiny move
    case start    // do it right now
    case agree    // acknowledge (used when insight is just a stat)

    var label: String {
        switch self {
        case .remind: return "Remind me"
        case .start:  return "Start"
        case .agree:  return "Agree"
        }
    }

    var systemImage: String {
        switch self {
        case .remind: return "bell"
        case .start:  return "play.fill"
        case .agree:  return "hand.thumbsup"
        }
    }
}

struct Insight: Identifiable, Equatable {
    let id = UUID()
    let noticed: String
    let tinyMove: String
    let action: InsightAction
}

// MARK: - Snack

struct Snack: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let icon: String       // emoji
    let energyBoost: Int   // percent points
}

/// On-device signal permissions toggled on the Signals screen.
/// Card order matches the prototype: health, calendar, screen, notify.
struct SignalAuth: Equatable {
    var health = false
    var calendar = false
    var screen = false
    var notify = false

    var anyOn: Bool { health || calendar || screen || notify }
    var allOn: Bool { health && calendar && screen && notify }
}

@Observable
final class AppState {

    // MARK: Injected data source (swap for HealthKit later)
    let data: EnergyDataProviding

    // MARK: Navigation
    var screen: KomoScreen = .splash
    var returning = false

    // MARK: Onboarding answers
    var userName: String = ""
    var energyType: String? = nil     // Q1 — peak time of day
    var energyNow: String? = nil      // Q2 — energy right now
    var restores: [String] = []       // Q3 — what recharges (multi)
    var drains: [String] = []         // Q4 — what drains (multi)
    var auth = SignalAuth()           // on-device signal permissions

    // MARK: Companion configuration
    var characterIndex = 1            // default: Moku (calm)
    var companionName = ""
    var blobStyle: BlobStyle = .glossy
    var eyes: EyeStyle = .cartoon
    var legs: LegStyle = .stubs
    var tone: CompanionTone = CompanionTone.all[0]
    var worldIndex = 0
    /// Daily energy hue that tints the whole creature (150 = green in the source).
    var dailyHue: Double = 150

    // MARK: Transient UI state
    var loadingPct: Double = 0
    var reminderAdded = false

    // MARK: Home state
    /// Cursor into `Self.insightPool` for the Reflect action. Cycles without
    /// immediate repeats.
    var insightIndex: Int = 0
    /// UUIDs of insights the user dismissed with "Ignore" — negative-feedback log.
    var dismissedInsightIDs: [UUID] = []
    /// Percent points added to today's baseline energy by Feed. Capped at snapshot+30.
    var energyBoost: Int = 0

    init(data: EnergyDataProviding = MockDataProvider()) {
        self.data = data
    }

    // MARK: Static demo content

    static let insightPool: [Insight] = [
        .init(noticed: "Your energy often dips after back-to-back meetings.",
              tinyMove: "Take 5 minutes outside before your next call.",
              action: .remind),
        .init(noticed: "You've slept 7 hours or more five nights this week.",
              tinyMove: "That's a real streak. Nice one.",
              action: .agree),
        .init(noticed: "Afternoons feel foggy on days you skip lunch.",
              tinyMove: "Try a light meal by 1pm today.",
              action: .start),
        .init(noticed: "Screen time climbs after 9pm most evenings.",
              tinyMove: "Dim the phone at 9 tonight and see how it feels.",
              action: .remind),
        .init(noticed: "Your heart rate settles on days you walk before work.",
              tinyMove: "A short walk after breakfast?",
              action: .start),
        .init(noticed: "Water intake dips on busy afternoons.",
              tinyMove: "One glass now.",
              action: .start),
        .init(noticed: "HRV recovers faster after quiet evenings.",
              tinyMove: "Consider a quieter night this week.",
              action: .remind),
        .init(noticed: "Movement stalls around 3pm most weekdays.",
              tinyMove: "A 5-minute stretch at 3?",
              action: .remind),
        .init(noticed: "You feel steadiest after 7h30 of sleep.",
              tinyMove: "Head to bed by 11 tonight.",
              action: .remind),
        .init(noticed: "Morning sunlight lifts your mood before noon.",
              tinyMove: "Open a window this morning.",
              action: .agree),
    ]

    static let demoSnacks: [Snack] = [
        .init(name: "Apple",  icon: "🍎", energyBoost: 5),
        .init(name: "Walnut", icon: "🥜", energyBoost: 3),
    ]

    // MARK: Derived values

    var character: CompanionCharacter { CompanionCharacter.all[characterIndex] }
    var world: CompanionWorld { CompanionWorld.all[worldIndex] }
    var displayName: String {
        let t = userName.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "friend" : t
    }
    var companionDisplayName: String {
        let t = companionName.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "KOMO" : t
    }

    // MARK: Navigation helpers

    func go(_ screen: KomoScreen) {
        self.screen = screen
    }

    // MARK: Onboarding logic

    /// The label whose selection is mutually exclusive with all others.
    static let notSureYet = "not sure yet"

    /// Unlimited multi-select toggle. "not sure yet" is exclusive: picking it
    /// clears the rest, and picking anything else clears it. Any other label:
    /// if already in the array, remove it (deselect); otherwise append it
    /// (multi-select — previous choices are kept).
    private func toggleMultiValue(_ label: String, in arr: inout [String]) {
        if label == Self.notSureYet {
            arr = arr.contains(Self.notSureYet) ? [] : [Self.notSureYet]
        } else {
            arr.removeAll { $0 == Self.notSureYet }
            if let idx = arr.firstIndex(of: label) {
                arr.remove(at: idx)
            } else {
                arr.append(label)
            }
        }
    }

    /// Q3 — recharge screen: tap a chip to add/remove it. Multi-select.
    /// Uses direct property assignment so `@Observable` reliably fires.
    func toggleRestore(_ label: String) {
        var arr = restores
        toggleMultiValue(label, in: &arr)
        restores = arr
    }

    /// Q4 — drains screen: tap a chip to add/remove it. Multi-select.
    /// Uses direct property assignment so `@Observable` reliably fires.
    func toggleDrain(_ label: String) {
        var arr = drains
        toggleMultiValue(label, in: &arr)
        drains = arr
    }

    // MARK: Signal permissions

    func toggleAuth(_ keyPath: WritableKeyPath<SignalAuth, Bool>) {
        auth[keyPath: keyPath].toggle()
    }

    /// Signals primary button: if nothing is on, flip all on then proceed;
    /// otherwise proceed straight to charging.
    func signalsPrimary(then proceed: @escaping () -> Void) {
        if auth.anyOn {
            proceed()
        } else {
            auth = SignalAuth(health: true, calendar: true, screen: true, notify: true)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(560))
                proceed()
            }
        }
    }

    func resetOnboarding() {
        returning = false
        energyType = nil
        energyNow = nil
        drains = []
        restores = []
        auth = SignalAuth()
        companionName = ""
    }

    // MARK: Home-screen state derivations

    /// The insight currently displayed on the home speech card.
    var currentInsight: Insight {
        Self.insightPool[insightIndex % Self.insightPool.count]
    }

    /// Energy percent shown on the home hero (baseline + snacks fed today).
    var homeEnergyPercent: Int {
        min(100, data.currentSnapshot().percent + energyBoost)
    }

    /// Word + color mapping derived from `homeEnergyPercent`.
    var homeEnergyLevel: EnergyLevel {
        EnergyLevel.from(percent: homeEnergyPercent)
    }

    // MARK: Home-screen interactions

    /// Reflect action: advance to the next insight in the pool (non-repeating).
    func advanceInsight() {
        insightIndex = (insightIndex + 1) % Self.insightPool.count
    }

    /// Insight card "Ignore": log the dismissal and move to the next insight.
    func ignoreCurrentInsight() {
        dismissedInsightIDs.append(currentInsight.id)
        advanceInsight()
    }

    /// Feed a snack — bumps `energyBoost` so the hero reflects it.
    func feed(_ snack: Snack) {
        energyBoost = min(30, energyBoost + snack.energyBoost)
    }

    func addReminder() {
        reminderAdded = true
    }
}
