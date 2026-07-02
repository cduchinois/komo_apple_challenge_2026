//  SleepView.swift
//  Komo
//
//  Q sleep — "did you sleep well last night?" · single-choice, auto-advances to
//  the contextual health-permission screen. Doubles as the first manual data
//  point if health access is later declined.

import SwiftUI

struct SleepView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID

    private let options = ["slept great", "okay", "badly", "barely slept"]

    /// Local echo of the chosen option so the row can flash its selected state
    /// briefly before the screen advances.
    @State private var picked: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Shares dot #2 in the 5-dot progress row with HealthPermissionView.
            OnboardingHeader(step: 2) { app.go(.now) }
                .padding(.bottom, 14)

            QuestionTitle(text: "did you sleep well\nlast night?")

            KomoMascotView(size: KomoMascotView.standardSize,
                           namespace: namespace,
                           geometryID: "companion",
                           accessibilityLabelText: app.companionDisplayName)
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
        .padding(.top, Theme.Space.screenTop)
        .padding(.bottom, 32)
        .safeAreaPadding(.horizontal, 40)
    }

    private func pick(_ opt: String) {
        guard picked == nil else { return }
        picked = opt
        app.sleepAnswer = opt
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 200))
            app.go(.healthPermission)
        }
    }
}
