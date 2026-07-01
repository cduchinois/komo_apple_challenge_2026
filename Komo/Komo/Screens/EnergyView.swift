//  EnergyView.swift
//  Komo
//
//  Page 3 — Q1 "Switched on". The companion listens (komoListen) inside the
//  signature "sun": a warm glow plus two blurred ray fans counter-rotating.
//  Single-choice; auto-advances to the "energy now" question.

import SwiftUI

struct EnergyView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    private let options = ["morning", "afternoon", "evening", "late night", "changes a lot"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 0) { app.go(.intro) }
                .padding(.bottom, 14)

            QuestionTitle(text: "when do you feel\nmost switched on?")

            ZStack {
                GlowHalo(color: Color(hex: 0xFFF6CD).opacity(0.4), diameter: 300, period: 4.6)
                SunRays(diameter: 280, color: Color(hex: 0xFFF5C3).opacity(0.26),
                        spokes: 20, period: 34, reversed: false, blur: 3)
                SunRays(diameter: 200, color: Color(hex: 0xFFF0AA).opacity(0.20),
                        spokes: 15, period: 52, reversed: true, blur: 2)
                BlobView(size: 128, cute: true, hue: app.dailyHue,
                         style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                         mood: .listen, namespace: namespace, geometryID: "companion")
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: Theme.Space.optionGap) {
                ForEach(options, id: \.self) { opt in
                    OptionRow(label: opt) {
                        app.energyType = opt
                        app.go(.now)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, 64)
        .padding(.bottom, 32)
    }
}
