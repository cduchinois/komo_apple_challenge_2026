//  EnergyView.swift
//  Komo
//
//  Page 3 — Q1 "Switched on". The companion listens (komoListen) inside the
//  signature "sun": a warm glow plus two blurred ray fans counter-rotating.
//  Single-choice; auto-advances to the "energy now" question.

import SwiftUI

struct EnergyView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID

    private let options = OnboardingOptions.energyPeaks

    /// Local echo of the chosen option so the row can flash its selected state
    /// briefly before the screen advances. Nil once the view re-appears.
    @State private var picked: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 0) { app.go(.intro) }
                .padding(.bottom, 14)

            QuestionTitle(text: "when do you feel\nmost switched on?")

            // Mascot cell — locked to the standard 220pt mascot size so the
            // aurora rays (300pt halo + 280/200pt spoke fans) no longer expand
            // the VStack's vertical footprint. Before this, the aurora ZStack's
            // intrinsic 300pt height pushed the question title up against the
            // status bar and cropped the last option on iPad's compat frame.
            // Aurora now lives as a purely decorative background layer, drawn
            // behind the mascot and free to overflow the cell bounds.
            //
            // TODO(mascot-rollout): "listen" mood + hue/style/eyes/legs
            // dropped — manual's default idle is used everywhere.
            KomoMascotView(size: KomoMascotView.standardSize,
                           namespace: namespace,
                           geometryID: "companion",
                           accessibilityLabelText: app.companionDisplayName)
                .background {
                    ZStack {
                        GlowHalo(color: Color(hex: 0xFFF6CD).opacity(0.4), diameter: 300, period: 4.6)
                        SunRays(diameter: 280, color: Color(hex: 0xFFF5C3).opacity(0.26),
                                spokes: 20, period: 34, reversed: false, blur: 3)
                        SunRays(diameter: 200, color: Color(hex: 0xFFF0AA).opacity(0.20),
                                spokes: 15, period: 52, reversed: true, blur: 2)
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: KomoMascotView.standardSize,
                       height: KomoMascotView.standardSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: Theme.Space.optionGap) {
                ForEach(options, id: \.self) { opt in
                    OptionRow(labelKey: opt, selected: picked == opt) {
                        pick(opt)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(picked != nil)
        }
        .frame(maxWidth: .infinity)
        .safeAreaPadding(.horizontal, 40)
        .padding(.top, Theme.Space.screenTop)
        .padding(.bottom, 32)
    }

    /// Single tap → mark selected, hold the visual state briefly, then advance.
    private func pick(_ opt: String) {
        guard picked == nil else { return }
        picked = opt
        app.energyType = opt
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 200))
            app.go(.now)
        }
    }
}
