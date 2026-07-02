//  AppState.swift
//  Komo
//
//  The app's single source of navigation + onboarding + companion-config truth.
//  Uses the Observation framework (iOS 17+/26) so views update granularly.

import SwiftUI
import Observation
import WidgetKit
import SwiftData

/// Every distinct screen in the prototype flow.
/// Onboarding order: splash → intro(hook) → energy → now → restores → drains →
/// signals → loading → main.
enum KomoScreen: String, Codable, Equatable {
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
        L10n.energyLevel(self)
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

enum ReflectionType: String, Codable, Equatable {
    case add       // sits on the calendar
    case reflect   // an observation, no active step
    case remind    // a nudge to schedule
    case start     // an immediate move
}

// MARK: - Topic (rule-based matcher vocabulary)

enum Topic: String, Equatable, Codable {
    case meetings, scrolling, poorSleep, intenseWork, socialPlans, commute
    case walking, music, quietTime, workout, napSleep, outdoorActivities, timeWithFriends
}

enum ReflectionAction: String, Identifiable, Codable, Equatable, CaseIterable {
    case addToCalendar
    case save
    case writeNote
    case remindMe
    case startNow
    case done
    case next

    var id: String { rawValue }

    var label: String { L10n.reflectionAction(self) }

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

struct SavedInsight: Identifiable, Codable, Equatable {
    var id = UUID()
    let reflectionID: UUID
    let observation: String
    let suggestion: String
    var note: String?
    let savedAt: Date
}

enum TodoKind: String, Codable, Equatable {
    case reminder  // from Remind me
    case calendar  // from Add to calendar
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    let reflectionID: UUID
    let text: String
    let kind: TodoKind
    var completed: Bool = false
    let createdAt: Date
}

// NOTE: Snacks replaced by stars — see `starBalance` + `feedKomoWithStar()`.

/// On-device signal permissions toggled on the Signals screen.
/// Card order matches the prototype: health, calendar, screen, notify.
struct SignalAuth: Codable, Equatable {
    var health = false
    var calendar = false
    var screen = false
    var notify = false

    var anyOn: Bool { health || calendar || screen || notify }
    var allOn: Bool { health && calendar && screen && notify }
}

@MainActor
@Observable
final class AppState {

    // MARK: Injected data source (swappable)
    //
    // Provider precedence: real HealthKit-backed scorer (future) > onboarding
    // scorer > MockDataProvider. Starts as mock; upgraded to
    // `OnboardingEnergyScorer` as soon as we have onboarding answers.
    var data: EnergyDataProviding

    // MARK: Navigation
    var screen: KomoScreen = .splash { didSet { persistAfterChange() } }
    var returning = false { didSet { persistAfterChange() } }

    // MARK: Onboarding answers
    var userName: String = "" { didSet { persistAfterChange() } }
    var energyType: String? = nil { didSet { persistAfterChange() } }
    var energyNow: String? = nil { didSet { persistAfterChange() } }
    var sleepAnswer: String? = nil { didSet { persistAfterChange() } }
    var restores: [String] = [] { didSet { persistAfterChange() } }
    var drains: [String] = [] { didSet { persistAfterChange() } }
    var auth = SignalAuth() { didSet { persistAfterChange() } }

    static let calendarBranchDrains: Set<String> = ["meetings", "intense work", "social plans"]

    var needsCalendarPermission: Bool {
        !drains.isEmpty && drains.contains { Self.calendarBranchDrains.contains($0) }
    }

    // MARK: Companion configuration
    var characterIndex = 1 { didSet { persistAfterChange() } }            // default: Moku (calm)
    var companionName = "" { didSet { persistAfterChange() } }
    var blobStyle: BlobStyle = .glossy { didSet { persistAfterChange() } }
    var eyes: EyeStyle = .cartoon { didSet { persistAfterChange() } }
    var legs: LegStyle = .stubs { didSet { persistAfterChange() } }
    var tone: CompanionTone = CompanionTone.all[0] { didSet { persistAfterChange() } }
    var worldIndex = 0 { didSet { persistAfterChange() } }
    /// Daily energy hue that tints the whole creature (150 = green in the source).
    var dailyHue: Double = 150 { didSet { persistAfterChange() } }

    // MARK: Transient UI state
    var loadingPct: Double = 0 { didSet { persistAfterChange() } }
    var reminderAdded = false { didSet { persistAfterChange() } }

    // MARK: Home state — Reflect
    var reflectionIndex: Int = 0 { didSet { persistAfterChange() } }

    /// Onboarding-derived topic sets used by the InsightSequencer. Ordered by
    /// the user's selection order — the matcher walks them in that order.
    /// Persisted so the same personalization survives relaunches.
    var userDrainTopics: [Topic] = []
    var userRechargeTopics: [Topic] = []

    // MARK: Home state — Feed
    var energyBoost: Double = 0 { didSet { persistAfterChange() } }

    // MARK: Stars — feed currency (earned from Recharge / FocusTimer)
    var starBalance: Int = 2 { didSet { persistAfterChange() } }
    var starsFedTotal: Int = 0 { didSet { persistAfterChange() } }

    // MARK: Cards tab feeds
    var savedInsights: [SavedInsight] = [] { didSet { persistAfterChange() } }
    var todos: [TodoItem] = [] { didSet { persistAfterChange() } }

    @ObservationIgnored private var isRestoringPersistedState = false
    @ObservationIgnored private let persistenceStore = AppStatePersistenceStore()

    init(data: EnergyDataProviding = MockDataProvider()) {
        self.data = data
        restorePersistedState()
    }

    // MARK: Persistence (SwiftData)

    func saveNow() {
        guard !isRestoringPersistedState else { return }
        persistenceStore.save(snapshotForPersistence())
    }

    private func persistAfterChange() {
        guard !isRestoringPersistedState else { return }
        saveNow()
    }

    private func restorePersistedState() {
        guard let persisted = persistenceStore.load() else { return }
        isRestoringPersistedState = true
        apply(persisted)
        isRestoringPersistedState = false
    }

    private func snapshotForPersistence() -> PersistedAppState {
        PersistedAppState(
            screen: screen,
            returning: returning,
            userName: userName,
            energyType: energyType,
            energyNow: energyNow,
            sleepAnswer: sleepAnswer,
            restores: restores,
            drains: drains,
            auth: auth,
            characterIndex: characterIndex,
            companionName: companionName,
            blobStyle: blobStyle,
            eyes: eyes,
            legs: legs,
            toneID: tone.id,
            worldIndex: worldIndex,
            dailyHue: dailyHue,
            loadingPct: loadingPct,
            reminderAdded: reminderAdded,
            reflectionIndex: reflectionIndex,
            energyBoost: energyBoost,
            starBalance: starBalance,
            starsFedTotal: starsFedTotal,
            userDrainTopics: userDrainTopics.map(\.rawValue),
            userRechargeTopics: userRechargeTopics.map(\.rawValue),
            savedInsights: savedInsights,
            todos: todos
        )
    }

    private func apply(_ persisted: PersistedAppState) {
        screen = persisted.screen
        returning = persisted.returning
        userName = persisted.userName
        energyType = persisted.energyType
        energyNow = persisted.energyNow
        sleepAnswer = persisted.sleepAnswer
        restores = persisted.restores
        drains = persisted.drains
        auth = persisted.auth
        characterIndex = CompanionCharacter.all.indices.contains(persisted.characterIndex) ? persisted.characterIndex : 1
        companionName = persisted.companionName
        blobStyle = persisted.blobStyle
        eyes = persisted.eyes
        legs = persisted.legs
        tone = CompanionTone.all.first { $0.id == persisted.toneID } ?? CompanionTone.all[0]
        worldIndex = CompanionWorld.all.contains { $0.id == persisted.worldIndex } ? persisted.worldIndex : 0
        dailyHue = persisted.dailyHue
        loadingPct = persisted.loadingPct
        reminderAdded = persisted.reminderAdded
        reflectionIndex = max(0, persisted.reflectionIndex)
        energyBoost = min(30, max(0, persisted.energyBoost))
        starBalance = max(0, persisted.starBalance)
        starsFedTotal = max(0, persisted.starsFedTotal)
        userDrainTopics = persisted.userDrainTopics.compactMap(Topic.init(rawValue:))
        userRechargeTopics = persisted.userRechargeTopics.compactMap(Topic.init(rawValue:))
        savedInsights = persisted.savedInsights
        todos = persisted.todos

        // Upgrade data provider when onboarding answers are already known.
        if energyType != nil || energyNow != nil || sleepAnswer != nil {
            self.data = OnboardingEnergyScorer(
                energyNow: energyNow,
                sleepAnswer: sleepAnswer,
                energyType: energyType,
                fallback: data
            )
        }
    }

    private func persistCurrentEnergyCheckIn() {
        persistenceStore.saveEnergyCheckIn(
            snapshot: data.currentSnapshot(),
            energyType: energyType,
            energyNow: energyNow,
            restores: restores,
            drains: drains
        )
    }


    /// Requests HealthKit permissions, loads today's data, and switches the
    /// active data provider to the real HealthKit-backed scorer.
    @MainActor
    func completeOnboardingLoad() async {
        // Load only — Health/Calendar prompts are triggered from onboarding buttons.
        await HealthKitDataProvider.shared.loadToday()
        // Only switch to HealthKit provider if the load succeeded and we have data.
        if HealthKitDataProvider.shared.hasData {
            self.data = HealthKitDataProvider.shared
            reflectionIndex = 0
        }
        publishWidgetEnergySnapshot()
        persistCurrentEnergyCheckIn()
        saveNow()
    }

    /// Loads fresh HealthKit data and switches AppState.data to the real provider.
    /// Call this on every foreground launch so returning users always see live data.
    @MainActor
    func refreshFromHealthKit() async {
        await HealthKitDataProvider.shared.loadToday()
        if HealthKitDataProvider.shared.hasData {
            self.data = HealthKitDataProvider.shared
            reflectionIndex = 0
        }
        publishWidgetEnergySnapshot()
    }

    // MARK: - UserDefaults keys (personalization + cursor + score persistence)

    private static let udkDrainTopics     = "komo.userDrainTopics"
    private static let udkRechargeTopics  = "komo.userRechargeTopics"
    private static let udkReflectionIndex = "komo.reflectionIndex"
    private static let udkEnergyType      = "komo.energyType"        // Q1
    private static let udkEnergyNow       = "komo.energyNow"         // Q2
    private static let udkSleepAnswer     = "komo.sleepAnswer"       // Sleep Q
    private static let udkLastPercent     = "komo.lastPercent"       // widget/cold-start hint
    private static let udkStarBalance     = "komo.starBalance"       // spendable stars
    private static let udkStarsFedTotal   = "komo.starsFedTotal"     // lifetime feed count → level

    // MARK: Static demo content
    //
    // (Stars are a KOMO-only currency now — feeding no longer touches the
    // user's energy pipeline, so no energy-per-star constant is needed here.)

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
    static var reflectionPool: [Reflection] { ReflectionCatalog.staticPool }

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
        returning = true

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

    /// Static or onboarding-sequenced pool when HealthKit has no personalized cards.
    private var fallbackReflectionPool: [Reflection] {
        guard !userDrainTopics.isEmpty || !userRechargeTopics.isEmpty else {
            return Self.reflectionPool
        }
        let sequencer: InsightSequencing = RuleBasedInsightSequencer()
        return sequencer.orderedPool(from: Self.reflectionPool,
                                     drains: userDrainTopics,
                                     recharges: userRechargeTopics)
    }

    /// Reflection pool shown on Home. HealthKit/AI cards lead; the static pool is
    /// appended so Next always has cards to cycle through (even when HealthKit
    /// returns a single personalized insight).
    var resolvedPool: [Reflection] {
        let personalized = data.personalizedReflections()
        let fallback = fallbackReflectionPool
        guard !personalized.isEmpty else { return fallback }

        var pool = personalized
        for card in fallback where !pool.contains(where: { $0.observation == card.observation }) {
            pool.append(card)
        }
        return pool
    }

    /// The reflection currently displayed on the home speech card.
    /// Prefers data-personalized cards from HealthKit; falls back to the
    /// static pool so the card is never empty.
    var currentReflection: Reflection {
        let pool = resolvedPool
        guard !pool.isEmpty else { return Self.reflectionPool[0] }
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

    /// Publish the exact Home energy value into the App Group so WidgetKit can
    /// render the same score outside the app process.
    func publishWidgetEnergySnapshot() {
        let snapshot = data.currentSnapshot()
        let reflection = currentReflection
        WidgetEnergySnapshot.save(WidgetEnergySnapshot(
            percent: homeEnergyPercent,
            word: homeEnergyLevel.word,
            rechargedBy: snapshot.rechargedBy,
            usedBy: snapshot.usedBy,
            insightText: reflection.observation,
            insightSuggestion: reflection.suggestion,
            updatedAt: Date()
        ))
        WidgetCenter.shared.reloadTimelines(ofKind: "KomoEnergyWidget")
    }

    // MARK: Reflect — cycle through the pool

    /// Advance to the next Reflection (non-repeating). Uses the resolved pool
    /// count so cursor arithmetic matches whatever pool the UI is showing.
    /// Persists to UserDefaults so the position survives relaunch.
    func advanceReflection() {
        reflectionIndex = (reflectionIndex + 1) % max(1, resolvedPool.count)
        publishWidgetEnergySnapshot()
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

    // MARK: Stars — earn (Recharge / Focus) + spend (Feed)

    /// Grants stars for a completed Recharge / FocusTimer session. Persists.
    func earnStar(_ count: Int = 1) {
        guard count > 0 else { return }
        starBalance += count
        UserDefaults.standard.set(starBalance, forKey: Self.udkStarBalance)
    }

    /// Try to spend one star to feed KOMO. Returns `true` if the star was
    /// available and spent; the caller then plays the drop → blob animation.
    /// Feeding KOMO is purely for KOMO: it does NOT touch the user's energy
    /// pipeline (`energyBoost` / `homeEnergyPercent`). It only decrements the
    /// star balance and bumps the lifetime feed counter that drives KOMO's
    /// level.
    @discardableResult
    func feedKomoWithStar() -> Bool {
        guard starBalance > 0 else { return false }
        starBalance -= 1
        starsFedTotal += 1
        let defaults = UserDefaults.standard
        defaults.set(starBalance,   forKey: Self.udkStarBalance)
        defaults.set(starsFedTotal, forKey: Self.udkStarsFedTotal)
        return true
    }

    // MARK: KOMO level (derived from feeds + days together)

    /// Integer level starting at 1, increasing every 3 combined
    /// (feed events + days together) units.
    var komoLevel: Int {
        1 + (starsFedTotal + max(0, currentDaysTogether - 1)) / 3
    }

    /// Progress toward the next level in 0...1.
    var komoLevelProgress: Double {
        let total = starsFedTotal + max(0, currentDaysTogether - 1)
        let intoLevel = total % 3
        return Double(intoLevel) / 3.0
    }

    /// Days together — placeholder for the real onboarding-anniversary count.
    /// TODO: wire real `daysTogether` from a persisted onboarding date.
    var currentDaysTogether: Int { 1 }

    func addReminder() {
        reminderAdded = true
    }
}

private struct PersistedAppState: Codable {
    var version: Int = 2
    var screen: KomoScreen
    var returning: Bool
    var userName: String
    var energyType: String?
    var energyNow: String?
    var sleepAnswer: String?
    var restores: [String]
    var drains: [String]
    var auth: SignalAuth
    var characterIndex: Int
    var companionName: String
    var blobStyle: BlobStyle
    var eyes: EyeStyle
    var legs: LegStyle
    var toneID: String
    var worldIndex: Int
    var dailyHue: Double
    var loadingPct: Double
    var reminderAdded: Bool
    var reflectionIndex: Int
    var energyBoost: Double
    var starBalance: Int = 2
    var starsFedTotal: Int = 0
    var userDrainTopics: [String] = []
    var userRechargeTopics: [String] = []
    var savedInsights: [SavedInsight]
    var todos: [TodoItem]
}

@MainActor
private struct AppStatePersistenceStore {
    private let appStateKey = "primary"

    func load() -> PersistedAppState? {
        do {
            var descriptor = FetchDescriptor<AppStateRecord>(
                predicate: #Predicate { $0.key == appStateKey }
            )
            descriptor.fetchLimit = 1
            guard let record = try KomoSwiftDataStore.context.fetch(descriptor).first else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PersistedAppState.self, from: record.payload)
        } catch {
            print("Failed to load AppState from SwiftData: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ state: PersistedAppState) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = try encoder.encode(state)

            var descriptor = FetchDescriptor<AppStateRecord>(
                predicate: #Predicate { $0.key == appStateKey }
            )
            descriptor.fetchLimit = 1
            let context = KomoSwiftDataStore.context
            if let record = try context.fetch(descriptor).first {
                record.payload = payload
                record.updatedAt = Date()
            } else {
                context.insert(AppStateRecord(key: appStateKey, payload: payload))
            }
            try context.save()
        } catch {
            print("Failed to persist AppState with SwiftData: \(error.localizedDescription)")
        }
    }

    func saveEnergyCheckIn(
        snapshot: EnergySnapshot,
        energyType: String?,
        energyNow: String?,
        restores: [String],
        drains: [String]
    ) {
        do {
            let context = KomoSwiftDataStore.context
            context.insert(EnergyCheckInRecord(
                percent: snapshot.percent,
                word: snapshot.word,
                rechargedBy: snapshot.rechargedBy,
                usedBy: snapshot.usedBy,
                headlineInsight: snapshot.headlineInsight,
                energyType: energyType,
                energyNow: energyNow,
                restores: restores,
                drains: drains
            ))
            try context.save()
        } catch {
            print("Failed to persist energy check-in with SwiftData: \(error.localizedDescription)")
        }
    }
}
