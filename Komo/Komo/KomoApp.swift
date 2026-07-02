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
                    // Track days together for the Home header "Day N with KOMO".
                    // Only increment once per calendar day.
                    let key      = "komo_days_together"
                    let dateKey  = "komo_days_last_date"
                    let today    = Calendar.current.startOfDay(for: Date())
                    let lastDate = UserDefaults.standard.object(forKey: dateKey) as? Date
                    if lastDate == nil || !Calendar.current.isDate(lastDate!, inSameDayAs: today) {
                        UserDefaults.standard.set(
                            UserDefaults.standard.integer(forKey: key) + 1,
                            forKey: key
                        )
                        UserDefaults.standard.set(today, forKey: dateKey)
                    }
                }
        }
    }
}
