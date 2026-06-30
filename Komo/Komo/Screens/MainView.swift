//  MainView.swift
//  Komo
//
//  Home — the main companion screen. The animated blob sits in the bright garden;
//  tapping it pops a speech-bubble insight (komoPop). Above is the insight card
//  with Add Reminder + like; below, today's energy bar; then Feed / Quest / Grow
//  and the bottom navigation. Feeding drops a treat that becomes a rising heart.

import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    @State private var feedItems: [FeedItem] = []

    private var snapshot: EnergySnapshot { app.data.currentSnapshot() }

    var body: some View {
        VStack(spacing: 0) {
            // Days together — taps through to the companion profile.
            Button { app.go(.profile) } label: {
                Text("Already \(snapshot.daysTogether) Days Together")
                    .font(Theme.Font.title(20))
                    .foregroundStyle(Theme.Palette.inkForest)
                    .shadow(color: .white.opacity(0.55), radius: 12, y: 1)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityHint("Opens your companion profile")

            insightCard
                .padding(.top, 24)

            companionStage
                .padding(.top, 14)

            actionButtons
                .padding(.top, 34)

            Spacer(minLength: 14)

            bottomNav
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
    }

    // MARK: Insight card

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(snapshot.headlineInsight)
                .font(Theme.Font.title(17))
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button { withAnimation(.spring) { app.addReminder() }; scheduleReminderReset() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: app.reminderAdded ? "checkmark" : "bell")
                            .foregroundStyle(Theme.Palette.leaf)
                        Text(app.reminderAdded ? "Reminder set" : "Add Reminder")
                            .font(Theme.Font.label(14.5))
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                    .frame(height: 48).padding(.horizontal, 18)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip).strokeBorder(Color(hex: 0x3C5A46).opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                Button { app.toggleLike() } label: {
                    Image(systemName: app.liked ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(app.liked ? Theme.Palette.leaf : Theme.Palette.leaf)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip).strokeBorder(Color(hex: 0x3C5A46).opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.liked ? "Unlike insight" : "Like insight")
            }
        }
        .padding(Theme.Space.cardPad)
        .frame(maxWidth: 332)
        .komoGlassCard(cornerRadius: Theme.Radius.insight, fillOpacity: 0.64, strokeOpacity: 0.75, shadow: true)
    }

    // MARK: Companion + bubble + energy bar

    private var companionStage: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                if app.bubbleShown {
                    SpeechBubble(text: app.currentInsightLine)
                        .offset(y: -8)
                        .zIndex(2)
                }

                ZStack {
                    BlobView(size: 196, cute: true, hue: app.dailyHue,
                             motion: app.character.motion,
                             // tapping cycles the insight bubble
                             style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                             onTap: { withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { app.tapCompanion() } },
                             namespace: namespace, geometryID: "companion")
                        .accessibilityLabel("\(app.companionDisplayName), your companion. Double tap for an insight.")

                    ForEach(feedItems) { item in
                        FeedItemView(item: item) { remove(item) }
                    }
                }
                .padding(.top, 70)
            }

            // ground shadow
            Ellipse().fill(RadialGradient(colors: [.white.opacity(0.18), .clear],
                                          center: .center, startRadius: 0, endRadius: 64))
                .frame(width: 128, height: 16)
                .blur(radius: 3)
                .offset(y: -10)

            energyBar
        }
    }

    private var energyBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Today's Energy")
                    .font(Theme.Font.label(14, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 6, y: 1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.24))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.Palette.energyBarStart, Theme.Palette.energyBarEnd],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(snapshot.percent) / 100)
                            .overlay(alignment: .trailing) {
                                Text("⚡").font(.system(size: 11)).padding(.trailing, 6)
                            }
                            .shadow(color: Color(hex: 0x82D773).opacity(0.6), radius: 8)
                    }
                }
                .frame(height: 16)
            }

            VStack(alignment: .trailing, spacing: 1) {
                Button { app.go(.stats) } label: {
                    HStack(spacing: 5) {
                        Text(snapshot.word)
                            .font(Theme.Font.label(20, weight: .heavy))
                            .foregroundStyle(.white)
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Energy \(snapshot.word), \(snapshot.percent) percent. Opens today's signals.")

                Text("\(snapshot.percent)%")
                    .font(Theme.Font.label(14, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    // MARK: Feed / Quest / Grow

    private var actionButtons: some View {
        HStack(spacing: 10) {
            ActionButton(system: "leaf.fill", title: "Feed") { feed() }
            ActionButton(system: "puzzlepiece.fill", title: "Quest") {
                withAnimation(.spring(response: 0.4)) { app.tapCompanion() }
            }
            ActionButton(system: "sparkles", title: "Grow") {
                withAnimation(.spring(response: 0.4)) { app.tapCompanion() }
            }
        }
    }

    // MARK: Bottom nav

    private var bottomNav: some View {
        HStack(spacing: 2) {
            NavItem(system: "house.fill", title: "Home", selected: true) { app.go(.main) }
            NavItem(system: app.liked ? "heart.fill" : "heart", title: "Favorites", selected: false) { app.toggleLike() }
            NavItem(system: "person.crop.circle", title: "Profile", selected: false) { app.go(.profile) }
            NavItem(system: "gearshape", title: "Settings", selected: false) { app.go(.customize) }
        }
        .padding(7)
        .background(Color(hex: 0x182E22).opacity(0.32), in: RoundedRectangle(cornerRadius: Theme.Radius.nav, style: .continuous))
        .komoGlass(RoundedRectangle(cornerRadius: Theme.Radius.nav, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.nav).strokeBorder(.white.opacity(0.24), lineWidth: 1))
    }

    // MARK: Feed logic (treat -> heart)

    private func feed() {
        let treats = ["🍎", "🍓", "🫐", "🍪", "🍃", "🥕"]
        let item = FeedItem(icon: treats.randomElement() ?? "🍎")
        feedItems.append(item)
    }
    private func remove(_ item: FeedItem) {
        feedItems.removeAll { $0.id == item.id }
    }
    private func scheduleReminderReset() {
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            app.reminderAdded = false
        }
    }
}

// MARK: - Action / nav sub-buttons

private struct ActionButton: View {
    var system: String
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 11) {
                Image(systemName: system).font(.system(size: 30, weight: .medium)).foregroundStyle(.white)
                Text(title).font(Theme.Font.label(15, weight: .bold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 1)
            }
            .frame(maxWidth: .infinity).frame(height: 106)
            .komoGlassCard(cornerRadius: Theme.Radius.action, fillOpacity: 0.16, strokeOpacity: 0.42, shadow: false, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct NavItem: View {
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

// MARK: - Feed item (drop -> heart)

struct FeedItem: Identifiable {
    let id = UUID()
    let icon: String
}

private struct FeedItemView: View {
    let item: FeedItem
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0   // 0 = treat dropping, 1 = heart rising

    var body: some View {
        Group {
            if phase == 0 {
                Text(item.icon).font(.system(size: 30))
                    .modifier(DropEffect(reduce: reduceMotion))
            } else {
                Text("❤️").font(.system(size: 28))
                    .modifier(RiseEffect(reduce: reduceMotion))
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(850))
            phase = 1
            try? await Task.sleep(for: .milliseconds(1300))
            onDone()
        }
        .allowsHitTesting(false)
    }
}

/// komoFeedDrop — treat falls from above into the blob and fades.
private struct DropEffect: ViewModifier {
    var reduce: Bool
    @State private var t: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .offset(y: -54 + t * 162)
            .scaleEffect(1 - t * 0.65)
            .opacity(reduce ? Double(1 - t) : (t < 0.14 ? Double(t / 0.14) : Double(max(0, 1 - (t - 0.68) / 0.32))))
            .onAppear { withAnimation(.easeIn(duration: 0.95)) { t = 1 } }
    }
}

/// komoHeartRise — a heart floats up and fades.
private struct RiseEffect: ViewModifier {
    var reduce: Bool
    @State private var t: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .offset(y: 26 - t * 104)
            .scaleEffect(0.4 + (t < 0.26 ? t / 0.26 * 0.7 : 1.1 - (t - 0.26) * 0.34))
            .opacity(t < 0.26 ? Double(t / 0.26) : Double(max(0, 1 - (t - 0.26) / 0.74)))
            .onAppear { withAnimation(.easeOut(duration: 1.3)) { t = 1 } }
    }
}
