//  PermissionsManager.swift
//  Komo
//
//  Native permission prompts for the onboarding flow. Publishes the current
//  `PermissionState` for each domain so views (onboarding + Profile) can
//  render live status. Reads back the system's authoritative state on refresh.
//
//  - Notifications: real `UNUserNotificationCenter` request.
//  - Calendar: real `EKEventStore.requestFullAccessToEvents` (iOS 17+).
//    Requires `NSCalendarsFullAccessUsageDescription` in Info.plist — added
//    via project INFOPLIST_KEY. Missing that string crashes on first request.
//  - Health: HealthKit needs the HealthKit capability + entitlement enabled
//    in Signing & Capabilities. Until that is wired we simulate a grant so
//    the onboarding flow is demoable end-to-end. TODO: swap in the real
//    `HKHealthStore.requestAuthorization(toShare:read:)` once the entitlement
//    is added.
//  - Screen Time: iOS doesn't expose a runtime request for this — status is
//    reported as "not connected" in Profile.

import SwiftUI
import Observation
import EventKit
import UserNotifications
import HealthKit
#if canImport(UIKit)
import UIKit
#endif

/// Live authorization status the app tracks for each permission domain.
enum PermissionState: String, Equatable {
    case notDetermined
    case granted
    case denied

    var label: String {
        switch self {
        case .granted:      return "Connected"
        case .denied:       return "Not connected"
        case .notDetermined: return "Not connected"
        }
    }
}

@Observable
@MainActor
final class PermissionsManager {
    var health: PermissionState = .notDetermined
    var calendar: PermissionState = .notDetermined
    var notifications: PermissionState = .notDetermined
    /// Screen Time is deep-linked in Settings — no runtime prompt. Kept for
    /// Profile completeness.
    var screenTime: PermissionState = .notDetermined

    private let eventStore = EKEventStore()
    private let healthStore = HKHealthStore()

    /// Health-read set requested during onboarding — sleep + core cardio + steps.
    private var healthReadTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = []
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount) { s.insert(t) }
        return s
    }

    // MARK: - Health (real HealthKit request)

    /// Fires the native HealthKit authorization sheet.
    /// - Requires the HealthKit capability enabled in Signing & Capabilities
    ///   AND `NSHealthShareUsageDescription` in Info.plist. Without those,
    ///   the request returns an error immediately and no sheet appears.
    /// - HK does not tell us the user's per-type answer for `read` scopes,
    ///   so a successful `requestAuthorization` means "the sheet closed" and
    ///   we mark the state `.granted`. Real per-type authorization is read
    ///   later at query time.
    func requestHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            health = .denied
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: healthReadTypes)
            health = .granted
        } catch {
            // Missing entitlement or user cancelled — treat as denied.
            health = .denied
        }
    }

    // MARK: - Calendar (EventKit, iOS 17+)

    func requestCalendar() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            calendar = granted ? .granted : .denied
        } catch {
            calendar = .denied
        }
    }

    // MARK: - Notifications

    func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter
                .current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            notifications = granted ? .granted : .denied
        } catch {
            notifications = .denied
        }
    }

    // MARK: - Refresh (re-read system-authoritative state)

    func refreshAll() async {
        // Notifications
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notifications = .granted
        case .denied: notifications = .denied
        default: notifications = .notDetermined
        }
        // Calendar (iOS 17+)
        let calStatus = EKEventStore.authorizationStatus(for: .event)
        switch calStatus {
        case .fullAccess, .authorized: calendar = .granted
        case .denied, .restricted, .writeOnly: calendar = .denied
        case .notDetermined: calendar = .notDetermined
        @unknown default: calendar = .notDetermined
        }
        // Health: no read-status API — leave last known.
    }

    // MARK: - Deep link to Settings (for denied permissions)

    func openSettings() {
#if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
#endif
    }
}
