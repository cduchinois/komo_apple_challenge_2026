//  KomoApp.swift
//  Komo
//
//  Komo — a passive ambient wellness companion.
//  "a little light brought through the gaps of your day."
//
//  Native iOS 26 SwiftUI rebuild of the exported prototype. All data is mocked
//  behind EnergyDataProviding so a HealthKit source can be swapped in later.

import SwiftUI

@main
struct KomoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // The companion is the focus; keep a single phone-like canvas.
                .statusBarHidden(false)
        }
    }
}
