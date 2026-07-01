//  FavoritesView.swift
//  Komo
//
//  Insights sauvegardés — accessibles via la nav Favorites.
//  Le cœur sur la carte principale sauvegarde un insight ici.
//  Style identique aux autres écrans du frontend (glass cards, fond garden).

import SwiftUI

struct FavoritesView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                HStack(spacing: 14) {
                    GlassBackButton { app.go(.main) }
                    Text("Saved Insights")
                        .font(Theme.Font.title(20))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
                    Spacer()
                }
                .padding(.top, 8)

                if app.likedInsights.isEmpty {
                    emptyState
                } else {
                    insightsList
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 60)

            // Petit blob qui attend
            BlobView(
                size: 110, cute: true, hue: app.dailyHue,
                style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                motion: .calm, namespace: namespace, geometryID: "fav-blob"
            )

            VStack(spacing: 8) {
                Text("Nothing saved yet")
                    .font(Theme.Font.title(20))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 1)
                Text("Tap the ♡ on an insight to save it here.")
                    .font(Theme.Font.body(15))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Insights list

    private var insightsList: some View {
        VStack(spacing: 14) {
            ForEach(app.likedInsights.reversed(), id: \.self) { insight in
                insightCard(insight)
            }
        }
    }

    private func insightCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .font(Theme.Font.title(16))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                // Catégorie auto-détectée
                Label(categoryLabel(for: text), systemImage: categoryIcon(for: text))
                    .font(Theme.Font.label(12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.leaf)

                Spacer()

                // Bouton supprimer
                Button {
                    withAnimation(.spring(response: 0.35)) {
                        app.likedInsights.removeAll { $0 == text }
                    }
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.leaf)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.45),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from favorites")
            }
        }
        .padding(Theme.Space.cardPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .komoGlassCard(cornerRadius: Theme.Radius.insight,
                       fillOpacity: 0.64, strokeOpacity: 0.75, shadow: true)
    }

    // MARK: - Bottom nav (identique à MainView)

    private var bottomNav: some View {
        HStack(spacing: 2) {
            NavButton(system: "house.fill", title: "Home",
                      selected: false) { app.go(.main) }
            NavButton(system: app.likedInsights.isEmpty ? "heart" : "heart.fill",
                      title: "Favorites",
                      selected: true) { }
            NavButton(system: "person.crop.circle", title: "Profile",
                      selected: false) { app.go(.profile) }
            NavButton(system: "gearshape", title: "Settings",
                      selected: false) { app.go(.customize) }
        }
        .padding(7)
        .komoGlass(RoundedRectangle(cornerRadius: Theme.Radius.nav, style: .continuous),
                   tint: Color(hex: 0x182E22).opacity(0.45))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.nav)
            .strokeBorder(.white.opacity(0.24), lineWidth: 1))
    }

    // MARK: - Helpers

    private func categoryLabel(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("sommeil") || lower.contains("sleep") || lower.contains("nuit") { return "Sleep" }
        if lower.contains("marche") || lower.contains("walk") || lower.contains("pas") { return "Movement" }
        if lower.contains("stress") || lower.contains("pause") || lower.contains("calme") { return "Recovery" }
        if lower.contains("réunion") || lower.contains("meeting") { return "Focus" }
        return "Energy"
    }

    private func categoryIcon(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("sommeil") || lower.contains("sleep") || lower.contains("nuit") { return "moon.stars.fill" }
        if lower.contains("marche") || lower.contains("walk") || lower.contains("pas") { return "figure.walk" }
        if lower.contains("stress") || lower.contains("pause") || lower.contains("calme") { return "leaf.fill" }
        if lower.contains("réunion") || lower.contains("meeting") { return "calendar" }
        return "bolt.heart.fill"
    }
}

// MARK: - NavButton (local copy pour FavoritesView)

private struct NavButton: View {
    var system: String
    var title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: system).font(.system(size: 20, weight: .medium))
                Text(title).font(.system(size: 10.5, weight: selected ? .bold : .semibold))
            }
            .foregroundStyle(selected ? Color(hex: 0xEAFFF0) : .white.opacity(0.78))
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(selected ? Color.white.opacity(0.2) : .clear,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
