//  HealthPermissionView.swift
//  Komo
//
//  Contextual permission screen shown right after Q sleep. KOMO explains why
//  it wants health data, then a primary CTA fires the native HealthKit prompt
//  via `PermissionsManager.requestHealth()`. The user's grant/deny choice is
//  made inside the native sheet — no in-app bypass (App Store 5.1.1(iv)).
//  Either outcome advances to Restores (Q3).

import SwiftUI

struct HealthPermissionView: View {
    @Environment(AppState.self) private var app
    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID

    @State private var revealed = false
    @State private var isRequesting = false

    private let lines: [String] = [
        String(localized: "sleep is one of your biggest energy signals."),
        String(localized: "komo can use health data to understand your sleep, movement, stress, and recovery."),
        String(localized: "everything stays on your device.")
    ]

    private let lineDuration: Double = 0.7
    private let lineStagger: Double = 0.2

    var body: some View {
        VStack(spacing: 0) {
            // Shares dot #2 with SleepView (permission screens don't get their
            // own dot — they follow their preceding question).
            OnboardingHeader(step: 2) { app.go(.sleep) }
                .padding(.bottom, 14)

            KomoMascotView(size: KomoMascotView.standardSize,
                           namespace: namespace,
                           geometryID: "companion",
                           accessibilityLabelText: app.companionDisplayName)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .font(Theme.Font.body(17, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.34), radius: 12, y: 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 10)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeOut(duration: lineDuration).delay(Double(i) * lineStagger),
                            value: revealed
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)

            Spacer(minLength: 20)

            PrimaryButton(title: isRequesting ? "requesting…" : "connect health data",
                          enabled: !isRequesting) {
                requestAndAdvance()
            }
        }
        .safeAreaPadding(.horizontal, 40)
        .padding(.top, Theme.Space.screenTop)
        .padding(.bottom, 24)
        .task {
            revealed = true
        }
    }

    private func requestAndAdvance() {
        isRequesting = true
        Task { @MainActor in
            await permissions.requestHealth()
            isRequesting = false
            app.go(.restores)
        }
    }
}
