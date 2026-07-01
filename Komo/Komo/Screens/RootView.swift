//  RootView.swift
//  Komo
//
//  Hosts the global background and switches between screens. On les écrans
//  principaux (main/stats/profile/customize), on utilise un TabView natif
//  iOS 26 avec Liquid Glass automatique — exactement comme Apple Music.
//  Sur les écrans onboarding, on garde la transition cross-fade.

import SwiftUI

struct RootView: View {
    @State private var app = AppState()
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
        Group {
            if isMainFlow {
                TabView(selection: tabSelection) {
                    Tab("Home", systemImage: "house.fill", value: KomoScreen.main) {
                        ZStack {
                            KomoBackground(darken: darken)
                            Group {
                                if app.screen == .stats {
                                    StatsView(namespace: blob)
                                } else {
                                    MainView(namespace: blob)
                                }
                            }
                        }
                    }
                    Tab("Cards", systemImage: "square.stack.fill", value: KomoScreen.cards) {
                        ZStack {
                            KomoBackground(darken: darken)
                            CardsView(namespace: blob)
                        }
                    }
                    Tab("Profile", systemImage: "person.crop.circle", value: KomoScreen.profile) {
                        // TODO: expose Customize as a row inside ProfileView
                        // instead of a dedicated tab. For now, .customize
                        // still routes here.
                        ZStack {
                            KomoBackground(darken: darken)
                            Group {
                                if app.screen == .customize {
                                    CustomizeView(namespace: blob)
                                } else {
                                    ProfileView(namespace: blob)
                                }
                            }
                        }
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                .transition(.opacity)
            } else {
                ZStack {
                    KomoBackground(darken: darken)
                    onboardingScreen
                        .transition(.opacity)
                }
            }
        }
        .environment(app)
        .environment(permissions)
        .animation(.easeInOut(duration: 0.45), value: app.screen)
        .preferredColorScheme(.light)
        .task {
            await permissions.refreshAll()
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
