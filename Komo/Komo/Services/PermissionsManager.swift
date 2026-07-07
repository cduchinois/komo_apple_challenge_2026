//  PermissionsManager.swift
//  Komo
//
//  Native permission prompts for the onboarding flow. Publishes the current
//  `PermissionState` for each domain so views (onboarding + Profile) can
//  render live status. Reads back the system's authoritative state on refresh.
//
//  Health and Calendar prompts are only fired from explicit UI actions
//  (HealthPermissionView / CalendarPermissionView / Profile), never on launch.

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

    var label: String { L10n.permissionState(self) }
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

    // MARK: - Health (native HealthKit sheet)

    /// Fires the native HealthKit authorization sheet.
    /// Requires the HealthKit capability + `NSHealthShareUsageDescription`.
    func requestHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            health = .denied
            return
        }
        do {
            try await HealthKitManager.shared.requestHealthAuthorization()
            health = .granted
        } catch {
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
