//  IntroView.swift
//  Komo
//
//  Page 2 — Greeting text. Lines reveal one at a time (greetStep 0→7 every 760ms),
//  and once complete the "Let's go" CTA fades up. "I already have a companion"
//  routes returning users to the welcome-back screen.

import SwiftUI

private struct GreetLine {
    let text: String
    let step: Int
    let big: Bool
    let topGap: CGFloat
}

struct IntroView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID

    private let lines: [GreetLine] = [
        .init(text: "Hi, I’m KOMO.", step: 1, big: true, topGap: 0),
        .init(text: "I help you notice your energy", step: 2, big: false, topGap: 20),
        .init(text: "through your day.", step: 3, big: false, topGap: 2),
        .init(text: "What charges it,", step: 4, big: false, topGap: 12),
        .init(text: "what drains it down.", step: 5, big: false, topGap: 2),
        .init(text: "Are you ready for this journey?", step: 6, big: false, topGap: 20),
        .init(text: "I have a few questions.", step: 7, big: false, topGap: 2),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // The companion glides in from the splash via matchedGeometry.
            BlobView(size: 120, cute: true, hue: app.dailyHue,
                     style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                     mood: app.greetStep >= 7 ? .perk : BlobAnim.none,
                     namespace: namespace, geometryID: "companion")
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(lines, id: \.step) { line in
                    Text(line.text)
                        .font(line.big ? Theme.Font.display(25) : Theme.Font.body(16))
                        .foregroundStyle(line.big ? .white : .white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.34), radius: 12, y: 1)
                        .padding(.top, line.topGap)
                        .opacity(app.greetStep >= line.step ? 1 : 0)
                        .offset(y: app.greetStep >= line.step ? 0 : 8)
                        .animation(.easeOut(duration: 0.7), value: app.greetStep)
                }
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: 8) {
                PrimaryButton(title: "Let’s go", enabled: app.greetStep >= 7) {
                    app.go(.energy)
                }
                Button("I already have a companion") {
                    app.returning = true
                    app.go(.greeting)
                }
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .padding(6)
            }
            .opacity(app.greetStep >= 7 ? 1 : 0)
            .offset(y: app.greetStep >= 7 ? 0 : 10)
            .animation(.easeOut(duration: 0.6), value: app.greetStep)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 32)
        .task {
            // startGreeting(): step 0→7, +1 every 760ms.
            app.greetStep = 0
            while app.greetStep < 7 {
                try? await Task.sleep(for: .milliseconds(760))
                if app.screen != .intro { return }
                app.greetStep += 1
            }
        }
    }
}
