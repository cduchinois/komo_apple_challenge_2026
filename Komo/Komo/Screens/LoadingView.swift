//  LoadingView.swift
//  Komo
//
//  Transition — Bringing your companion to life. The blob floats (komoFloat), the
//  caption pulses and swaps by threshold, and the bar fills (+3..8% every 110ms)
//  until 100%, then settles into the main screen after 500ms.

import SwiftUI

struct LoadingView: View {
    @Environment(AppState.self) private var app
    @Environment(PermissionsManager.self) private var permissions
    var namespace: Namespace.ID

    private var caption: String {
        let p = app.loadingPct
        if p < 40 { return "reading your signals…" }
        if p < 75 { return "looking for patterns…" }
        return "building your first energy check-in…"
    }

    var body: some View {
        VStack(spacing: 36) {
            // TODO(mascot-rollout): old hue/style/eyes/legs/mood dropped —
            // the manual defines a single idle motion used everywhere.
            KomoMascotView(size: KomoMascotView.standardSize,
                           namespace: namespace,
                           geometryID: "companion",
                           accessibilityLabelText: app.companionDisplayName)

            VStack(spacing: 16) {
                Text(caption)
                    .font(Theme.Font.body(18, weight: .medium))
                    .foregroundStyle(.white)
                    .pulsing()

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule().fill(Color.white)
                            .frame(width: geo.size.width * CGFloat(app.loadingPct / 100))
                            .shadow(color: .white.opacity(0.6), radius: 6)
                            .animation(.linear(duration: 0.15), value: app.loadingPct)
                    }
                }
                .frame(height: 6)

                Text("\(Int(app.loadingPct))%")
                    .font(Theme.Font.label(13))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 80)
        .task {
            // Snapshot onboarding answers into topic sets and reset the
            // Reflect cursor so the first two Home cards are personalized.
            app.completeOnboarding()

            // Fire the native notification prompt here (replaces the old
            // SignalsView toggle wall). The bar keeps filling in parallel —
            // slowed intentionally so the user has time to read + tap the
            // system prompt before we move on.
            Task { await permissions.requestNotifications() }

            app.loadingPct = 0
            // ~50 ticks × 130ms + 1.2s tail ≈ 7–8s total.
            while app.loadingPct < 100 {
                try? await Task.sleep(for: .milliseconds(130))
                if app.screen != .loading { return }
                app.loadingPct = min(100, app.loadingPct + (1 + Double.random(in: 0..<2)))
            }
            try? await Task.sleep(for: .milliseconds(1200))
            if app.screen == .loading { app.go(.main) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bringing your companion to life. \(Int(app.loadingPct)) percent.")
    }
}

private extension View {
    func pulsing() -> some View { modifier(Pulse()) }
}

private struct Pulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.animation) { tl in
                let p = (tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2)) / 2
                content.opacity(0.5 + 0.5 * (sin(p * 2 * .pi) * 0.5 + 0.5))
            }
        }
    }
}
