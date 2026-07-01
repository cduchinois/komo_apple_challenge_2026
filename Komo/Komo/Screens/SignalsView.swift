//  SignalsView.swift
//  Komo
//
//  Page 7 — Signals / Permissions (new in V1). KOMO asks to read on-device
//  signals. All toggles are OFF by default. The primary button reads "activate
//  all" until at least one is on, then "continue". A "choose later" glass button
//  and a trust line finish the screen. We do NOT touch HealthKit yet.

import SwiftUI

struct SignalsView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingHeader(step: 4) { app.go(.drains) }
                .padding(.bottom, 14)

            Text("komo learns from\nsignals already on\nyour devices")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(-0.4)
                .lineSpacing(2)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 14, y: 2)

            Text("everything stays on your device.")
                .font(Theme.Font.body(14.5))
                .foregroundStyle(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
                .padding(.top, 8)

            VStack(spacing: 10) {
                SignalCard(icon: "heart.fill", label: "activate health data",
                           desc: "heart rate, sleep & activity",
                           isOn: app.auth.health) { app.toggleAuth(\.health) }
                SignalCard(icon: "calendar", label: "activate calendar",
                           desc: "your daily load",
                           isOn: app.auth.calendar) { app.toggleAuth(\.calendar) }
                SignalCard(icon: "iphone", label: "activate screen time",
                           desc: "your digital balance",
                           isOn: app.auth.screen) { app.toggleAuth(\.screen) }
                SignalCard(icon: "bell.fill", label: "activate notification",
                           desc: "gentle nudges from komo",
                           isOn: app.auth.notify) { app.toggleAuth(\.notify) }
            }
            .padding(.top, 20)

            Spacer(minLength: 14)

            Button {
                app.signalsPrimary { app.go(.loading) }
            } label: {
                Text(app.auth.anyOn ? "continue" : "activate all")
                    .font(Theme.Font.label(17))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
            }
            .buttonStyle(.plain)

            Button { app.go(.loading) } label: {
                Text("choose later")
                    .font(Theme.Font.label(15.5))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .komoGlassButton(cornerRadius: 16, strokeOpacity: 0.28)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                Text("your data is processed on-device.")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, 60)
        .padding(.bottom, 28)
        .animation(.easeInOut(duration: 0.2), value: app.auth)
    }
}

private struct SignalCard: View {
    var icon: String
    var label: String
    var desc: String
    var isOn: Bool
    var toggle: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isOn ? Color(hex: 0x1C6B3F) : .white)
                .frame(width: 40, height: 40)
                .background(isOn ? Color.white.opacity(0.92) : Color.white.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Theme.Font.label(15.5))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(Theme.Font.body(12.5))
                    .foregroundStyle(.white.opacity(0.64))
            }
            Spacer(minLength: 8)

            SignalToggle(isOn: isOn, action: toggle)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .komoGlassCard(cornerRadius: 18,
                       fillOpacity: isOn ? 0.2 : 0.1,
                       strokeOpacity: isOn ? 0.55 : 0.2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }
}

/// The 50×30 pill toggle that lights up on the accent color when on.
private struct SignalToggle: View {
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.Palette.accent : Color.white.opacity(0.22))
                    .frame(width: 50, height: 30)
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 2)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isOn)
        .accessibilityHidden(true)
    }
}
