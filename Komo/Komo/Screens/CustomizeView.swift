//  CustomizeView.swift
//  Komo
//
//  Customize the companion: name, surface, eyes, legs, voice, motion, and world.
//  A live preview floats at the top and updates as choices change. Done -> main.

import SwiftUI

struct CustomizeView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    GlassBackButton { app.go(.main) }
                    Text("Customize \(app.companionDisplayName)")
                        .font(Theme.Font.title(20)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
                    Spacer()
                }

                BlobView(size: 150, cute: true, hue: app.dailyHue,
                         style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                         motion: app.character.motion,
                         mood: .float, namespace: namespace, geometryID: "companion")
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)

                section("NAME") {
                    TextField("", text: Binding(get: { app.companionName }, set: { app.companionName = $0 }),
                              prompt: Text("Call me KOMO").foregroundColor(.white.opacity(0.55)))
                        .font(Theme.Font.label(16)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 50)
                        .komoGlassCard(cornerRadius: Theme.Radius.field, fillOpacity: 0.18, strokeOpacity: 0.3)
                }

                section("SURFACE") {
                    ChipBar(items: BlobStyle.allCases.map(\.name),
                            selectedIndex: BlobStyle.allCases.firstIndex(of: app.blobStyle) ?? 0) { i in
                        app.blobStyle = BlobStyle.allCases[i]
                    }
                }

                section("EYES") {
                    ChipBar(items: EyeStyle.allCases.map(\.name),
                            selectedIndex: EyeStyle.allCases.firstIndex(of: app.eyes) ?? 0) { i in
                        app.eyes = EyeStyle.allCases[i]
                    }
                }

                section("MOVE") {
                    ChipBar(items: LegStyle.allCases.map(\.name),
                            selectedIndex: LegStyle.allCases.firstIndex(of: app.legs) ?? 0) { i in
                        app.legs = LegStyle.allCases[i]
                    }
                }

                section("MOTION") {
                    ChipBar(items: CompanionCharacter.all.map(\.trait),
                            selectedIndex: app.characterIndex) { i in
                        app.characterIndex = i
                    }
                }

                section("VOICE") {
                    ChipBar(items: CompanionTone.all.map(\.name),
                            selectedIndex: CompanionTone.all.firstIndex(of: app.tone) ?? 0) { i in
                        app.tone = CompanionTone.all[i]
                    }
                }

                section("WORLD") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(CompanionWorld.all) { world in
                            WorldSwatch(world: world, selected: app.worldIndex == world.id) {
                                if !world.locked { app.worldIndex = world.id }
                            }
                        }
                    }
                }

                Button { app.go(.main) } label: {
                    Text("Done")
                        .font(Theme.Font.label(16)).foregroundStyle(Theme.Palette.ink)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.horizontal, Theme.Space.screenH)
            .padding(.top, 62)
            .padding(.bottom, 44)
            .animation(.easeInOut(duration: 0.25), value: app.blobStyle)
            .animation(.easeInOut(duration: 0.25), value: app.eyes)
            .animation(.easeInOut(duration: 0.25), value: app.legs)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Font.label(13, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.leading, 4)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
            content()
        }
    }
}

/// A row of equal-width selectable chips.
private struct ChipBar: View {
    var items: [String]
    var selectedIndex: Int
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, name in
                let selected = i == selectedIndex
                Button { onSelect(i) } label: {
                    Text(name)
                        .font(Theme.Font.label(13))
                        .foregroundStyle(selected ? Theme.Palette.ink : .white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(selected ? Color.white.opacity(0.9) : Color.white.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

private struct WorldSwatch: View {
    var world: CompanionWorld
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                WorldBackground(id: world.id)
                LinearGradient(colors: [.white.opacity(0.26), .clear], startPoint: .topLeading, endPoint: .center)
                if world.locked {
                    Color.black.opacity(0.35)
                    Image(systemName: "lock.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.92))
                }
                VStack { Spacer(); HStack {
                    Text(world.locked ? "Locked" : world.name)
                        .font(Theme.Font.label(13)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 1)
                    Spacer() } }
                .padding(11)
            }
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(selected ? 1 : 0.22), lineWidth: selected ? 3 : 3))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 8)
            .opacity(world.locked ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(world.name)\(world.locked ? ", locked" : "")")
    }
}

/// Representative gradient for each world (the photo backdrop stays global; these
/// are the picker swatches).
struct WorldBackground: View {
    var id: Int
    var body: some View {
        switch id {
        case 1: // Neon Cyberpunk
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2A1A4A), Color(hex: 0x0C0820)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0xFF5DB1), .clear], center: .topLeading, startRadius: 0, endRadius: 90)
                RadialGradient(colors: [Color(hex: 0x2DE2E6), .clear], center: .topTrailing, startRadius: 0, endRadius: 90)
            }
        case 2: // Sakura Bloom
            ZStack {
                LinearGradient(colors: [Color(hex: 0xFFC2D8), Color(hex: 0xE07BA6)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.white, .clear], center: .top, startRadius: 0, endRadius: 80)
            }
        case 3: // Cosmic Starry
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2B2466), Color(hex: 0x0A0820)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0x5B3FA0), .clear], center: .topTrailing, startRadius: 0, endRadius: 90)
            }
        case 4: // Tidepool (locked)
            LinearGradient(colors: [Color(hex: 0x5B6B72), Color(hex: 0x3C474D)], startPoint: .top, endPoint: .bottom)
        case 5: // Ember Night (locked)
            LinearGradient(colors: [Color(hex: 0x6E5F6B), Color(hex: 0x4A4150)], startPoint: .top, endPoint: .bottom)
        default: // Mystic Forest
            ZStack {
                LinearGradient(colors: [Color(hex: 0x3F7D52), Color(hex: 0x14352B)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0xF3E7A0), .clear], center: .topLeading, startRadius: 0, endRadius: 80)
            }
        }
    }
}
