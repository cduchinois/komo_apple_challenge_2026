//  NowView.swift
//  Komo
//
//  Page 4 — Q2 "Energy now" (new in V1, replaces the old Sleep screen).
//  "how's your energy right now?" · single-choice, auto-advances to recharge.

import SwiftUI

struct NowView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    private let options = ["strong", "okay", "low", "running on fumes"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 1) { app.go(.energy) }
                .padding(.bottom, 14)

            QuestionTitle(text: "how’s your energy\nright now?")

            BlobView(size: 128, cute: true, hue: app.dailyHue,
                     style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                     mood: .listen, namespace: namespace, geometryID: "companion")
                .frame(maxHeight: .infinity)

            VStack(spacing: Theme.Space.optionGap) {
                ForEach(options, id: \.self) { opt in
                    OptionRow(label: opt) {
                        app.energyNow = opt
                        app.go(.restores)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, 64)
        .padding(.bottom, 32)
    }
}
