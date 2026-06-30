//
//  KomoApp.swift
//  Komo
//
//  Created by Sacha Morin on 24/06/2026.
//

import AppIntents
import SwiftData
import SwiftUI

@main
struct KomoApp: App {
    @StateObject private var engine = HealthAvatarEngine.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// SwiftData container pour persister les DailySnapshot (baseline personnelle)
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([DailySnapshot.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        KomoShortcutsProvider.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(engine)
                    .task {
                        // Inject modelContext into engine for SwiftData persistence
                        engine.modelContext = sharedModelContainer.mainContext
                        await engine.requestPermissions()  // ← cette ligne doit être là
                        await SmartNotificationManager.shared.requestAuthorization()
                    }
            } else {
                OnboardingWelcomeView()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
