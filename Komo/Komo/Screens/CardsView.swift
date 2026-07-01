//  CardsView.swift
//  Komo
//
//  Cards tab — insights and patterns about the user (when-patterns, todos).
//  Placeholder stub for now; the real feed will be seeded by KOMO's Reflect
//  history + passive-signal analysis.

import SwiftUI

struct CardsView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 18) {
            Text("Cards")
                .font(Theme.Font.title(24))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 1)

            Text("Insights and patterns KOMO has learned about you.\nComing soon.")
                .font(Theme.Font.body(14))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 1)
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, Theme.Space.screenTop + 40)
    }
}
