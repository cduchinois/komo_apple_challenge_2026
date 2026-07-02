//  IntroView.swift
//  Komo
//
//  Page 2 — Hook. KOMO introduces itself with a gentle line-by-line reveal:
//  each line fades in from a small vertical offset, staggered by index, with a
//  soft ease-out curve. Once all lines have landed, the lowercase "let's go" CTA
//  fades up. No companion blob, no returning-user link (per prototype V1).

import SwiftUI

private struct HookLine {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let color: Color
    let topGap: CGFloat
    let tracking: CGFloat
}

struct IntroView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var namespace: Namespace.ID

    /// Single trigger — flips to true on appear, driving per-line delayed animations.
    @State private var revealed = false
    /// True once the last line has settled → CTA fades up.
    @State private var done = false

    private let lines: [HookLine] = [
        .init(text: "hi, i’m komo.", size: 27, weight: .heavy, color: .white, topGap: 0, tracking: -0.6),
        .init(text: "i help you understand your energy", size: 19, weight: .medium, color: .white.opacity(0.92), topGap: 22, tracking: -0.2),
        .init(text: "what drains you,", size: 19, weight: .medium, color: .white.opacity(0.92), topGap: 14, tracking: -0.2),
        .init(text: "what restores you,", size: 19, weight: .medium, color: .white.opacity(0.92), topGap: 4, tracking: -0.2),
        .init(text: "and take care of your energy", size: 19, weight: .medium, color: .white.opacity(0.92), topGap: 22, tracking: -0.2),
        .init(text: "before you crash.", size: 19, weight: .medium, color: .white.opacity(0.92), topGap: 4, tracking: -0.2),
    ]

    // Motion tokens for the staggered reveal.
    private let lineDuration: Double = 0.7
    private let lineStagger: Double = 0.2
    private let lineOffset: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    lineView(line)
                        .padding(.top, line.topGap)
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : lineOffset)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeOut(duration: lineDuration).delay(Double(i) * lineStagger),
                            value: revealed
                        )
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PrimaryButton(title: "let’s go", enabled: done) {
                app.go(.energy)
            }
            .opacity(done ? 1 : 0)
            .offset(y: done ? 0 : 10)
            .allowsHitTesting(done)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: done)
        }
//        .padding(.horizontal, 28)
        .padding(.top, 54)
        .padding(.bottom, 32)
        .safeAreaPadding(.horizontal, 40)
        .task { await revealHook() }
    }

    /// One hook line — no per-character mutation; the reveal is purely opacity+offset.
    @ViewBuilder
    private func lineView(_ line: HookLine) -> some View {
        Text(line.text)
            .font(.system(size: line.size, weight: line.weight, design: .rounded))
            .tracking(line.tracking)
            .foregroundStyle(line.color)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.34), radius: 12, y: 1)
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel(line.text)
    }

    /// Trigger the staggered reveal, then unlock the CTA once the last line lands.
    private func revealHook() async {
        if reduceMotion {
            revealed = true
            done = true
            return
        }
        revealed = true
        // Wait until the last line has finished animating.
        let totalMs = Int((Double(lines.count - 1) * lineStagger + lineDuration) * 1000)
        try? await Task.sleep(for: .milliseconds(totalMs))
        if app.screen != .intro { return }
        done = true
    }
}
