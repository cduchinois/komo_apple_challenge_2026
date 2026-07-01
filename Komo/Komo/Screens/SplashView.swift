//  SplashView.swift
//  Komo
//
//  Page 1 — Splash. The companion arrives with a one-shot squash-settle (komoGreet)
//  over a soft glow halo, the KOMO wordmark's two O's are live glancing eyes, and
//  the screen auto-advances to the greeting after 2.6s (no tap).

import SwiftUI

struct SplashView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 34) {
            ZStack {
                GlowHalo(color: Color(hex: 0xB0E8C4).opacity(0.55), diameter: 236)
                BlobView(size: 156, cute: true, hue: app.dailyHue,
                         style: app.blobStyle, eyes: app.eyes, legs: app.legs,
                         namespace: namespace, geometryID: "companion")
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
            }

            Wordmark()
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.7, dampingFraction: 0.55)) {
                appeared = true
            }
        }
        .task {
            // Auto-advance to the greeting (scheduleSplash -> 2600ms).
            try? await Task.sleep(for: .seconds(2.6))
            if app.screen == .splash { app.go(.intro) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("KOMO. A little light brought through the gaps of your day.")
    }
}

/// The "KOMO" wordmark whose O's are blinking, glancing eye-discs.
private struct Wordmark: View {
    var body: some View {
        HStack(spacing: 1) {
            Text("K").komoWordmarkLetter()
            WordmarkEye(blinkPeriod: 5.4, glancePeriod: 5.0, glanceForward: true)
            Text("M").komoWordmarkLetter()
            WordmarkEye(blinkPeriod: 6.1, glancePeriod: 5.6, glanceForward: false)
        }
        .shadow(color: .black.opacity(0.3), radius: 22, y: 3)
        .accessibilityHidden(true)
    }
}

private extension Text {
    func komoWordmarkLetter() -> some View {
        self.font(Theme.Font.wordmark(54)).foregroundStyle(.white)
    }
}

private struct WordmarkEye: View {
    var blinkPeriod: Double
    var glancePeriod: Double
    var glanceForward: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let diameter: CGFloat = 45  // ≈ 0.84em of 54pt

    var body: some View {
        Group {
            if reduceMotion {
                disc(pupilOffset: .zero, blink: 1)
            } else {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let gp = (t.truncatingRemainder(dividingBy: glancePeriod)) / glancePeriod
                    let dir: CGFloat = glanceForward ? 1 : -1
                    let dx = CGFloat(sin(gp * 2 * .pi)) * diameter * 0.18 * dir
                    let bp = (t.truncatingRemainder(dividingBy: blinkPeriod)) / blinkPeriod
                    disc(pupilOffset: CGSize(width: dx, height: diameter * 0.03),
                         blink: bp >= 0.94 ? 0.12 : 1)
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func disc(pupilOffset: CGSize, blink: CGFloat) -> some View {
        Circle().fill(.white)
            .overlay {
                Circle().fill(Color(hex: 0x1C2722))
                    .frame(width: diameter * 0.4, height: diameter * 0.4)
                    .overlay(alignment: .topLeading) {
                        Circle().fill(.white.opacity(0.92))
                            .frame(width: diameter * 0.4 * 0.34, height: diameter * 0.4 * 0.34)
                            .offset(x: diameter * 0.4 * 0.16, y: diameter * 0.4 * 0.12)
                    }
                    .offset(pupilOffset)
            }
            .scaleEffect(x: 1, y: blink)
            .shadow(color: .black.opacity(0.2), radius: 14, y: 3)
            .offset(y: 2)
    }
}
