//  GreetingView.swift
//  Komo
//
//  Returning — Welcome back. A floating companion (tap or Continue -> main).

import SwiftUI

struct GreetingView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 14) {
            Text("Welcome back")
                .font(Theme.Font.body(16, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))

            BlobView(size: 200, cute: true, hue: app.dailyHue,
                     style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                     mood: .float, onTap: { app.go(.main) },
                     namespace: namespace, geometryID: "companion")
                .padding(.vertical, 6)

            Text(app.displayName)
                .font(Theme.Font.display(30))
                .foregroundStyle(.white)

            Text("Your companion kept the light on. It missed you.")
                .font(Theme.Font.body(15))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)

            Button { app.go(.main) } label: {
                Text("Continue")
                    .font(Theme.Font.label(16))
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 80)
    }
}
