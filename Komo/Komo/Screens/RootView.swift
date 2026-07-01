//  RootView.swift
//  Komo
//
//  Hosts the global background and switches between screens. A shared namespace
//  lets the companion morph between screens via matchedGeometryEffect, and a soft
//  cross-fade (komoFade) covers everything else. Screen transitions are animated;
//  the blob carries visual continuity across them.

import SwiftUI

struct RootView: View {
    @State private var app = AppState()
    @Namespace private var blob

    /// Non-main screens get the darkening veil so white text stays legible.
    private var darken: Bool { app.screen != .main }

    var body: some View {
        ZStack {
            KomoBackground(darken: darken)

            screen
                .transition(.opacity)
        }
        .environment(app)
        .animation(.easeInOut(duration: 0.45), value: app.screen)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var screen: some View {
        switch app.screen {
        case .splash:    SplashView(namespace: blob)
        case .intro:     IntroView(namespace: blob)
        case .energy:    EnergyView(namespace: blob)
        case .now:       NowView(namespace: blob)
        case .restores:  RestoresView(namespace: blob)
        case .drains:    DrainsView(namespace: blob)
        case .signals:   SignalsView(namespace: blob)
        case .loading:   LoadingView(namespace: blob)
        case .greeting:  GreetingView(namespace: blob)
        case .main:      MainView(namespace: blob)
        case .stats:     StatsView(namespace: blob)
        case .profile:   ProfileView(namespace: blob)
        case .customize: CustomizeView(namespace: blob)
        }
    }
}

#Preview {
    RootView()
}
