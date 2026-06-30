//  AppState.swift
//  Komo
//
//  The app's single source of navigation + onboarding + companion-config truth.
//  Uses the Observation framework (iOS 17+/26) so views update granularly.

import SwiftUI
import Observation

/// Every distinct screen in the prototype flow.
enum KomoScreen: Equatable {
    case splash
    case intro          // greeting text, auto-typed lines + "Let's go"
    case energy         // when do you have the most energy?
    case sleep          // how did you sleep? -> health/manual
    case drains         // what drains you? (max 2)
    case restores       // what restores you? (max 2)
    case loading        // bringing your companion to life
    case greeting       // welcome back (returning users)
    case main           // home companion screen
    case stats          // the passive-signals scroll
    case profile        // companion profile summary
    case customize      // edit name / surface / eyes / legs / world
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
    var energyType: String? = nil
    var sleepQuality: String? = nil
    var sleepAsked = false
    var sleepManual = false
    var sleepDuration = ""
    var drains: [String] = []
    var restores: [String] = []

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
    var greetStep = 0                 // 0...7, gates the intro lines + CTA

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

    /// Multi-select with a hard cap of 2 (selecting a 3rd drops the oldest) —
    /// matches the prototype's `toggleMulti`.
    func toggleMulti(_ keyPath: ReferenceWritableKeyPath<AppState, [String]>, _ label: String) {
        var arr = self[keyPath: keyPath]
        if let idx = arr.firstIndex(of: label) {
            arr.remove(at: idx)
        } else if arr.count >= 2 {
            arr = [arr[1], label]
        } else {
            arr.append(label)
        }
        self[keyPath: keyPath] = arr
    }

    func pickSleep(_ quality: String) {
        sleepQuality = quality
        sleepAsked = true
    }

    func resetOnboarding() {
        returning = false
        energyType = nil
        sleepQuality = nil
        sleepAsked = false
        sleepManual = false
        drains = []
        restores = []
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
