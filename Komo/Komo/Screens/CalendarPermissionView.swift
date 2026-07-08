//  CalendarPermissionView.swift
//  Komo
//
//  Conditional permission screen shown right after Q4 (drains) if the user
//  selected a calendar-heavy drain (meetings / intense work / social plans).
//  KOMO's opening line reflects the first matching drain. Primary CTA fires
//  the native EventKit prompt — user's grant/deny choice is made inside the
//  system sheet, no in-app bypass (App Store 5.1.1(iv)).
//
//  Requires INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription in the project
//  build settings — added in project.pbxproj.

import SwiftUI

struct CalendarPermissionView: View {
    @Environment(AppState.self) private var app
    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID

    @State private var revealed = false
    @State private var isRequesting = false

    /// Opening line adapts to which drain triggered this screen. First
    /// matching drain wins.
    private var openingLine: String {
        for drain in app.drains {
            if ["meetings", "intense work", "social plans"].contains(drain) {
                return L10n.calendarPermissionOpening(for: drain)
            }
        }
        return L10n.calendarPermissionOpening(for: "")
    }

    private var lines: [String] {
        [
            openingLine,
            String(localized: "if i can peek at your calendar, i'll see the heavy days coming.")
        ]
    }

    private let lineDuration: Double = 0.7
    private let lineStagger: Double = 0.2

    var body: some View {
        VStack(spacing: 0) {
            // Shares dot #4 with DrainsView.
            OnboardingHeader(step: 4) { app.go(.drains) }
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

            PrimaryButton(title: isRequesting ? "requesting…" : "let komo see my calendar",
                          enabled: !isRequesting) {
                requestAndAdvance()
            }
        }
        .padding(.top, Theme.Space.screenTop)
        .padding(.bottom, 24)
        .safeAreaPadding(.horizontal, 40)
        .task {
            revealed = true
        }
    }

    private func requestAndAdvance() {
        isRequesting = true
        Task { @MainActor in
            await permissions.requestCalendar()
            isRequesting = false
            app.go(.loading)
        }
    }
}
