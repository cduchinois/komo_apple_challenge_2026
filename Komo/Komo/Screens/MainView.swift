//  MainView.swift
//  Komo
//
//  Home — the single question this screen answers: "What is my energy today,
//  and what should I do next?" Layout, top to bottom:
//    1. Header — "Day N with KOMO"
//    2. Insight card (KOMO noticed / Tiny move / Remind me + Ignore)
//    3. Companion (blob) — tap = tiny reaction only, not navigation
//    4. Energy hero — color-graded word + percent (green→red via EnergyLevel)
//    5. Action area — Feed, Reflect, Recharge (three glass buttons)
//  No elastic bottom Spacer; the tab bar comes from RootView's TabView.

import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID

    // In-flight treats animated on top of the blob.
    @State private var feedItems: [FeedItem] = []
    // Blob tap reaction (squash + tiny heart).
    @State private var blobSquash: CGFloat = 1.0
    @State private var showHeart = false
    // Sheets
    @State private var showSnackStore = false
    @State private var showRecharge = false
    @State private var showEnergyInfo = false

    private var snapshot: EnergySnapshot { app.data.currentSnapshot() }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 6)

            insightCard
                .padding(.top, 18)

            companionStage
                .padding(.top, 10)

            energyHero
                .padding(.top, 6)

            actionArea
                .padding(.top, 18)
        }
        // Shared horizontal margin token → insight card, energy hero, bar,
        // and action row all sit inside the same symmetric inset.
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, 8)   // sits just below the safe-area inset
        .sheet(isPresented: $showSnackStore) {
            SnackStoreSheet(snacks: AppState.demoSnacks) { snack in
                showSnackStore = false
                feedWithSnack(snack)
            }
        }
        .sheet(isPresented: $showRecharge) {
            RechargeSheet()
        }
        .sheet(isPresented: $showEnergyInfo) {
            EnergyInfoSheet()
        }
    }

    // MARK: 1. Header

    private var header: some View {
        // TODO: wire real daysTogether from persisted onboarding date.
        Text("Day 1 with KOMO")
            .font(Theme.Font.title(20))
            .foregroundStyle(Theme.Palette.inkForest)
            .shadow(color: .white.opacity(0.55), radius: 12, y: 1)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: 2. Insight card — speech from KOMO, above the blob

    private var insightCard: some View {
        let insight = app.currentInsight
        // Second block label softens when the insight is an affirmation (Agree).
        let moveLabel = insight.action == .agree ? "A gentle note" : "Quick win"
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("✨ Insight")
                    .font(Theme.Font.label(12, weight: .bold))
                    .foregroundStyle(Theme.Palette.leaf)
                Text(insight.noticed)
                    .font(Theme.Font.body(15, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(moveLabel)
                    .font(Theme.Font.label(12, weight: .bold))
                    .foregroundStyle(Theme.Palette.leaf)
                Text(insight.tinyMove)
                    .font(Theme.Font.body(15, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                // Primary action (Remind me / Start / Agree)
                Button {
                    withAnimation(.spring) { app.addReminder() }
                    scheduleReminderReset()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: app.reminderAdded ? "checkmark" : insight.action.systemImage)
                            .foregroundStyle(Theme.Palette.leaf)
                        Text(app.reminderAdded ? "Reminder set" : insight.action.label)
                            .font(Theme.Font.label(14, weight: .semibold))
                            .foregroundStyle(Theme.Palette.inkMuted)
                    }
                    .frame(height: 42).padding(.horizontal, 16)
                    .background(Color.white.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip)
                        .strokeBorder(Color(hex: 0x3C5A46).opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.reminderAdded ? "Reminder set" : insight.action.label)

                // Secondary "Ignore" — real button, lighter styling, same height.
                Button {
                    withAnimation(.spring) { app.ignoreCurrentInsight() }
                } label: {
                    Text("Ignore")
                        .font(Theme.Font.label(14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.inkMuted.opacity(0.85))
                        .frame(height: 42).padding(.horizontal, 16)
                        .background(Color.white.opacity(0.25),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip)
                            .strokeBorder(Color(hex: 0x3C5A46).opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Dismiss this insight")

                Spacer()
            }
        }
        .padding(Theme.Space.cardPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Native iOS 26 Liquid Glass container (same pattern as the reference
        // LiquidGlassHContainer example): padded content, then .glassEffect
        // in a rounded-rectangle shape. No manual fill/stroke/shadow — the
        // modifier renders the whole glass surface with its own frost + rim.
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: Theme.Radius.insight, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: 3. Companion (blob) — tap = small reaction, no navigation

    private var companionStage: some View {
        VStack(spacing: 4) {
            ZStack {
                BlobView(size: 170, cute: true, hue: app.dailyHue,
                         style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                         motion: app.character.motion,
                         onTap: { blobReact() },
                         namespace: namespace, geometryID: "companion")
                    .scaleEffect(blobSquash)
                    .accessibilityLabel("\(app.companionDisplayName), your companion. Double tap for a reaction.")

                if showHeart {
                    Text("❤️")
                        .font(.system(size: 22))
                        .offset(y: -70)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ForEach(feedItems) { item in
                    FeedItemView(item: item) { remove(item) }
                }
            }
            .frame(width: 170, height: 170)

            // ground shadow
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.18), .clear],
                                     center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 120, height: 14)
                .blur(radius: 3)
                .offset(y: -6)
        }
    }

    // MARK: 4. Energy hero — the readable headline of the screen

    private var energyHero: some View {
        let level = app.homeEnergyLevel
        let percent = app.homeEnergyPercent
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S ENERGY")
                        .font(Theme.Font.label(11, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.28), radius: 6, y: 1)
                        .tracking(1.2)

                    HStack(spacing: 6) {
                        Text(level.word)
                            .font(Theme.Font.display(30))
                            .foregroundStyle(level.color)
                            .shadow(color: .black.opacity(0.45), radius: 8, y: 1)

                        Button { showEnergyInfo = true } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("What shapes today's energy")
                    }
                }
                Spacer()
                Text("\(percent)%")
                    .font(Theme.Font.title(22))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
                    .accessibilityHidden(true)
            }

            // Capsule bar — gradient colored by EnergyLevel so word + bar + %
            // read as one signal. Fill width tracks `percent`.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.24))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [level.color.opacity(0.85), level.color],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(14, geo.size.width * CGFloat(percent) / 100))
                        .overlay(alignment: .trailing) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.trailing, 6)
                        }
                        .shadow(color: level.color.opacity(0.55), radius: 8)
                        .animation(.spring(response: 0.5), value: percent)
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's energy: \(level.word), \(percent) percent.")
    }

    // MARK: 5. Action area — Feed / Reflect / Recharge

    private var actionArea: some View {
        GlassCluster(spacing: 10) {
            HStack(spacing: 10) {
                // Feed — fruit apple with no bite. SF Symbols has no whole-apple
                // glyph and emojis ignore .foregroundStyle, so we render the 🍎
                // glyph as a white silhouette by masking a white rectangle with
                // the emoji shape — matches the white icon color of Reflect and
                // Recharge.
                ActionButton(title: "Feed", action: { showSnackStore = true }) {
                    Color.white
                        .frame(width: 34, height: 34)
                        .mask {
                            Text("🍎")
                                .font(.system(size: 34))
                        }
                }
                .frame(width:100, height:100)
                .glassEffect(.clear.interactive(), in:Circle())

                ActionButton(title: "Reflect", action: {
                    withAnimation(.spring(response: 0.35)) { app.advanceInsight() }
                }) {
                    Image(systemName: "lightbulb.fill")
                }
                .frame(width:100, height:100)
                .glassEffect(.clear.interactive(), in:Circle())

                ActionButton(title: "Recharge", action: { showRecharge = true }) {
                    Image(systemName: "bolt.fill")
                }
                .frame(width:100, height:100)
                .glassEffect(.clear.interactive(), in:Circle())
            }
        }
    }

    // MARK: - Actions

    /// Small emotional reaction on blob tap: brief squash + a tiny rising heart.
    /// Reduce Motion: just the heart, no scale.
    private func blobReact() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.15)) { showHeart = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation { showHeart = false }
            }
            return
        }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) { blobSquash = 0.9 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { blobSquash = 1.0 }
        }
        withAnimation(.easeOut(duration: 0.25)) { showHeart = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeIn(duration: 0.35)) { showHeart = false }
        }
    }

    private func feedWithSnack(_ snack: Snack) {
        let item = FeedItem(icon: snack.icon)
        feedItems.append(item)
        // Energy update fires after the drop lands (feels causal).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            withAnimation(.spring) { app.feed(snack) }
        }
    }

    private func remove(_ item: FeedItem) {
        feedItems.removeAll { $0.id == item.id }
    }

    private func scheduleReminderReset() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            app.reminderAdded = false
        }
    }
}

// MARK: - Action button (glass)
//
// Icon is a ViewBuilder so callers can pass an SF Symbol (Image) or an emoji
// (Text) — needed for Feed since SF Symbols has no whole-apple-fruit glyph.

private struct ActionButton<Icon: View>: View {
    var title: String
    var action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                icon()
                    .foregroundStyle(.white)
                    // Slightly bigger than before, consistent across all three.
                    .font(.system(size: 30, weight: .medium))
                Text(title)
                    .font(Theme.Font.label(14, weight: .bold))
                    .foregroundStyle(.white)   // matches the icon color
            }
            .frame(maxWidth: .infinity).frame(height: 96)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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

// MARK: - Snack store sheet (Feed)

private struct SnackStoreSheet: View {
    var snacks: [Snack]
    var onPick: (Snack) -> Void

    // Locked demo entries — hint at future variety without shipping content yet.
    private let locked: [(name: String, icon: String)] = [
        ("Berry",  "🫐"),
        ("Cookie", "🍪"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("Snack store")
                    .font(Theme.Font.title(19))
                Text("Feed one to KOMO.")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)

            // Available
            VStack(spacing: 8) {
                ForEach(snacks) { snack in
                    Button {
                        onPick(snack)
                    } label: {
                        HStack(spacing: 12) {
                            Text(snack.icon).font(.system(size: 28))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(snack.name)
                                    .font(Theme.Font.label(15))
                                    .foregroundStyle(.primary)
                                Text("+\(snack.energyBoost)% energy")
                                    .font(Theme.Font.body(12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.white.opacity(0.7),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Feed \(snack.name), +\(snack.energyBoost)% energy")
                }
            }
            .padding(.horizontal, 20)

            // Locked
            VStack(alignment: .leading, spacing: 6) {
                Text("LOCKED")
                    .font(Theme.Font.label(10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.1)
                    .padding(.leading, 4)

                VStack(spacing: 8) {
                    ForEach(locked, id: \.name) { snack in
                        HStack(spacing: 12) {
                            Text(snack.icon).font(.system(size: 22))
                            Text(snack.name)
                                .font(Theme.Font.label(14))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.white.opacity(0.35),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                        .opacity(0.7)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            Text("Earned through rest and movement.")
                .font(Theme.Font.body(11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.bottom, 14)
        }
        .padding(.top, 4)
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Recharge sheet (1-minute breathing)

private struct RechargeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expanded = false
    @State private var caption = "Breathe in…"
    @State private var seconds = 60
    @State private var running = true

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 4).padding(.top, 8)

            VStack(spacing: 4) {
                Text("1-minute breath")
                    .font(Theme.Font.title(20))
                Text("A quiet minute. KOMO breathes with you.")
                    .font(Theme.Font.body(13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.green.opacity(0.55), Color.green.opacity(0.08)],
                                         center: .center, startRadius: 20, endRadius: 130))
                    .frame(width: 200, height: 200)
                    .scaleEffect(reduceMotion ? 0.9 : (expanded ? 1.05 : 0.7))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 4), value: expanded)

                Text(caption)
                    .font(Theme.Font.title(18))
                    .foregroundStyle(.primary)
            }

            Text("\(seconds)s")
                .font(Theme.Font.title(24))
                .foregroundStyle(.secondary)

            Button {
                running = false
                dismiss()
            } label: {
                Text("Done")
                    .font(Theme.Font.label(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)

            Spacer(minLength: 8)
        }
        .padding(.bottom, 24)
        .presentationDetents([.medium, .large])
        .task {
            // Alternate breath in/out over 4s cycles for a total of ~60s.
            while running && seconds > 0 {
                caption = "Breathe in…"
                expanded = true
                try? await Task.sleep(for: .seconds(4))
                if !running { break }
                caption = "Breathe out…"
                expanded = false
                try? await Task.sleep(for: .seconds(4))
                seconds = max(0, seconds - 8)
            }
            if running { dismiss() }
        }
    }
}

// MARK: - Energy info sheet (placeholder — TODO: signal summary)

private struct EnergyInfoSheet: View {
    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 4).padding(.top, 8)

            Text("What shapes today's energy")
                .font(Theme.Font.title(18))
                .padding(.top, 6)
            // TODO: real signal summary (sleep + movement + calendar load).
            Text("Based on sleep, movement, and calendar load.")
                .font(Theme.Font.body(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.bottom, 24)
        .presentationDetents([.medium])
    }
}
