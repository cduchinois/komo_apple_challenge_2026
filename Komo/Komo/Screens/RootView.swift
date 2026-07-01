//  RootView.swift
//  Komo
//
//  Hosts the global background and switches between screens.
//  Sur les écrans principaux (main/stats/favorites/profile/customize),
//  utilise un TabView natif iOS 26 avec Liquid Glass automatique — exactement
//  comme Apple Music. Sur les écrans onboarding, garde la transition cross-fade.

import SwiftUI

struct RootView: View {
    @State private var app = AppState()
    @Namespace private var blob

    /// True quand on est dans le flux principal (post-onboarding).
    private var isMainFlow: Bool {
        switch app.screen {
        case .main, .stats, .favorites, .profile, .customize: return true
        default: return false
        }
    }

    private var darken: Bool {
        switch app.screen {
        case .main, .favorites: return false
        default: return true
        }
    }

    private var tabSelection: Binding<KomoScreen> {
        Binding(
            get: {
                if app.screen == .stats { return .main }
                return app.screen
            },
            set: { app.go($0) }
        )
    }

    var body: some View {
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
                        .background { KomoBackground(darken: darken) }
                        .toolbarBackground(.visible, for: .tabBar)
                    }
                    Tab("Favorites", systemImage: "heart.fill", value: KomoScreen.favorites) {
                        FavoritesView(namespace: blob)
                            .background { KomoBackground(darken: darken) }
                            .toolbarBackground(.visible, for: .tabBar)
                    }
                    Tab("Profile", systemImage: "person.crop.circle", value: KomoScreen.profile) {
                        ProfileView(namespace: blob)
                            .background { KomoBackground(darken: darken) }
                            .toolbarBackground(.visible, for: .tabBar)
                    }
                    Tab("Settings", systemImage: "gearshape", value: KomoScreen.customize) {
                        CustomizeView(namespace: blob)
                            .background { KomoBackground(darken: darken) }
                            .toolbarBackground(.visible, for: .tabBar)
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                .transition(.opacity)
            } else {
                ZStack {
                    KomoBackground(darken: darken)
                    onboardingScreen
                }
                .transition(.opacity)
            }
        }
        .environment(app)
        .animation(.easeInOut(duration: 0.45), value: app.screen)
        .animation(.easeInOut(duration: 0.6), value: app.worldIndex)
        .preferredColorScheme(app.worldIndex == 1 || app.worldIndex == 3 || app.worldIndex == 5 ? .dark : .light)
    }

    // MARK: - Screens

    @ViewBuilder
    private var onboardingScreen: some View {
        switch app.screen {
        case .splash:    SplashView(namespace: blob)
        case .intro:     IntroView(namespace: blob)
        case .energy:    EnergyView(namespace: blob)
        case .sleep:     SleepView(namespace: blob)
        case .drains:    DrainsView(namespace: blob)
        case .restores:  RestoresView(namespace: blob)
        case .loading:   LoadingView(namespace: blob)
        case .greeting:  GreetingView(namespace: blob)
        default:         MainView(namespace: blob)
        }
    }
}

#Preview {
    RootView()
}
