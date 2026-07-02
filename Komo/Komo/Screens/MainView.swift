//  MainView.swift
//  Komo
//
//  Home. New composition, top to bottom:
//    1. Header — "Day N with KOMO"
//    2. Energy hero — moved up under the header (word + info + percent + bar)
//    3. Reflection card
//    4. Companion (blob) — visual anchor of the lower half, with a small
//       KOMO-level pill on the head side
//    5. Action area — three glass bubbles arranged in a shallow arc around
//       the mascot: Feed centered + lower + full size, Reflect (left) and
//       Recharge (right) smaller, slightly higher, subtly less opaque.
//  Feed spends stars now (no more snack store). Stars are earned by
//  completing a Recharge session or a Focus timer.

import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var app
    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID

    // In-flight treats animated on top of the blob.
    @State private var feedItems: [FeedItem] = []
    // Blob tap reaction (squash + tiny heart).
    @State private var blobSquash: CGFloat = 1.0
    @State private var showHeart = false
    // Shine ring emitted from KOMO when fed a star.
    @State private var shineID: Int = 0
    // Sheets
    @State private var showRecharge = false
    @State private var showEnergyInfo = false
    @State private var showNoteSheet = false
    @State private var showFocusTimer = false
    @State private var focusDurationSeconds: Int = 180
    // Toast for brief confirmations after reflection actions.
    @State private var toast: String? = nil
    @State private var didPromptNotifications = false

    private var snapshot: EnergySnapshot { app.data.currentSnapshot() }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 6)

            energyHero
                .padding(.top, 14)

            insightCard
                .padding(.top, 14)

            companionStage
                .padding(.top, 10)

            actionArea
                // Pulled up so the arc sits AROUND the mascot, not detached
                // below it.
                .padding(.top, -30)
        }
        // Shared horizontal margin token — everything lines up on the same
        // symmetric inset.
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, 8)   // sits just below the safe-area inset
        .overlay(alignment: .top) { toastOverlay }
        .sheet(isPresented: $showRecharge) {
            RechargeSheet { completed in
                guard completed else { return }
                // Recharge completion → +1 star.
                app.earnStar()
                flashToast(String(localized: "Recharge complete · ★ +1"))
            }
        }
        .sheet(isPresented: $showEnergyInfo) {
            EnergyBreakdownSheet(breakdown: app.data.energyBreakdown())
        }
        .sheet(isPresented: $showNoteSheet) {
            WriteNoteSheet(observation: app.currentReflection.observation,
                           suggestion: app.currentReflection.suggestion) { note in
                app.saveCurrentReflection(note: note)
                showNoteSheet = false
                flashToast(String(localized: "Note saved"))
                app.advanceReflection()
            }
        }
        .fullScreenCover(isPresented: $showFocusTimer) {
            FocusTimerView(durationSeconds: focusDurationSeconds) {
                showFocusTimer = false
                // Focus completion → blob love + +1 star + advance.
                blobReact()
                app.earnStar()
                flashToast(String(localized: "Session complete · ★ +1"))
                app.advanceReflection()
            }
        }
        .task {
            app.publishWidgetEnergySnapshot()
            await promptNotificationsAfterOnboarding()
        }
    }

    /// Ask for notification permission once the user reaches Home — never during onboarding.
    private func promptNotificationsAfterOnboarding() async {
        guard !didPromptNotifications else { return }
        guard permissions.notifications == .notDetermined else { return }
        didPromptNotifications = true
        // Brief pause so the blob screen renders before the system sheet.
        try? await Task.sleep(for: .milliseconds(700))
        await permissions.requestNotifications()
    }

    // MARK: 1. Header

    private var header: some View {
        // TODO: wire real daysTogether from persisted onboarding date.
        Text("Day 1 with KOMO", comment: "Home header showing days with KOMO")
            .font(Theme.Font.title(20))
            .foregroundStyle(Theme.Palette.inkForest)
            .shadow(color: .white.opacity(0.55), radius: 12, y: 1)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: 2. Reflection card — dynamic per-card buttons

    private var insightCard: some View {
        let r = app.currentReflection
        // Second block label softens when the card is a pure observation.
        let secondLabel: String = (r.type == .reflect)
            ? String(localized: "A gentle note")
            : String(localized: "Quick win")
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("✨ Insight", comment: "Insight card section title")
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
            flashToast(String(localized: "Added to calendar"))
        case .save:
            app.saveCurrentReflection(note: nil)
            flashToast(String(localized: "Saved to Cards"))
        case .writeNote:
            showNoteSheet = true
        case .remindMe:
            app.remindCurrentReflection()
            flashToast(String(localized: "Added to reminders"))
            scheduleReminderReset()
        case .startNow:
            focusDurationSeconds = r.suggestedDurationSeconds
            showFocusTimer = true
        case .done:
            app.markCurrentDone()
            flashToast(String(localized: "Nice"))
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
                // Shine ring — emitted from KOMO when fed a star. Every feed
                // bumps `shineID`, spawning a fresh ring below the mascot.
                ShineRing(id: shineID, size: KomoMascotView.standardSize)
                    .allowsHitTesting(false)

                KomoMascotView(size: KomoMascotView.standardSize,
                               onTap: { blobReact() },
                               namespace: namespace,
                               geometryID: "companion",
                               accessibilityLabelText: "\(app.companionDisplayName), your companion. Double tap for a reaction.")
                    .scaleEffect(blobSquash)
                    .overlay(alignment: .topTrailing) {
                        LevelBadge(level: app.komoLevel, progress: app.komoLevelProgress)
                            .offset(x: 6, y: 4)
                    }

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
                    Text("TODAY'S ENERGY", comment: "Energy hero section label")
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
                        .accessibilityLabel(String(format: String(localized: "Why %lld percent"), percent))
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
        .accessibilityLabel(String(format: String(localized: "Today's energy: %1$@, %2$lld percent."), level.word, percent))
    }

    // MARK: 5. Action area — Reflect / Feed (center) / Recharge in an arc
    //
    // The three glass bubbles curve around KOMO rather than sitting in a flat
    // row. Feed is the center bubble at full 100pt, positioned slightly lower
    // (closest to the viewer). Reflect and Recharge sit at ~78pt and are
    // offset slightly higher + subtly dimmer to read as receding into depth.

    private var actionArea: some View {
        GlassCluster(spacing: 10) {
            ZStack {
                // Reflect — side bubble, upper-left, dimmer + smaller.
                // Floating: slightly shorter cycle, phase-shifted so it never
                // beats in unison with the others.
                ActionButton(title: "Reflect", action: {
                    withAnimation(.spring(response: 0.35)) { app.advanceReflection() }
                }) {
                    Image(systemName: "lightbulb.fill")
                }
                .frame(width: 78, height: 78)
                .glassEffect(.clear.interactive(), in: Circle())
                .opacity(0.85)
                .offset(x: -100, y: -14)
                .modifier(FloatingDrift(amplitude: 4, period: 4.5, phase: 0.30))

                // Recharge — side bubble, upper-right, dimmer + smaller.
                ActionButton(title: "Recharge", action: { showRecharge = true }) {
                    Image(systemName: "bolt.fill")
                }
                .frame(width: 78, height: 78)
                .glassEffect(.clear.interactive(), in: Circle())
                .opacity(0.85)
                .offset(x: 100, y: -14)
                .modifier(FloatingDrift(amplitude: 5, period: 5.5, phase: 0.60))

                // Feed — center bubble, full-size, lower, closest to viewer.
                // Icon = star.fill; tiny "+N" badge on the top-right.
                ActionButton(title: "Feed", action: { feedTap() }) {
                    Image(systemName: "star.fill")
                }
                .frame(width: 100, height: 100)
                .glassEffect(.clear.interactive(), in: Circle())
                .overlay(alignment: .topTrailing) {
                    StarCountBadge(count: app.starBalance)
                        .offset(x: 6, y: -4)
                }
                .offset(y: 22)
                .modifier(FloatingDrift(amplitude: 5, period: 5.0, phase: 0.00))
            }
            .frame(height: 130)
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

    // MARK: Feed with a star

    /// Tap on the Feed bubble. Spends one star if available, otherwise nudges
    /// the user to earn one via Recharge / Focus.
    private func feedTap() {
        if app.starBalance > 0 {
            feedWithStar()
        } else {
            flashToast(String(localized: "Recharge to earn stars for KOMO"))
        }
    }

    /// Drop a star into KOMO. Reuses the existing FeedItem/FeedItemView drop
    /// animation, then applies the energy boost, emits a shine ring and a
    /// blob love reaction when the drop lands.
    private func feedWithStar() {
        let ok = app.feedKomoWithStar()
        guard ok else { return }
        let item = FeedItem(icon: "⭐")
        feedItems.append(item)

        // Blob love + shine ring fire after the star lands (feels causal).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            withAnimation(.spring) { shineID &+= 1 }
            app.publishWidgetEnergySnapshot()
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
    var title: LocalizedStringKey
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

// MARK: - Slow vertical floating for action bubbles
//
// A continuous, gentle vertical drift (sinusoidal ease-in-out). Each bubble
// gets its own `period` and `phase` so the three never move in unison.
// Bypassed entirely when `accessibilityReduceMotion` is on.

private struct FloatingDrift: ViewModifier {
    var amplitude: CGFloat   // pt, peak-to-center
    var period: Double       // seconds per full cycle
    var phase: Double        // 0..1 phase offset

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let p = (t / period + phase).truncatingRemainder(dividingBy: 1)
                let y = amplitude * CGFloat(sin(p * 2 * .pi))
                content.offset(y: y)
            }
        }
    }
}

// MARK: - Star count badge (small "+N" pill on the Feed bubble)
//
// The button icon is already a star — the badge only shows the spendable
// count with a "+" prefix. Hidden entirely when there are no stars.

private struct StarCountBadge: View {
    var count: Int

    var body: some View {
        if count > 0 {
            Text("+\(count)")
                .font(Theme.Font.label(11, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0xFFD54D))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule(style: .continuous))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .accessibilityLabel("\(count) stars available")
        }
    }
}

// MARK: - Level badge (KOMO's growing level, rendered on the head side)

private struct LevelBadge: View {
    var level: Int
    var progress: Double   // 0..1 toward next level

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Lv \(level)")
                .font(Theme.Font.label(10, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(hex: 0x2F6B41).opacity(0.9),
                            in: Capsule(style: .continuous))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule()
                        .fill(Color(hex: 0x93D76E))
                        .frame(width: max(4, geo.size.width * CGFloat(progress)))
                        .shadow(color: Color(hex: 0x93D76E).opacity(0.55), radius: 4)
                }
            }
            .frame(width: 34, height: 4)
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        .accessibilityElement()
        .accessibilityLabel("Level \(level)")
    }
}

// MARK: - Shine ring (fires when KOMO is fed a star)
//
// A single concentric ring that expands and fades outward from KOMO. Bumping
// `id` re-triggers the animation. Reduce Motion: renders as a static circle.

private struct ShineRing: View {
    var id: Int
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t: CGFloat = 0

    var body: some View {
        Circle()
            .stroke(Color.white.opacity(reduceMotion ? 0 : (1 - t) * 0.7),
                    lineWidth: 3)
            .frame(width: size, height: size)
            .scaleEffect(1 + t * 0.6)
            .onChange(of: id) { _, _ in
                guard !reduceMotion else { return }
                t = 0
                withAnimation(.easeOut(duration: 1.1)) { t = 1 }
            }
    }
}

// MARK: - Recharge sheet (1-minute breathing)

private struct RechargeSheet: View {
    var onComplete: (_ completed: Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expanded = false
    @State private var caption = String(localized: "Breathe in…")
    @State private var seconds = 60
    @State private var running = true
    @State private var didComplete = false

    private func updateBreathingPhase(elapsed: Int) {
        if elapsed % 8 < 4 {
            caption = String(localized: "Breathe in…")
            expanded = true
        } else {
            caption = String(localized: "Breathe out…")
            expanded = false
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 4).padding(.top, 8)

            VStack(spacing: 4) {
                Text("1-minute breath", comment: "Recharge sheet title")
                    .font(Theme.Font.title(20))
                Text("A quiet minute. KOMO breathes with you.", comment: "Recharge sheet subtitle")
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

            Text(String(format: String(localized: "%llds"), seconds))
                .font(Theme.Font.title(24))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                guard seconds == 0 else { return }
                running = false
                if !didComplete {
                    didComplete = true
                    onComplete(true)
                }
                dismiss()
            } label: {
                Text("Done", comment: "Recharge sheet done button")
                    .font(Theme.Font.label(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(seconds > 0)
            .padding(.horizontal, 24)

            Spacer(minLength: 8)
        }
        .padding(.bottom, 24)
        .presentationDetents([.medium, .large])
        .onDisappear {
            running = false
        }
        .task {
            updateBreathingPhase(elapsed: 0)
            for tick in 1...60 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                if Task.isCancelled { return }
                guard running else { return }
                seconds = 60 - tick
                updateBreathingPhase(elapsed: tick)
            }
            if Task.isCancelled { return }
            guard running else { return }
            if !didComplete {
                didComplete = true
                onComplete(true)
            }
            dismiss()
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
                    title: String(localized: "what recharged you"),
                    totalText: "+\(formattedInt(breakdown.recoveryTotal))",
                    items: breakdown.recoveryItems,
                    color: recoveryColor,
                    emptyLine: String(localized: "nothing lifting you up right now.")
                )

                factorSection(
                    title: String(localized: "what drew it down"),
                    totalText: signedString(breakdown.loadTotal),
                    items: breakdown.loadItems,
                    color: loadColor,
                    emptyLine: String(localized: "nothing pulling you down right now.")
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
        .accessibilityLabel(String(format: String(localized: "Energy breakdown, %lld percent, %@."), breakdown.percent, breakdown.word))
    }

    // MARK: Header

    private var header: some View {
        let level = EnergyLevel.from(percent: breakdown.percent)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Today's energy", comment: "Energy breakdown sheet title")
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

            // Subtitle is provider-owned so it tracks the underlying signal
            // source (mock / onboarding scorer / real health data).
            Text(breakdown.subtitle)
                .font(Theme.Font.body(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(HealthKitL10n.breakdownExplanation)
                .font(Theme.Font.body(11))
                .foregroundStyle(.tertiary)
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
        color: Color,
        emptyLine: String
    ) -> some View {
        let maxAbs = items.map { abs($0.points) }.max() ?? 1

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(Theme.Font.label(11, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Spacer()
                Text(items.isEmpty ? "" : totalText)
                    .font(Theme.Font.label(14, weight: .heavy))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }

            if items.isEmpty {
                Text(emptyLine)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
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
        let net = Int(breakdown.net.rounded())
        return Text(HealthKitL10n.breakdownFooter(recovery: recovery, load: load, percent: net))
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

            Text("Write a note", comment: "Write note sheet title")
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

            TextField(String(localized: "Your note"), text: $noteText, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(Color.gray.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .padding(.horizontal, 20)
                .focused($focused)

            HStack(spacing: 10) {
                Button(String(localized: "Cancel")) { dismiss() }
                    .buttonStyle(.bordered)
                Button(String(localized: "Save")) { onSave(noteText) }
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
                Text("Focus", comment: "Focus timer title")
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

                Text("Keep this screen open.", comment: "Focus timer instruction")
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
        .accessibilityLabel(String(format: String(localized: "Focus timer, %@ remaining"), timeString(remaining)))
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
