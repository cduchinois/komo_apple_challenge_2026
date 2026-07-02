//  ProfileView.swift
//  Komo
//
//  Companion profile — surfaces the onboarding answers the user gave (energy
//  type, interests, authorizations) alongside the existing companion
//  customization (World, Look, Eyes, Legs, Voice). Read-only view of stored
//  onboarding state; nothing is re-asked here.

import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(PermissionsManager.self) private var permissions
    var namespace: Namespace.ID

#if DEBUG
    @State private var isInjectingDebugData = false
    @State private var debugInjectionMessage: String?
    @State private var debugScenarioIndex = 0

    private var nextScenario: DebugScenario {
        DebugScenario.allCases[debugScenarioIndex % DebugScenario.allCases.count]
    }
#endif

    /// Existing companion-customization rows (World, Companion, Look, …).
    private var companionRows: [(String, String)] {
        [
            ("World", app.world.name),
            ("Companion", "\(app.companionDisplayName) · \(app.character.trait)"),
            ("Look", app.blobStyle.name),
            ("Eyes", app.eyes.name),
            ("Legs", app.legs.name),
            ("Voice", app.tone.name),
        ]
    }

    /// Onboarding answers stored in AppState (from the Q1..Q4 flow).
    private var onboardingRows: [(String, String)] {
        [
            ("Peak time", (app.energyType?.capitalized ?? "—")),
            ("Right now", (app.energyNow?.capitalized ?? "—")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    Text(app.displayName)
                        .font(Theme.Font.title(20)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // TODO(mascot-rollout): character.motion / hue / style / eyes /
                // legs have no equivalent in KomoMascotView; manual's default
                // idle is used. Customize screen still stores these preferences.
                KomoMascotView(size: KomoMascotView.standardSize,
                               namespace: namespace,
                               geometryID: "companion",
                               accessibilityLabelText: app.companionDisplayName)
                    .padding(.vertical, 4)

                Text(app.companionDisplayName)
                    .font(Theme.Font.display(26)).foregroundStyle(.white)
                Text(app.character.desc)
                    .font(Theme.Font.body(14)).foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center).frame(maxWidth: 280)

                // 1) Onboarding energy answers
                sectionHeader("Energy")
                rowsCard(onboardingRows)

                // 2) Interests — restores + drains chip clouds
                sectionHeader("Interests")
                chipsCard(title: "Recharges you",
                          labels: app.restores,
                          emptyText: "Not set yet.")
                chipsCard(title: "Drains you",
                          labels: app.drains,
                          emptyText: "Not set yet.")

                // 3) Permissions (live from PermissionsManager)
                sectionHeader("Permissions")
                permissionsCard

                // 4) Companion customization (existing)
                sectionHeader("Companion")
                rowsCard(companionRows)

                Button { app.go(.customize) } label: {
                    Text("Customize \(app.companionDisplayName)")
                        .font(Theme.Font.label(16)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
                        .glassEffect(.clear.interactive())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

#if DEBUG
                sectionHeader("Debug")
                Button { injectDebugData() } label: {
                    HStack(spacing: 10) {
                        if isInjectingDebugData {
                            ProgressView()
                                .tint(Theme.Palette.ink)
                        }
                        Text(isInjectingDebugData ? "Injection en cours..." : nextScenario.buttonLabel)
                            .font(Theme.Font.label(15))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(isInjectingDebugData)
#endif
            }
            .padding(.horizontal, Theme.Space.screenH)
            .padding(.top, Theme.Space.screenTop)
            .padding(.bottom, 44)
        }
#if DEBUG
        .alert("Debug data", isPresented: debugInjectionAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(debugInjectionMessage ?? "")
        }
#endif
    }

#if DEBUG
    private var debugInjectionAlertBinding: Binding<Bool> {
        Binding(
            get: { debugInjectionMessage != nil },
            set: { isPresented in
                if !isPresented {
                    debugInjectionMessage = nil
                }
            }
        )
    }

    private func injectDebugData() {
        isInjectingDebugData = true
        let scenario = nextScenario
        Task { @MainActor in
            do {
                let result = try await DebugTestDataInjector.shared.resetAndInject(scenario: scenario)
                // refreshFromHealthKit() reloads data AND switches app.data to HealthKitDataProvider
                // so the energy bar re-renders immediately.
                await app.refreshFromHealthKit()
                debugScenarioIndex += 1
                debugInjectionMessage = "[\(scenario.scenarioLabel)] \(result.message)"
            } catch {
                debugInjectionMessage = "Injection impossible: \(error.localizedDescription)"
            }
            isInjectingDebugData = false
        }
    }
#endif

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.Font.label(11, weight: .heavy))
                .foregroundStyle(.white.opacity(0.8))
                .tracking(1.2)
                .padding(.leading, 4)
            Spacer()
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func rowsCard(_ rows: [(String, String)]) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        )
    }

    @ViewBuilder
    private func chipsCard(title: String, labels: [String], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Font.label(13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            if labels.isEmpty {
                Text(emptyText)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                FlowLayout(spacing: 6, alignment: .leading) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .font(Theme.Font.label(12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.white.opacity(0.18),
                                        in: Capsule(style: .continuous))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        )
    }

    // MARK: - Permissions (live from PermissionsManager)

    /// A row in the permissions section, tied to a live `PermissionState`.
    private struct PermissionRowSpec {
        let name: String
        let state: PermissionState
        let onTap: () -> Void
    }

    private var permissionsCard: some View {
        let rows: [PermissionRowSpec] = [
            .init(name: String(localized: "Health data"),   state: permissions.health,
                  onTap: { Task { await permissions.requestHealth() } }),
            .init(name: String(localized: "Calendar"),      state: permissions.calendar,
                  onTap: { Task { await permissions.requestCalendar() } }),
            .init(name: String(localized: "Notifications"), state: permissions.notifications,
                  onTap: { Task { await permissions.requestNotifications() } }),
            // Screen Time has no runtime API — tap deep-links to Settings.
            .init(name: String(localized: "Screen time"),   state: permissions.screenTime,
                  onTap: { permissions.openSettings() }),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                permissionRow(row)
                if idx < rows.count - 1 {
                    Divider().overlay(Color.white.opacity(0.12)).padding(.leading, 18)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        )
        .task {
            // Re-read system-authoritative state whenever Profile appears —
            // status can change outside the app (Settings toggle).
            await permissions.refreshAll()
        }
    }

    @ViewBuilder
    private func permissionRow(_ row: PermissionRowSpec) -> some View {
        Button(action: row.onTap) {
            HStack {
                Text(row.name).font(Theme.Font.body(15)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.state == .granted ? Theme.Palette.leaf : Color.white.opacity(0.35))
                        .frame(width: 8, height: 8)
                    Text(row.state.label)
                        .font(Theme.Font.label(13, weight: .semibold))
                        .foregroundStyle(.white)
                    if row.state != .granted {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.name), \(row.state.label)")
        .accessibilityHint(row.state == .granted ? "" : "Requests this permission or opens Settings.")
    }
}
