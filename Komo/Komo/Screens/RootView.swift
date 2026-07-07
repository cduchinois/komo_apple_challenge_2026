//  RootView.swift
//  Komo
//
//  Hosts the global background and switches between screens. On les écrans
//  principaux (main/stats/profile/customize), on utilise un TabView natif
//  iOS 26 avec Liquid Glass automatique — exactement comme Apple Music.
//  Sur les écrans onboarding, on garde la transition cross-fade.

import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var app = AppState(data: HealthKitDataProvider.shared)
    @State private var permissions = PermissionsManager()
    @Namespace private var blob

    /// True quand on est dans le flux principal (post-onboarding).
    private var isMainFlow: Bool {
        switch app.screen {
        case .main, .stats, .cards, .profile, .customize: return true
        default: return false
        }
    }

    /// Non-main screens get the darkening veil so white text stays legible.
    private var darken: Bool { app.screen != .main }

    /// Le TabView pilote directement `app.screen`. Stats vit dans l'onglet Home
    /// (avec back-button), donc on le mappe à `.main` pour la sélection d'onglet.
    /// Customize est atteignable depuis Profile — pas d'onglet dédié.
    private var tabSelection: Binding<KomoScreen> {
        Binding(
            get: {
                switch app.screen {
                case .stats:     return .main
                case .customize: return .profile
                default:         return app.screen
                }
            },
            set: { app.go($0) }
        )
    }

    var body: some View {
        // KomoBackground is applied per-tab via `.komoScreen(background:)`.
        // Because KomoBackground itself now calls `.ignoresSafeArea()` (see
        // Effects.swift), the underlying Image's layout frame is genuinely
        // full-screen — `.scaledToFill()` computes against the ignored-safe-
        // area frame so the forest photo covers everything, including the
        // strip below the tab bar that used to leak the cream fallback.
        Group {
            if isMainFlow {
                TabView(selection: tabSelection) {
                    Tab("Home", systemImage: "house.fill", value: KomoScreen.main) {
                        Group {
                            if app.screen == .stats {
                                StatsView(namespace: blob)
                            } else {
                                MainView(namespace: blob)
                            }
                        }
                        .komoScreen(background: KomoBackground(darken: darken))
                    }
                    Tab("Cards", systemImage: "square.stack.fill", value: KomoScreen.cards) {
                        CardsView(namespace: blob)
                            .komoScreen(background: KomoBackground(darken: darken))
                    }
                    Tab("Profile", systemImage: "person.crop.circle", value: KomoScreen.profile) {
                        // TODO: expose Customize as a row inside ProfileView
                        // instead of a dedicated tab. For now, .customize
                        // still routes here.
                        Group {
                            if app.screen == .customize {
                                CustomizeView(namespace: blob)
                            } else {
                                ProfileView(namespace: blob)
                            }
                        }
                        .komoScreen(background: KomoBackground(darken: darken))
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                // Hide the tab bar's opaque material so the per-tab
                // KomoBackground bleeds all the way to the compat frame's
                // bottom edge (removes the residual band under the tab bar).
                .toolbarBackground(.hidden, for: .tabBar)
                .transition(.opacity)
            } else {
                onboardingScreen
                    .transition(.opacity)
                    .komoScreen(background: KomoBackground(darken: darken))
            }
        }
        .environment(app)
        .environment(permissions)
        .animation(.easeInOut(duration: 0.45), value: app.screen)
        .preferredColorScheme(.light)
        .task {
            #if DEBUG
            // Skip health / notification prompts under the iPad-layout screenshot script.
            if CommandLine.arguments.contains("-KOMO_NO_STARTUP_TASKS") { return }
            #endif
            await permissions.refreshAll()
            // Sync HealthKit only for returning users already in the main app.
            // Permission sheets are shown from onboarding buttons, not on launch.
            if isMainFlow {
                await app.refreshFromHealthKit()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.saveNow() }
        }
        .onChange(of: app.screen) { _, screen in
            if screen == .main {
                app.publishWidgetEnergySnapshot()
                Task { await app.refreshFromHealthKit() }
            }
        }
    }

    @ViewBuilder
    private var onboardingScreen: some View {
        switch app.screen {
        case .splash:              SplashView(namespace: blob)
        case .intro:               IntroView(namespace: blob)
        case .energy:              EnergyView(namespace: blob)
        case .now:                 NowView(namespace: blob)
        case .sleep:               SleepView(namespace: blob)
        case .healthPermission:    HealthPermissionView(namespace: blob)
        case .restores:            RestoresView(namespace: blob)
        case .drains:              DrainsView(namespace: blob)
        case .calendarPermission:  CalendarPermissionView(namespace: blob)
        case .loading:             LoadingView(namespace: blob)
        case .greeting:            GreetingView(namespace: blob)
        case .main, .stats, .cards, .profile, .customize:
            MainView(namespace: blob)   // safety fallback — main-flow handled above
        }
    }
}

#Preview {
    RootView()
}

// MARK: - iPad rendering
//
// KOMO is an iPhone-first app. iPadOS 26 runs iPhone-only apps full-screen
// (no automatic letterbox) inside a compat frame that collapses the top
// safe-area to ~20pt and stretches iPhone-authored layouts. `komoScreen()`
// constrains the foreground layout to iPhone Pro Max width (~430pt) and
// centers it horizontally; the shared KomoBackground (mounted once at the
// RootView root) fills the whole compat frame edge-to-edge behind it.

private struct KomoScreenModifier<Background: View>: ViewModifier {
    /// iPhone 16 Pro Max logical width — safe upper bound for any current
    /// iPhone layout. On iPhone this is a no-op (screen is already narrower).
    static var maxWidth: CGFloat { 430 }

    let background: Background

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: Self.maxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background.ignoresSafeArea())
    }
}

private extension View {
    func komoScreen<Background: View>(background: Background) -> some View {
        modifier(KomoScreenModifier(background: background))
    }
}
