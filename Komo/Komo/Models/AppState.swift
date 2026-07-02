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
    case intro                 // hook: typewriter greeting + "let's go"
    case energy                // Q1 — when do you feel most switched on?
    case now                   // Q2 — how's your energy right now?
    case sleep                 // Q sleep — did you sleep well last night?
    case healthPermission      // contextual health-data permission request
    case restores              // Q3 — what helps you recharge? (multi-select)
    case drains                // Q4 — what usually drains you? (multi-select)
    case calendarPermission    // conditional calendar permission (from Q4 drains)
    case loading               // charging: building your first check-in
    case greeting              // welcome back (returning users)
    case main                  // home companion screen
    case stats                 // the passive-signals scroll
    case cards                 // insights, todos & saved cards
    case profile               // companion profile summary
    case customize             // edit name / surface / eyes / legs / world
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

// MARK: - Topic (rule-based matcher vocabulary)
//
// Vocabulary shared between the reflection cards, the user's onboarding
// answers, and the InsightSequencer. Keeping it as one enum makes it easy
// to swap the rule-based matcher for a real reasoning engine later behind
// the same InsightSequencing protocol.

enum Topic: String, Equatable, Codable {
    // Drains vocabulary (Q4)
    case meetings, scrolling, poorSleep, intenseWork, socialPlans, commute
    // Recharges vocabulary (Q3)
    case walking, music, quietTime, workout, napSleep, outdoorActivities, timeWithFriends
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
    /// Tags used by the InsightSequencer to personalize the first two cards.
    /// Cards with an empty `topics` array are never picked by the matcher
    /// (they still appear in the general pool afterwards).
    let topics: [Topic]

    init(type: ReflectionType,
         observation: String,
         suggestion: String,
         actions: [ReflectionAction],
         topics: [Topic] = []) {
        self.type = type
        self.observation = observation
        self.suggestion = suggestion
        self.actions = actions
        self.topics = topics
    }

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

    // MARK: Injected data source (swappable)
    //
    // Provider precedence: real HealthKit-backed scorer (future) > onboarding
    // scorer > MockDataProvider. Starts as mock; upgraded to
    // `OnboardingEnergyScorer` as soon as we have onboarding answers.
    var data: EnergyDataProviding

    // MARK: Navigation
    var screen: KomoScreen = .splash
    var returning = false

    // MARK: Onboarding answers
    var userName: String = ""
    var energyType: String? = nil     // Q1 — peak time of day
    var energyNow: String? = nil      // Q2 — energy right now
    var sleepAnswer: String? = nil    // Q sleep — last-night rating
    var restores: [String] = []       // Q3 — what recharges (multi)
    var drains: [String] = []         // Q4 — what drains (multi)
    var auth = SignalAuth()           // legacy toggle state, unused by the new
                                      // contextual flow; kept until Profile
                                      // reads permissions from PermissionsManager
                                      // exclusively.

    /// Drains that should trigger the calendar-permission branch (6b).
    static let calendarBranchDrains: Set<String> = ["meetings", "intense work", "social plans"]

    /// True if the user's Q4 drains selection warrants the calendar permission
    /// screen right after DrainsView.
    var needsCalendarPermission: Bool {
        !drains.isEmpty && drains.contains { Self.calendarBranchDrains.contains($0) }
    }

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
    /// Cursor into the resolved pool (personalized order or plain pool).
    /// Persisted to UserDefaults so the sequence survives app relaunch.
    var reflectionIndex: Int = 0

    /// Onboarding-derived topic sets used by the InsightSequencer. Ordered by
    /// the user's selection order — the matcher walks them in that order.
    /// Persisted so the same personalization survives relaunches.
    var userDrainTopics: [Topic] = []
    var userRechargeTopics: [Topic] = []

    // MARK: Home state — Feed
    /// Points added to today's baseline energy by feeding. Capped at +30.
    var energyBoost: Double = 0
    /// Mutable snack inventory (stock decreases as the user feeds).
    var snacks: [Snack] = AppState.initialSnacks

    // MARK: Cards tab feeds
    var savedInsights: [SavedInsight] = []
    var todos: [TodoItem] = []

    init(data: EnergyDataProviding = MockDataProvider()) {
        let defaults = UserDefaults.standard

        // Read persisted values into locals first — Swift requires all stored
        // properties to be initialized before any read of `self`.
        let drainTopicsRaw = defaults.stringArray(forKey: Self.udkDrainTopics) ?? []
        let rechargeTopicsRaw = defaults.stringArray(forKey: Self.udkRechargeTopics) ?? []
        let restoredEnergyType  = defaults.string(forKey: Self.udkEnergyType)
        let restoredEnergyNow   = defaults.string(forKey: Self.udkEnergyNow)
        let restoredSleepAnswer = defaults.string(forKey: Self.udkSleepAnswer)

        // Reflect personalization + cursor.
        self.userDrainTopics    = drainTopicsRaw.compactMap(Topic.init(rawValue:))
        self.userRechargeTopics = rechargeTopicsRaw.compactMap(Topic.init(rawValue:))
        self.reflectionIndex    = defaults.integer(forKey: Self.udkReflectionIndex)

        // Onboarding scoring answers.
        self.energyType  = restoredEnergyType
        self.energyNow   = restoredEnergyNow
        self.sleepAnswer = restoredSleepAnswer

        // Provider precedence: OnboardingEnergyScorer if we have any onboarding
        // answers from a previous session, otherwise the mock provider.
        if restoredEnergyType != nil || restoredEnergyNow != nil || restoredSleepAnswer != nil {
            self.data = OnboardingEnergyScorer(
                energyNow: restoredEnergyNow,
                sleepAnswer: restoredSleepAnswer,
                energyType: restoredEnergyType,
                fallback: data
            )
        } else {
            self.data = data
        }
    }

    // MARK: - UserDefaults keys (personalization + cursor + score persistence)

    private static let udkDrainTopics     = "komo.userDrainTopics"
    private static let udkRechargeTopics  = "komo.userRechargeTopics"
    private static let udkReflectionIndex = "komo.reflectionIndex"
    private static let udkEnergyType      = "komo.energyType"        // Q1
    private static let udkEnergyNow       = "komo.energyNow"         // Q2
    private static let udkSleepAnswer     = "komo.sleepAnswer"       // Sleep Q
    private static let udkLastPercent     = "komo.lastPercent"       // widget/cold-start hint

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

    /// The Reflect pool — exactly 25 cards, in this order. Topic tags feed
    /// the InsightSequencer's rule-based matcher.
    static let reflectionPool: [Reflection] = [
        // 1
        .init(type: .add,
              observation: "your energy often dips after back-to-back meetings.",
              suggestion: "take 5 minutes outside before your next call.",
              actions: [.addToCalendar, .save, .next],
              topics: [.meetings]),
        // 2
        .init(type: .reflect,
              observation: "you slept 7+ hours on five nights this week.",
              suggestion: "your body seems to recover better when sleep is consistent.",
              actions: [.writeNote, .save, .next],
              topics: [.napSleep, .poorSleep]),
        // 3
        .init(type: .remind,
              observation: "afternoons feel foggy on days you eat a heavy lunch.",
              suggestion: "try a lighter lunch before 1pm today.",
              actions: [.remindMe, .save, .next],
              topics: []),
        // 4
        .init(type: .remind,
              observation: "your screen time usually climbs after 9pm.",
              suggestion: "dim your phone at 9 tonight and see how your sleep feels.",
              actions: [.remindMe, .save, .next],
              topics: [.scrolling, .poorSleep]),
        // 5
        .init(type: .start,
              observation: "you skipped your usual workout today.",
              suggestion: "try a quick 10-minute reset instead.",
              actions: [.startNow, .save, .next],
              topics: [.workout]),
        // 6
        .init(type: .start,
              observation: "mornings go better when you begin with focus instead of scrolling.",
              suggestion: "start a 10-minute focus session.",
              actions: [.startNow, .remindMe, .next],
              topics: [.scrolling]),
        // 7
        .init(type: .start,
              observation: "someone's been on your mind.",
              suggestion: "send a quick text or call them now.",
              actions: [.startNow, .done, .next],
              topics: [.timeWithFriends]),
        // 8
        .init(type: .add,
              observation: "your calendar looks packed before lunch.",
              suggestion: "block 10 minutes after your last morning meeting.",
              actions: [.addToCalendar, .next],
              topics: [.meetings, .intenseWork]),
        // 9
        .init(type: .remind,
              observation: "you tend to sit for long stretches on workdays.",
              suggestion: "stand up for 3 minutes before your next session.",
              actions: [.remindMe, .done, .next],
              topics: [.intenseWork]),
        // 10
        .init(type: .start,
              observation: "your energy looks low right now.",
              suggestion: "do a 2-minute reset: breathe, stretch, drink water.",
              actions: [.startNow, .next],
              topics: []),
        // 11
        .init(type: .remind,
              observation: "late workouts seem to push your bedtime later.",
              suggestion: "try moving your workout earlier today.",
              actions: [.remindMe, .save, .next],
              topics: [.workout, .poorSleep]),
        // 12
        .init(type: .reflect,
              observation: "you moved more than usual yesterday.",
              suggestion: "your energy looks steadier after active days.",
              actions: [.save, .writeNote, .next],
              topics: [.workout, .walking]),
        // 13
        .init(type: .start,
              observation: "your focus usually improves after a short walk.",
              suggestion: "take a 7-minute walk without your phone.",
              actions: [.startNow, .done, .next],
              topics: [.walking]),
        // 14
        .init(type: .remind,
              observation: "your evening energy crashes after long screen sessions.",
              suggestion: "take a screen break before dinner.",
              actions: [.remindMe, .next],
              topics: [.scrolling]),
        // 15
        .init(type: .add,
              observation: "you have a heavy meeting block today.",
              suggestion: "protect a recovery gap after it.",
              actions: [.addToCalendar, .next],
              topics: [.meetings]),
        // 16
        .init(type: .start,
              observation: "you look mentally loaded today.",
              suggestion: "clear one small task in 10 minutes.",
              actions: [.startNow, .next],
              topics: [.intenseWork]),
        // 17
        .init(type: .reflect,
              observation: "quiet time seems to help you recharge.",
              suggestion: "notice how you feel after 5 minutes without input.",
              actions: [.writeNote, .save, .next],
              topics: [.quietTime]),
        // 18
        .init(type: .remind,
              observation: "your sleep tends to suffer after late scrolling.",
              suggestion: "start wind down mode at 9:30 tonight.",
              actions: [.remindMe, .next],
              topics: [.scrolling, .poorSleep]),
        // 19
        .init(type: .start,
              observation: "your body has been still for a while.",
              suggestion: "move for 5 minutes. nothing heroic.",
              actions: [.startNow, .done, .next],
              topics: [.walking, .workout]),
        // 20
        .init(type: .reflect,
              observation: "your best energy window is usually in the morning.",
              suggestion: "protect that window for deep work when you can.",
              actions: [.save, .addToCalendar, .next],
              topics: [.intenseWork]),
        // 21
        .init(type: .remind,
              observation: "your afternoon dips often follow low-movement mornings.",
              suggestion: "take a short walk before lunch.",
              actions: [.remindMe, .next],
              topics: [.walking]),
        // 22
        .init(type: .start,
              observation: "you seem close to an energy crash.",
              suggestion: "pause for 3 minutes before pushing through.",
              actions: [.startNow, .next],
              topics: []),
        // 23
        .init(type: .reflect,
              observation: "social time seems to recharge you on some days.",
              suggestion: "notice who gives you energy, not just attention.",
              actions: [.writeNote, .save, .next],
              topics: [.timeWithFriends, .socialPlans]),
        // 24
        .init(type: .remind,
              observation: "your focus drops when meetings run back-to-back.",
              suggestion: "leave 5 minutes between calls when possible.",
              actions: [.addToCalendar, .save, .next],
              topics: [.meetings]),
        // 25
        .init(type: .start,
              observation: "you have a small window right now.",
              suggestion: "use it to reset, not scroll.",
              actions: [.startNow, .next],
              topics: [.scrolling]),
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
        sleepAnswer = nil
        drains = []
        restores = []
        auth = SignalAuth()
        companionName = ""
    }

    // MARK: - Onboarding → topics mapping

    /// Map a Q4 drain selection string to a Topic (or nil if it has no mapping).
    static func drainTopic(from selection: String) -> Topic? {
        switch selection {
        case "meetings":         return .meetings
        case "screen time":      return .scrolling
        case "poor sleep":       return .poorSleep
        case "intense work":     return .intenseWork
        case "social plans":     return .socialPlans
        case "commute / travel": return .commute
        default:                 return nil    // "sitting too long", "not sure yet"
        }
    }

    /// Map a Q3 recharge selection string to a Topic (or nil if none).
    static func rechargeTopic(from selection: String) -> Topic? {
        switch selection {
        case "walking":     return .walking
        case "music":       return .music
        case "quiet time":  return .quietTime
        case "workout":     return .workout
        case "nap / sleep": return .napSleep
        case "outside":     return .outdoorActivities
        case "talking":     return .timeWithFriends
        default:            return nil     // "not sure yet"
        }
    }

    /// Called when the user finishes onboarding (right before Loading).
    /// - Snapshots drain/recharge topics for the Reflect matcher.
    /// - Persists Q1/Q2/sleep so the OnboardingEnergyScorer works on cold launch.
    /// - Swaps `data` for an OnboardingEnergyScorer wrapping the previous provider.
    /// - Caches the freshly computed percent for a widget / cold-start hint.
    /// - Resets the Reflect cursor so the personalized sequence starts at card 1.
    func completeOnboarding() {
        userDrainTopics    = drains.compactMap(Self.drainTopic(from:))
        userRechargeTopics = restores.compactMap(Self.rechargeTopic(from:))
        reflectionIndex = 0

        // Wrap the current provider in the onboarding scorer so Home + the (i)
        // sheet use the rule-based score from now on. If it's already wrapped
        // (relaunch after onboarding), we re-wrap with the freshest answers.
        let baseProvider: EnergyDataProviding = (data as? OnboardingEnergyScorer)?.fallback ?? data
        let scorer = OnboardingEnergyScorer(
            energyNow: energyNow,
            sleepAnswer: sleepAnswer,
            energyType: energyType,
            fallback: baseProvider
        )
        data = scorer

        let defaults = UserDefaults.standard
        defaults.set(userDrainTopics.map(\.rawValue),    forKey: Self.udkDrainTopics)
        defaults.set(userRechargeTopics.map(\.rawValue), forKey: Self.udkRechargeTopics)
        defaults.set(reflectionIndex,                     forKey: Self.udkReflectionIndex)
        defaults.set(energyType,                          forKey: Self.udkEnergyType)
        defaults.set(energyNow,                           forKey: Self.udkEnergyNow)
        defaults.set(sleepAnswer,                         forKey: Self.udkSleepAnswer)

        // Cache the freshly computed percent for cold-start / widget hints.
        defaults.set(scorer.currentSnapshot().percent, forKey: Self.udkLastPercent)
    }

    // MARK: Home-screen state derivations

    /// Personalized pool if the user has onboarding topics, else the plain pool.
    /// Same output feeds both the Home insight card and the Reflect button so
    /// they stay in sync.
    /// TODO: replace `RuleBasedInsightSequencer` with the Foundation Models
    ///       reasoning engine (same InsightSequencing protocol).
    var resolvedPool: [Reflection] {
        guard !userDrainTopics.isEmpty || !userRechargeTopics.isEmpty else {
            return Self.reflectionPool
        }
        let sequencer: InsightSequencing = RuleBasedInsightSequencer()
        return sequencer.orderedPool(from: Self.reflectionPool,
                                     drains: userDrainTopics,
                                     recharges: userRechargeTopics)
    }

    /// The reflection currently displayed on the home speech card.
    var currentReflection: Reflection {
        let pool = resolvedPool
        return pool[reflectionIndex % pool.count]
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

    /// Advance to the next Reflection (non-repeating). Uses the resolved pool
    /// count so cursor arithmetic matches whatever pool the UI is showing.
    /// Persists to UserDefaults so the position survives relaunch.
    func advanceReflection() {
        let count = resolvedPool.count
        reflectionIndex = (reflectionIndex + 1) % max(1, count)
        UserDefaults.standard.set(reflectionIndex, forKey: Self.udkReflectionIndex)
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
