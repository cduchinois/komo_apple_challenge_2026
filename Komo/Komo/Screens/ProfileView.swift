//  ProfileView.swift
//  Komo
//
//  Companion profile — a calm summary of who the companion is and how it's tuned.
//  Reached from the main screen's "Days Together" header.

import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    private var rows: [(String, String)] {
        [
            ("World", app.world.name),
            ("Companion", "\(app.companionDisplayName) · \(app.character.trait)"),
            ("Look", app.blobStyle.name),
            ("Eyes", app.eyes.name),
            ("Legs", app.legs.name),
            ("Voice", app.tone.name),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    GlassBackButton { app.go(.main) }
                    Text(app.displayName)
                        .font(Theme.Font.title(20)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                BlobView(size: 132, cute: true, hue: app.dailyHue,
                         style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                         motion: app.character.motion,
                         namespace: namespace, geometryID: "companion")
                    .padding(.vertical, 4)

                Text(app.companionDisplayName)
                    .font(Theme.Font.display(26)).foregroundStyle(.white)
                Text(app.character.desc)
                    .font(Theme.Font.body(14)).foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center).frame(maxWidth: 280)

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        HStack {
                            Text(row.0).font(Theme.Font.body(15)).foregroundStyle(.white.opacity(0.78))
                            Spacer()
                            Text(row.1).font(Theme.Font.label(15)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 15)
                        if idx < rows.count - 1 {
                            Divider().overlay(Color.white.opacity(0.12)).padding(.leading, 18)
                        }
                    }
                }
                .komoGlassCard(cornerRadius: Theme.Radius.card, fillOpacity: 0.14, strokeOpacity: 0.24)

                Button { app.go(.customize) } label: {
                    Text("Customize \(app.companionDisplayName)")
                        .font(Theme.Font.label(16)).foregroundStyle(Theme.Palette.ink)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.Space.screenH)
            .padding(.top, 62)
            .padding(.bottom, 44)
        }
    }
}
