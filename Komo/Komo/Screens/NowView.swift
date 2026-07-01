//  NowView.swift
//  Komo
//
//  Page 4 — Q2 "Energy now" (new in V1, replaces the old Sleep screen).
//  "how's your energy right now?" · single-choice, auto-advances to recharge.

import SwiftUI

struct NowView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID

    private let options = ["strong", "okay", "low", "running on fumes"]

    /// Local echo of the chosen option so the row can flash its selected state
    /// briefly before the screen advances.
    @State private var picked: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 1) { app.go(.energy) }
                .padding(.bottom, 14)

            QuestionTitle(text: "how’s your energy\nright now?")

            BlobView(size: 128, cute: true, hue: app.dailyHue,
                     style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                     mood: .listen, namespace: namespace, geometryID: "companion")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: Theme.Space.optionGap) {
                ForEach(options, id: \.self) { opt in
                    OptionRow(label: opt, selected: picked == opt) {
                        pick(opt)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(picked != nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, Theme.Space.screenTop)
        .padding(.bottom, 32)
    }

    /// Single tap → mark selected, hold the visual state briefly, then advance.
    private func pick(_ opt: String) {
        guard picked == nil else { return }
        picked = opt
        app.energyNow = opt
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 200))
            app.go(.restores)
        }
    }
}
