//  SleepView.swift
//  Komo
//
//  Page 4 — Sleep + Health. The blob is state-driven: it droops (komoDrowsy)
//  until a quality is chosen, then springs awake (komoPerk). Choosing a quality
//  reveals the Health-data / manual-entry card.

import SwiftUI

struct SleepView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    private let qualities = ["Well", "Okay", "Not great"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 2) {
                app.sleepAsked = false
                app.sleepManual = false
                app.go(.energy)
            }
            .padding(.bottom, 14)

            QuestionTitle(text: "How did you sleep last night?")

            BlobView(size: 128, cute: true, hue: app.dailyHue,
                     style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                     mood: app.sleepAsked ? .perk : .drowsy,
                     namespace: namespace, geometryID: "companion")
                .frame(maxHeight: .infinity)

            if !app.sleepAsked {
                VStack(spacing: Theme.Space.optionGap) {
                    ForEach(qualities, id: \.self) { q in
                        OptionRow(label: q) {
                            withAnimation(.spring(response: 0.4)) { app.pickSleep(q) }
                        }
                    }
                }
            } else {
                healthCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.Space.screenH)
        .padding(.top, 64)
        .padding(.bottom, 32)
        .animation(.spring(response: 0.4), value: app.sleepAsked)
        .animation(.spring(response: 0.35), value: app.sleepManual)
    }

    @ViewBuilder
    private var healthCard: some View {
        if app.sleepManual {
            VStack(spacing: 11) {
                Text("How long have you slept last night?")
                    .font(Theme.Font.label(16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 1)

                TextField("", text: Binding(get: { app.sleepDuration }, set: { app.sleepDuration = $0 }),
                          prompt: Text("Enter hours"))
                    .keyboardType(.decimalPad)
                    .font(Theme.Font.body(15, weight: .medium))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))

                PrimaryButton(title: "Continue", filledGreen: true) { app.go(.drains) }
                    .frame(height: 50)
            }
        } else {
            VStack(spacing: 8) {
                PrimaryButton(title: "Let KOMO read my Health Data", filledGreen: true) {
                    // We do NOT touch HealthKit yet — just advance the mocked flow.
                    app.go(.drains)
                }
                .frame(height: 52)

                Button {
                    app.sleepManual = true
                } label: {
                    Text("Enter Manually")
                        .font(Theme.Font.label(14.5))
                        .foregroundStyle(Theme.Palette.inkMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field).strokeBorder(Color(hex: 0x3C5A46).opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
