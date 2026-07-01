//  DrainsView.swift
//  Komo
//
//  Page 6 — Q4 "Drains". The blob is tired (half-lidded, more saturated,
//  komoTired). Unlimited multi-select; "not sure yet" is exclusive. Next → signals.

import SwiftUI

struct DrainsView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    private let options = ["poor sleep", "screen time", "meetings", "sitting too long",
                           "intense work", "social plans", "commute / travel", "not sure yet"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 3) { app.go(.restores) }
                .padding(.bottom, 14)

            QuestionTitle(text: "what usually\ndrains you?", subtitle: "select all that apply")

            // TODO(mascot-rollout): "tired" mood and hue/style/eyes/legs
            // have no equivalent in KomoMascotView; manual's default idle
            // is used everywhere.
            KomoMascotView(size: KomoMascotView.standardSize,
                           namespace: namespace,
                           geometryID: "companion",
                           accessibilityLabelText: app.companionDisplayName)
                .frame(maxHeight: .infinity)

            FlowChips(options: options, selected: app.drains) { label in
                app.toggleDrain(label)
            }

            PrimaryButton(title: "next", enabled: !app.drains.isEmpty) {
                app.go(.signals)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, Theme.Space.screenTop)
        .padding(.bottom, 32)
        .animation(.spring(response: 0.25), value: app.drains)
    }
}

/// A centered wrapping row of multi-select pills.
struct FlowChips: View {
    var options: [String]
    var selected: [String]
    var onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 10, alignment: .center) {
            ForEach(options, id: \.self) { opt in
                PillChip(label: opt, selected: selected.contains(opt)) { onTap(opt) }
            }
        }
    }
}
