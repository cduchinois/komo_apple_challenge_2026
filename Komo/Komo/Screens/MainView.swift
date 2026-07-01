//  MainView.swift
//  Komo
//
//  Home — the single question this screen answers: "What is my energy today,
//  and what should I do next?" Layout, top to bottom:
//    1. Header — "Day N with KOMO"
//    2. Reflection card (observation / suggestion / per-card buttons)
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
    @State private var showNoteSheet = false
    @State private var showFocusTimer = false
    @State private var focusDurationSeconds: Int = 180
    // Toast for brief confirmations after reflection actions.
    @State private var toast: String? = nil

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
        // Shared horizontal margin token → reflection card, energy hero, bar,
        // and action row all sit inside the same symmetric inset.
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, 8)   // sits just below the safe-area inset
        .overlay(alignment: .top) { toastOverlay }
        .sheet(isPresented: $showSnackStore) {
            SnackStoreSheet { snack in
                showSnackStore = false
                feedWithSnack(snack)
            }
            .environment(app)
        }
        .sheet(isPresented: $showRecharge) {
            RechargeSheet()
        }
        .sheet(isPresented: $showEnergyInfo) {
            EnergyBreakdownSheet(breakdown: app.data.energyBreakdown())
        }
        .sheet(isPresented: $showNoteSheet) {
            WriteNoteSheet(observation: app.currentReflection.observation,
                           suggestion: app.currentReflection.suggestion) { note in
                app.saveCurrentReflection(note: note)
                showNoteSheet = false
                flashToast("Note saved")
                app.advanceReflection()
            }
        }
        .fullScreenCover(isPresented: $showFocusTimer) {
            FocusTimerView(durationSeconds: focusDurationSeconds) {
                showFocusTimer = false
                // Reward on completion: blob love.
                blobReact()
                flashToast("Session complete")
                app.advanceReflection()
            }
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

    // MARK: 2. Reflection card — dynamic per-card buttons

    private var insightCard: some View {
        let r = app.currentReflection
        // Second block label softens when the card is a pure observation.
        let secondLabel: String = (r.type == .reflect) ? "A gentle note" : "Quick win"
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("✨ Insight")
                    .font(Theme.Font.label(12, weight: .bold))
                    .foregroundStyle(Theme.Palette.leaf)
                Text(r.observation)
                    .font(Theme.Font.body(15, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(secondLabel)
                    .font(Theme.Font.label(12, weight: .bold))
                    .foregroundStyle(Theme.Palette.leaf)
                Text(r.suggestion)
                    .font(Theme.Font.body(15, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionRow(for: r)
        }
        .padding(Theme.Space.cardPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Native iOS 26 Liquid Glass container.
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: Theme.Radius.insight, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    /// Renders the per-card buttons in the order declared by the reflection.
    /// `.next` is always styled as a lighter secondary button.
    @ViewBuilder
    private func actionRow(for r: Reflection) -> some View {
        HStack(spacing: 8) {
            ForEach(r.actions) { action in
                Button {
                    handle(action, for: r)
                } label: {
                    reflectionChip(action)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.label)
            }
            Spacer(minLength: 0)
        }
    }

    /// Chip visual for a Reflection action. `.next` reads lighter.
    @ViewBuilder
    private func reflectionChip(_ action: ReflectionAction) -> some View {
        let isSecondary = action.isSecondary
        HStack(spacing: 6) {
            Image(systemName: action.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSecondary ? Theme.Palette.inkMuted.opacity(0.7) : Theme.Palette.leaf)
            Text(action.label)
                .font(Theme.Font.label(13, weight: .semibold))
                .foregroundStyle(isSecondary ? Theme.Palette.inkMuted.opacity(0.85) : Theme.Palette.inkMuted)
                .lineLimit(1)
        }
        .frame(height: 38).padding(.horizontal, 12)
        .background(Color.white.opacity(isSecondary ? 0.25 : 0.55),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip)
            .strokeBorder(Color(hex: 0x3C5A46).opacity(isSecondary ? 0.14 : 0.18), lineWidth: 1))
    }

    /// Route a reflection action to its handler.
    private func handle(_ action: ReflectionAction, for r: Reflection) {
        switch action {
        case .addToCalendar:
            app.addCurrentReflectionToCalendar()
            flashToast("Added to calendar")
        case .save:
            app.saveCurrentReflection(note: nil)
            flashToast("Saved to Cards")
        case .writeNote:
            showNoteSheet = true
        case .remindMe:
            app.remindCurrentReflection()
            flashToast("Added to reminders")
            scheduleReminderReset()
        case .startNow:
            focusDurationSeconds = r.suggestedDurationSeconds
            showFocusTimer = true
        case .done:
            app.markCurrentDone()
            flashToast("Nice")
        case .next:
            withAnimation(.spring(response: 0.35)) { app.advanceReflection() }
        }
    }

    // MARK: 3. Companion (blob) — tap = small reaction, no navigation

    private var companionStage: some View {
        // Home spacing was tuned for a 170pt blob; now uses the shared
        // KomoMascotView.standardSize (220pt). The insight-card gap above
        // and the energy-hero gap below already absorb the extra height
        // via their .padding(.top) offsets.
        VStack(spacing: 4) {
            ZStack {
                // TODO(mascot-rollout): character.motion / hue / style / eyes /
                // legs dropped — manual's default idle is used everywhere.
                // Tap reaction (blobReact) + feed drop/rise + love-back still
                // wire through: the scaleEffect(blobSquash) and the feed/heart
                // overlays live in the same ZStack and target the mascot's
                // center identically to before.
                KomoMascotView(size: KomoMascotView.standardSize,
                               onTap: { blobReact() },
                               namespace: namespace,
                               geometryID: "companion",
                               accessibilityLabelText: "\(app.companionDisplayName), your companion. Double tap for a reaction.")
                    .scaleEffect(blobSquash)

                if showHeart {
                    Text("❤️")
                        .font(.system(size: 22))
                        .offset(y: -90)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ForEach(feedItems) { item in
                    FeedItemView(item: item) { remove(item) }
                }
            }
            .frame(width: KomoMascotView.standardSize, height: KomoMascotView.standardSize)

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
                        .accessibilityLabel("Why \(percent) percent")
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
                // Feed — fruit apple silhouette (SF Symbols has no whole-apple
                // glyph; emojis ignore .foregroundStyle so we mask a white
                // rectangle with the 🍎 shape to match the other white icons).
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
                    withAnimation(.spring(response: 0.35)) { app.advanceReflection() }
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

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            Text(toast)
                .font(Theme.Font.label(13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.65),
                            in: Capsule(style: .continuous))
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func flashToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeIn(duration: 0.25)) { toast = nil }
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
        // Energy update + blob "love" reaction fire after the drop lands
        // (feels causal). Stock is decremented via the same call.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            withAnimation(.spring) { app.feed(snackID: snack.id) }
            blobReact()
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
                    .font(.system(size: 30, weight: .medium))
                Text(title)
                    .font(Theme.Font.label(14, weight: .bold))
                    .foregroundStyle(.white)
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

// MARK: - Snack store sheet (Feed) — stock-aware

private struct SnackStoreSheet: View {
    @Environment(AppState.self) private var app
    var onPick: (Snack) -> Void

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

            // Available snacks — greyed out & disabled when stock hits 0.
            VStack(spacing: 8) {
                ForEach(app.snacks) { snack in
                    let available = snack.stock > 0
                    Button {
                        if available { onPick(snack) }
                    } label: {
                        HStack(spacing: 12) {
                            Text(snack.icon).font(.system(size: 28))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(snack.name)
                                    .font(Theme.Font.label(15))
                                    .foregroundStyle(.primary)
                                Text("+\(formatBoost(snack.energyBoost)) energy · \(snack.stock) left")
                                    .font(Theme.Font.body(12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if available {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("Empty")
                                    .font(Theme.Font.label(11, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.gray.opacity(0.18),
                                                in: Capsule(style: .continuous))
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.white.opacity(available ? 0.7 : 0.35),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                        .opacity(available ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                    .accessibilityLabel("Feed \(snack.name), \(available ? "\(snack.stock) left" : "empty")")
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
                    ForEach(AppState.lockedSnackPreviews, id: \.name) { snack in
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

            Text("Earned through rest and movement (sleep, workouts).")
                .font(Theme.Font.body(11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 14)
        }
        .padding(.top, 4)
        .presentationDetents([.fraction(0.55)])
        .presentationDragIndicator(.visible)
    }

    /// "+1", "+0.5" — trim trailing .0 for the whole-number case.
    private func formatBoost(_ x: Double) -> String {
        if x == x.rounded() { return "\(Int(x))" }
        return String(format: "%.1f", x)
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

// MARK: - Energy breakdown sheet ("Why 72%")
//
// Opened by the (i) icon beside the energy word on Home. Reads its data from
// the provider (`app.data.energyBreakdown()`) — the view does no scoring.
// Two grouped sections (recovery + load); each row has a signed value and a
// thin bar scaled to the largest absolute value in its group. The footer line
// spells out the math: `{recovery} recharged - {load} load = {percent}%`.

private struct EnergyBreakdownSheet: View {
    let breakdown: EnergyBreakdown
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Colors — recovery reads as the charged-green from the EnergyLevel
    /// palette; load reads amber. Text stays in normal ink; only bars carry color.
    private let recoveryColor = Color(hex: 0x4EA35E)
    private let loadColor     = Color(hex: 0xE68A3E)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                factorSection(
                    title: "what recharged you",
                    totalText: "+\(formattedInt(breakdown.recoveryTotal))",
                    items: breakdown.recoveryItems,
                    color: recoveryColor
                )

                factorSection(
                    title: "what drew it down",
                    totalText: signedString(breakdown.loadTotal),
                    items: breakdown.loadItems,
                    color: loadColor
                )

                footer
            }
            .padding(.horizontal, Theme.Space.screenH)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Energy breakdown, \(breakdown.percent) percent, \(breakdown.word).")
    }

    // MARK: Header

    private var header: some View {
        let level = EnergyLevel.from(percent: breakdown.percent)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Today's energy")
                .font(Theme.Font.label(11, weight: .heavy))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(breakdown.percent)%")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(level.color)
                Text(breakdown.word)
                    .font(Theme.Font.title(22))
                    .foregroundStyle(.primary)
            }

            Text("based on sleep, movement, stress, and calendar load")
                .font(Theme.Font.body(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Section

    @ViewBuilder
    private func factorSection(
        title: String,
        totalText: String,
        items: [EnergyContribution],
        color: Color
    ) -> some View {
        let maxAbs = items.map { abs($0.points) }.max() ?? 1

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(Theme.Font.label(11, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Spacer()
                Text(totalText)
                    .font(Theme.Font.label(14, weight: .heavy))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }

            VStack(spacing: 10) {
                ForEach(items) { item in
                    contributionRow(item, maxAbsInGroup: maxAbs, color: color)
                }
            }
        }
    }

    // MARK: Row

    @ViewBuilder
    private func contributionRow(
        _ item: EnergyContribution,
        maxAbsInGroup: Double,
        color: Color
    ) -> some View {
        let width: CGFloat = maxAbsInGroup > 0 ? CGFloat(abs(item.points) / maxAbsInGroup) : 0

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.label)
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(signedString(item.points))
                    .font(Theme.Font.label(14, weight: .heavy))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(Theme.Font.body(12))
                    .foregroundStyle(.secondary)
            }
            // Thin proportional bar. Reduce Motion: no growth animation.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * width))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: width)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label), \(signedSpokenString(item.points))\(item.detail.map { ". \($0)" } ?? "")")
    }

    // MARK: Footer

    private var footer: some View {
        let recovery = formattedInt(breakdown.recoveryTotal)
        let load = formattedInt(abs(breakdown.loadTotal))
        return Text("\(recovery) recharged - \(load) load = \(breakdown.percent)%")
            .font(Theme.Font.body(12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    // MARK: Formatters

    private func formattedInt(_ x: Double) -> String {
        String(Int(x.rounded()))
    }

    private func signedString(_ x: Double) -> String {
        let n = Int(x.rounded())
        return n >= 0 ? "+\(n)" : "\(n)"    // Int keeps the "-" sign
    }

    private func signedSpokenString(_ x: Double) -> String {
        let n = Int(abs(x).rounded())
        return x >= 0 ? "plus \(n)" : "minus \(n)"
    }
}

// MARK: - Write-note sheet (Reflect / .writeNote)

private struct WriteNoteSheet: View {
    var observation: String
    var suggestion: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(.secondary.opacity(0.4))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Text("Write a note")
                .font(Theme.Font.title(19))
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(observation)
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(.primary)
                Text(suggestion)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            TextField("Your note", text: $noteText, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(Color.gray.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .padding(.horizontal, 20)
                .focused($focused)

            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") { onSave(noteText) }
                    .buttonStyle(.borderedProminent)
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .presentationDetents([.medium])
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            focused = true
        }
    }
}

// MARK: - Focus timer (Reflect / .startNow)
//
// Full-screen blocking countdown. User has a discreet hold-to-exit so they are
// never trapped. On completion, dismisses and calls `onComplete`. Reduce Motion:
// no ring animation, just the mm:ss text.

private struct FocusTimerView: View {
    var durationSeconds: Int
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var remaining: Int
    @State private var startedAt: Date = .now
    @State private var holdProgress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>? = nil
    @State private var finished = false

    init(durationSeconds: Int, onComplete: @escaping () -> Void) {
        self.durationSeconds = durationSeconds
        self.onComplete = onComplete
        self._remaining = State(initialValue: durationSeconds)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 32) {
                Text("Focus")
                    .font(Theme.Font.label(12, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.65))
                    .tracking(2)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 6)
                        .frame(width: 240, height: 240)
                    Circle()
                        .trim(from: 0, to: max(0, CGFloat(remaining) / CGFloat(durationSeconds)))
                        .stroke(Color.white.opacity(0.9),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 240, height: 240)
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 0.5), value: remaining)

                    Text(timeString(remaining))
                        .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }

                Text("Keep this screen open.")
                    .font(Theme.Font.body(13))
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                // Hold-to-exit — discreet, never traps the user.
                holdToExitButton
                    .padding(.bottom, 40)
            }
            .padding(.top, 60)
        }
        .task { await runCountdown() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus timer, \(timeString(remaining)) remaining")
    }

    private var holdToExitButton: some View {
        ZStack {
            Capsule()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                .frame(width: 200, height: 44)
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 200 * holdProgress, height: 44)
                .frame(width: 200, alignment: .leading)
                .clipShape(Capsule())
            Text(holdProgress > 0 ? "Release to stay" : "Hold to exit")
                .font(Theme.Font.label(13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .contentShape(Capsule())
        .gesture(
            LongPressGesture(minimumDuration: 1.2)
                .onEnded { _ in
                    finished = true
                    dismiss()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if holdTask == nil {
                        startHoldFill()
                    }
                }
                .onEnded { _ in
                    holdTask?.cancel()
                    holdTask = nil
                    withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
                }
        )
    }

    private func startHoldFill() {
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let p = min(1, elapsed / 1.2)
                holdProgress = CGFloat(p)
                if p >= 1 { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private func runCountdown() async {
        while remaining > 0 && !finished {
            try? await Task.sleep(for: .seconds(1))
            if finished { return }
            remaining -= 1
        }
        if !finished {
            finished = true
            onComplete()
        }
    }

    private func timeString(_ s: Int) -> String {
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}
