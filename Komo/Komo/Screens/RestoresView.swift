//  RestoresView.swift
//  Komo
//
//  Page 6 — What restores you (final onboarding). The hero is a translucent green
//  liquid charge filling the blob silhouette (komoCharge) — a cup refilling — with
//  a soft green halo. The body itself is still on purpose (mood .none).

import SwiftUI

struct RestoresView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    private let options = ["Sleep", "Moving or walking", "Quiet time", "Focus", "Being outside"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 4) { app.go(.drains) }
                .padding(.bottom, 14)

            QuestionTitle(text: "What helps you recharge your energy?", subtitle: "Pick up to two.")

            ZStack {
                GlowHalo(color: Color(hex: 0x96EBA0).opacity(0.38), diameter: 150, period: 3.2)
                BlobView(size: 138, cute: true, hue: app.dailyHue,
                         style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                         mood: BlobAnim.none, namespace: namespace, geometryID: "companion")
                ChargeFill(size: 138)
            }
            .frame(maxHeight: .infinity)

            FlowChips(options: options, selected: app.restores) { label in
                app.toggleMulti(\.restores, label)
            }

            PrimaryButton(title: "Let’s begin", enabled: !app.restores.isEmpty) {
                app.go(.loading)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, 64)
        .padding(.bottom, 32)
        .animation(.spring(response: 0.25), value: app.restores)
    }
}
