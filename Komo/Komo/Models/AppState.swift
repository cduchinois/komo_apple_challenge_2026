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
    case cards          // insights, todos & saved cards
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

// MARK: - Reflection (Reflect action)
//
// The Reflect action serves one Reflection card at a time. The old 10-item
// Insight pool is fully removed — this Reflection pool is the single truth.

enum ReflectionType: String, Equatable {
    case add       // sits on the calendar
    case reflect   // an observation, no active step
    case remind    // a nudge to schedule
    case start     // an immediate move
}

enum ReflectionAction: String, Identifiable, Equatable, CaseIterable {
    case addToCalendar
    case save
    case writeNote
    case remindMe
    case startNow
    case done
    case next

    var id: String { rawValue }

    var label: String {
        switch self {
        case .addToCalendar: return "Add to calendar"
        case .save:          return "Save"
        case .writeNote:     return "Write a note"
        case .remindMe:      return "Remind me"
        case .startNow:      return "Start now"
        case .done:          return "Done"
        case .next:          return "Next"
        }
    }

    var systemImage: String {
        switch self {
        case .addToCalendar: return "calendar.badge.plus"
        case .save:          return "bookmark"
        case .writeNote:     return "square.and.pencil"
        case .remindMe:      return "bell"
        case .startNow:      return "play.fill"
        case .done:          return "checkmark"
        case .next:          return "chevron.right"
        }
    }

    /// `.next` is the trailing/secondary button on every card.
    var isSecondary: Bool { self == .next }
}

struct Reflection: Identifiable, Equatable {
    let id = UUID()
    let type: ReflectionType
    let observation: String
    let suggestion: String
    let actions: [ReflectionAction]

    /// If the suggestion mentions "N-minute" / "N minute" / "N minutes", extract N.
    /// Otherwise 3:00 default for focus timer.
    var suggestedDurationSeconds: Int {
        let text = suggestion.lowercased()
        // Look for the first "<digits>[-space]minute" match.
        if let range = text.range(of: "(\\d+)[- ]?minute", options: .regularExpression),
           let n = Int(text[range].filter(\.isNumber)) {
            return max(30, n * 60)
        }
        return 180
    }
}

// MARK: - Saved insight / Todo item (Cards tab feeds)

struct SavedInsight: Identifiable, Equatable {
    let id = UUID()
    let reflectionID: UUID
    let observation: String
    let suggestion: String
    var note: String?
    let savedAt: Date
}

enum TodoKind: String, Equatable {
    case reminder  // from Remind me
    case calendar  // from Add to calendar
}

struct TodoItem: Identifiable, Equatable {
    let id = UUID()
    let reflectionID: UUID
    let text: String
    let kind: TodoKind
    var completed: Bool = false
    let createdAt: Date
}

// MARK: - Snack (mutable stock)

struct Snack: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let icon: String            // emoji
    let energyBoost: Double     // points added to energy hero
    var stock: Int              // remaining pieces
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

    // MARK: Home state — Reflect
    /// Cursor into `Self.reflectionPool`. Cycles without immediate repeats.
    var reflectionIndex: Int = 0

    // MARK: Home state — Feed
    /// Points added to today's baseline energy by feeding. Capped at +30.
    var energyBoost: Double = 0
    /// Mutable snack inventory (stock decreases as the user feeds).
    var snacks: [Snack] = AppState.initialSnacks

    // MARK: Cards tab feeds
    var savedInsights: [SavedInsight] = []
    var todos: [TodoItem] = []

    init(data: EnergyDataProviding = MockDataProvider()) {
        self.data = data
    }

    // MARK: Static demo content

    /// Two starter snacks, each with limited stock (2 pieces).
    /// Energy values kept small so the hero moves subtly, not dramatically.
    static let initialSnacks: [Snack] = [
        .init(name: "Apple",  icon: "🍎", energyBoost: 1.0, stock: 2),
        .init(name: "Walnut", icon: "🥜", energyBoost: 0.5, stock: 2),
    ]

    /// Additional snack shapes shown as locked in the store, with a hint on
    /// how to earn them (rest + movement).
    static let lockedSnackPreviews: [(name: String, icon: String)] = [
        ("Berry",  "🫐"),
        ("Cookie", "🍪"),
    ]

    /// A light seed of evergreen energy tips shown in the Cards tab's
    /// "Energy advice" section. TODO: derive these from real patterns.
    static let energyAdvice: [String] = [
        "Short walks after meetings tend to reset focus.",
        "Consistency in sleep matters more than a single long night.",
        "A light lunch keeps afternoon energy steadier.",
        "Morning sunlight helps set your rhythm for the day.",
        "Screen dimming after 9pm often improves sleep depth.",
    ]

    /// The Reflect pool — exactly 25 cards, in this order.
    static let reflectionPool: [Reflection] = [
        .init(type: .add,
              observation: "your energy often dips after back-to-back meetings.",
              suggestion: "take 5 minutes outside before your next call.",
              actions: [.addToCalendar, .save, .next]),
        .init(type: .reflect,
              observation: "you slept 7+ hours on five nights this week.",
              suggestion: "your body seems to recover better when sleep is consistent.",
              actions: [.writeNote, .save, .next]),
        .init(type: .remind,
              observation: "afternoons feel foggy on days you eat a heavy lunch.",
              suggestion: "try a lighter lunch before 1pm today.",
              actions: [.remindMe, .save, .next]),
        .init(type: .remind,
              observation: "your screen time usually climbs after 9pm.",
              suggestion: "dim your phone at 9 tonight and see how your sleep feels.",
              actions: [.remindMe, .save, .next]),
        .init(type: .start,
              observation: "you skipped your usual workout today.",
              suggestion: "try a quick 10-minute reset instead.",
              actions: [.startNow, .save, .next]),
        .init(type: .start,
              observation: "mornings go better when you begin with focus instead of scrolling.",
              suggestion: "start a 10-minute focus session.",
              actions: [.startNow, .remindMe, .next]),
        .init(type: .start,
              observation: "someone's been on your mind.",
              suggestion: "send a quick text or call them now.",
              actions: [.startNow, .done, .next]),
        .init(type: .add,
              observation: "your calendar looks packed before lunch.",
              suggestion: "block 10 minutes after your last morning meeting.",
              actions: [.addToCalendar, .next]),
        .init(type: .remind,
              observation: "you tend to sit for long stretches on workdays.",
              suggestion: "stand up for 3 minutes before your next session.",
              actions: [.remindMe, .done, .next]),
        .init(type: .start,
              observation: "your energy looks low right now.",
              suggestion: "do a 2-minute reset: breathe, stretch, drink water.",
              actions: [.startNow, .next]),
        .init(type: .remind,
              observation: "late workouts seem to push your bedtime later.",
              suggestion: "try moving your workout earlier today.",
              actions: [.remindMe, .save, .next]),
        .init(type: .reflect,
              observation: "you moved more than usual yesterday.",
              suggestion: "your energy looks steadier after active days.",
              actions: [.save, .writeNote, .next]),
        .init(type: .start,
              observation: "your focus usually improves after a short walk.",
              suggestion: "take a 7-minute walk without your phone.",
              actions: [.startNow, .done, .next]),
        .init(type: .remind,
              observation: "your evening energy crashes after long screen sessions.",
              suggestion: "take a screen break before dinner.",
              actions: [.remindMe, .next]),
        .init(type: .add,
              observation: "you have a heavy meeting block today.",
              suggestion: "protect a recovery gap after it.",
              actions: [.addToCalendar, .next]),
        .init(type: .start,
              observation: "you look mentally loaded today.",
              suggestion: "clear one small task in 10 minutes.",
              actions: [.startNow, .next]),
        .init(type: .reflect,
              observation: "quiet time seems to help you recharge.",
              suggestion: "notice how you feel after 5 minutes without input.",
              actions: [.writeNote, .save, .next]),
        .init(type: .remind,
              observation: "your sleep tends to suffer after late scrolling.",
              suggestion: "start wind down mode at 9:30 tonight.",
              actions: [.remindMe, .next]),
        .init(type: .start,
              observation: "your body has been still for a while.",
              suggestion: "move for 5 minutes. nothing heroic.",
              actions: [.startNow, .done, .next]),
        .init(type: .reflect,
              observation: "your best energy window is usually in the morning.",
              suggestion: "protect that window for deep work when you can.",
              actions: [.save, .addToCalendar, .next]),
        .init(type: .remind,
              observation: "your afternoon dips often follow low-movement mornings.",
              suggestion: "take a short walk before lunch.",
              actions: [.remindMe, .next]),
        .init(type: .start,
              observation: "you seem close to an energy crash.",
              suggestion: "pause for 3 minutes before pushing through.",
              actions: [.startNow, .next]),
        .init(type: .reflect,
              observation: "social time seems to recharge you on some days.",
              suggestion: "notice who gives you energy, not just attention.",
              actions: [.writeNote, .save, .next]),
        .init(type: .remind,
              observation: "your focus drops when meetings run back-to-back.",
              suggestion: "leave 5 minutes between calls when possible.",
              actions: [.addToCalendar, .save, .next]),
        .init(type: .start,
              observation: "you have a small window right now.",
              suggestion: "use it to reset, not scroll.",
              actions: [.startNow, .next]),
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

    /// The reflection currently displayed on the home speech card.
    var currentReflection: Reflection {
        Self.reflectionPool[reflectionIndex % Self.reflectionPool.count]
    }

    /// Energy percent shown on the home hero (baseline + snacks fed today).
    var homeEnergyPercent: Int {
        let base = Double(data.currentSnapshot().percent)
        return min(100, Int((base + energyBoost).rounded()))
    }

    /// Word + color mapping derived from `homeEnergyPercent`.
    var homeEnergyLevel: EnergyLevel {
        EnergyLevel.from(percent: homeEnergyPercent)
    }

    // MARK: Reflect — cycle through the pool

    /// Advance to the next Reflection (non-repeating).
    func advanceReflection() {
        reflectionIndex = (reflectionIndex + 1) % Self.reflectionPool.count
    }

    // MARK: Reflect — action handlers (per-card buttons)

    /// Save current reflection to Cards → Saved insights (optionally with a note).
    func saveCurrentReflection(note: String? = nil) {
        let r = currentReflection
        // Dedup: if this reflection is already saved without a note and we're
        // adding one, update it in place; otherwise append.
        if let idx = savedInsights.firstIndex(where: { $0.reflectionID == r.id }) {
            var copy = savedInsights[idx]
            if let note, !note.trimmingCharacters(in: .whitespaces).isEmpty {
                copy.note = note
            }
            savedInsights[idx] = copy
        } else {
            savedInsights.append(SavedInsight(
                reflectionID: r.id,
                observation: r.observation,
                suggestion: r.suggestion,
                note: (note?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 },
                savedAt: Date()
            ))
        }
    }

    func removeSavedInsight(_ item: SavedInsight) {
        savedInsights.removeAll { $0.id == item.id }
    }

    /// Remind me → append a Todo (reminder-kind) built from the suggestion.
    /// TODO: schedule a real local notification.
    func remindCurrentReflection() {
        let r = currentReflection
        todos.append(TodoItem(
            reflectionID: r.id,
            text: r.suggestion,
            kind: .reminder,
            createdAt: Date()
        ))
        reminderAdded = true
    }

    /// Add to calendar → append a Todo (calendar-kind) built from the suggestion.
    /// TODO: wire EventKit for a real calendar event.
    func addCurrentReflectionToCalendar() {
        let r = currentReflection
        todos.append(TodoItem(
            reflectionID: r.id,
            text: r.suggestion,
            kind: .calendar,
            createdAt: Date()
        ))
    }

    /// Positive feedback on a suggestion — mark done and advance.
    func markCurrentDone() {
        // For now we just advance; positive-feedback logging can hook here later.
        advanceReflection()
    }

    /// Toggle a todo's completed flag (used in Cards → To-dos).
    func toggleTodo(_ item: TodoItem) {
        guard let idx = todos.firstIndex(where: { $0.id == item.id }) else { return }
        todos[idx].completed.toggle()
    }

    func removeTodo(_ item: TodoItem) {
        todos.removeAll { $0.id == item.id }
    }

    // MARK: Feed — decrement stock, bump energy, blob love

    /// Feed a snack by ID. Decrements that snack's stock and adds a small
    /// energy boost (Apple +1, Walnut +0.5). Caller triggers the drop-to-blob
    /// treat animation and the rising heart in the view.
    func feed(snackID: Snack.ID) {
        guard let idx = snacks.firstIndex(where: { $0.id == snackID }),
              snacks[idx].stock > 0 else { return }
        snacks[idx].stock -= 1
        energyBoost = min(30, energyBoost + snacks[idx].energyBoost)
    }

    func addReminder() {
        reminderAdded = true
    }
}
