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
    case favorites      // saved companion moments
    case profile        // companion profile summary
    case customize      // edit name / surface / eyes / legs / world
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
    var bubbleShown = false
    var bubbleIndex = 0
    var liked = false
    var reminderAdded = false

    init(data: EnergyDataProviding = MockDataProvider()) {
        self.data = data
    }

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

    /// Unlimited multi-select, but "not sure yet" is exclusive: picking it clears
    /// the rest, and picking anything else clears it — matches the prototype's
    /// `toggleMulti`.
    func toggleMulti(_ keyPath: ReferenceWritableKeyPath<AppState, [String]>, _ label: String) {
        var arr = self[keyPath: keyPath]
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
        self[keyPath: keyPath] = arr
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

    // MARK: Main-screen interactions

    /// Tap the companion -> reveal / cycle the speech-bubble insight.
    func tapCompanion() {
        bubbleShown = true
        bubbleIndex += 1
    }

    var currentInsightLine: String {
        let lines = data.insightLines(for: tone)
        guard !lines.isEmpty else { return "" }
        return lines[bubbleIndex % lines.count]
    }

    func toggleLike() { liked.toggle() }

    func addReminder() {
        reminderAdded = true
    }
}
