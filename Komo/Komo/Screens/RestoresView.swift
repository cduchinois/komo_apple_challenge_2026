//  RestoresView.swift
//  Komo
//
//  Page 5 — Q3 "Recharge". The hero is a translucent green liquid charge filling
//  the blob silhouette (komoCharge) — a cup refilling — with a soft green halo.
//  Unlimited multi-select; "not sure yet" is exclusive. Next → drains.

import SwiftUI

struct RestoresView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    private let options = ["walking", "music", "quiet time", "workout",
                           "nap / sleep", "outside", "talking", "not sure yet"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 2) { app.go(.now) }
                .padding(.bottom, 14)

            QuestionTitle(text: "what helps you\nrecharge?", subtitle: "select all that apply")

            ZStack {
                GlowHalo(color: Color(hex: 0x96EBA0).opacity(0.38), diameter: 150, period: 3.2)
                BlobView(size: 138, cute: true, hue: app.dailyHue,
                         style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                         namespace: namespace, geometryID: "companion")
                ChargeFill(size: 138)
            }
            .frame(maxHeight: .infinity)

            FlowChips(options: options, selected: app.restores) { label in
                app.toggleRestore(label)
            }

            PrimaryButton(title: "next", enabled: !app.restores.isEmpty) {
                app.go(.drains)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, Theme.Space.screenTop)
        .padding(.bottom, 32)
        .animation(.spring(response: 0.25), value: app.restores)
    }
}
