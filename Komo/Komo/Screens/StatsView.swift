//  StatsView.swift
//  Komo
//
//  The passive-signals scroll, reached by tapping the energy reading on the main
//  screen (tap-to-insight). Each card shows one signal with a calm good/warn dot —
//  never a score, never a judgement.

import SwiftUI

struct StatsView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    private var stats: [EnergyStat] { app.data.stats() }
    private var snapshot: EnergySnapshot { app.data.currentSnapshot() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    GlassBackButton { app.go(.main) }
                    Text("Today’s Energy")
                        .font(Theme.Font.title(20))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
                    Spacer()
                }

                // Summary card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(snapshot.word).font(Theme.Font.label(28, weight: .heavy))
                        Text("· \(snapshot.percent)% charged").font(Theme.Font.body(16, weight: .semibold)).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    Text("Recharged by \(snapshot.rechargedBy)")
                        .font(Theme.Font.body(14)).foregroundStyle(.white.opacity(0.85))
                    Text("Used by \(snapshot.usedBy)")
                        .font(Theme.Font.body(14)).foregroundStyle(.white.opacity(0.85))
                }
                .padding(Theme.Space.cardPad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .komoGlassCard(cornerRadius: Theme.Radius.card, fillOpacity: 0.18, strokeOpacity: 0.3)

                Text("TODAY’S SIGNALS")
                    .font(Theme.Font.label(13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.leading, 4)

                ForEach(stats) { stat in
                    StatCard(stat: stat)
                }

                Text("Read passively from your devices · nothing leaves your phone.")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(.top, Theme.Space.screenTop)
            .padding(.bottom, 44)
        }
        .safeAreaPadding(.horizontal, 20)
    }
}

private struct StatCard: View {
    let stat: EnergyStat
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: stat.iconName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.label).font(Theme.Font.label(15)).foregroundStyle(.white)
                Text(stat.sub).font(Theme.Font.body(13)).foregroundStyle(.white.opacity(0.78))
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(stat.value).font(Theme.Font.label(20, weight: .bold)).foregroundStyle(.white)
                if !stat.unit.isEmpty {
                    Text(stat.unit).font(Theme.Font.body(13)).foregroundStyle(.white.opacity(0.7))
                }
                Circle().fill(stat.tone.dotColor).frame(width: 8, height: 8).padding(.leading, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .komoGlassCard(cornerRadius: Theme.Radius.card, fillOpacity: 0.14, strokeOpacity: 0.24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.label): \(stat.value) \(stat.unit). \(stat.sub).")
    }
}
