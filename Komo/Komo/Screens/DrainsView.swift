//  DrainsView.swift
//  Komo
//
//  Page 5 — What drains you. The blob is tired (half-lidded, more saturated,
//  komoTired). Multi-select, max two; Continue once at least one is picked.

import SwiftUI

struct DrainsView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    private let options = ["Busy schedule", "Scrolling social media", "Poor sleep", "Sitting too long", "Stress"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 3) { app.go(.sleep) }
                .padding(.bottom, 14)

            QuestionTitle(text: "What tends to make you exhausted?", subtitle: "Pick up to two.")

            BlobView(size: 132, cute: true, tired: true, hue: app.dailyHue,
                     style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                     mood: .tired, namespace: namespace, geometryID: "companion")
                .frame(maxHeight: .infinity)

            FlowChips(options: options, selected: app.drains) { label in
                app.toggleMulti(\.drains, label)
            }

            PrimaryButton(title: "Continue", enabled: !app.drains.isEmpty) {
                app.go(.restores)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, 64)
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
