//  KomoApp.swift
//  Komo
//
//  Komo — a passive ambient wellness companion.
//  "a little light brought through the gaps of your day."
//
//  Native iOS 26 SwiftUI rebuild of the exported prototype. Real health data
//  is sourced from HealthKit via HealthKitDataProvider (EnergyDataProviding).

import SwiftUI
import SwiftData
import WidgetKit

@main
struct KomoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .statusBarHidden(false)
                .modelContainer(KomoSwiftDataStore.shared)
                .task {
                    // Request HealthKit (and Calendar) permissions on first launch.
                    // This triggers the system permission sheet automatically.
                    await HealthKitDataProvider.shared.requestPermissions()
                    // Pre-load today's data so stats are ready when the user
                    // reaches MainView (after onboarding or on returning visits).
                    await HealthKitDataProvider.shared.loadToday()
                    let snapshot = HealthKitDataProvider.shared.currentSnapshot()
                    WidgetEnergySnapshot.save(WidgetEnergySnapshot(
                        percent: snapshot.percent,
                        word: snapshot.word,
                        rechargedBy: snapshot.rechargedBy,
                        usedBy: snapshot.usedBy,
                        updatedAt: Date()
                    ))
                    WidgetCenter.shared.reloadTimelines(ofKind: "KomoEnergyWidget")
                    // Track days together for the Home header "Day N with KOMO".
                    let key = "komo_days_together"
                    UserDefaults.standard.set(
                        (UserDefaults.standard.integer(forKey: key) + 1),
                        forKey: key
                    )
                }
        }
    }
}
