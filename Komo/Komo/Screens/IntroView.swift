//  IntroView.swift
//  Komo
//
//  Page 2 — Hook. KOMO introduces itself with a typewriter effect: each line
//  types in character-by-character with a blinking caret, then advances. Once all
//  lines finish, the lowercase "let's go" CTA fades up. No companion blob, no
//  returning-user link (per prototype V1).

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

    // hookLine index currently typing, char count into it, and completion flag.
    @State private var lineIndex = 0
    @State private var charCount = 0
    @State private var done = false

    private let lines: [HookLine] = [
        .init(text: "hi, i’m komo.", size: 27, weight: .heavy, color: .white, topGap: 0, tracking: -0.6),
        .init(text: "i help you understand your energy", size: 19, weight: .medium, color: .white.opacity(0.92), topGap: 22, tracking: -0.2),
        .init(text: "what drains you,", size: 19, weight: .medium, color: .white.opacity(0.92), topGap: 14, tracking: -0.2),
        .init(text: "what restores you,", size: 19, weight: .medium, color: .white.opacity(0.92), topGap: 4, tracking: -0.2),
        .init(text: "and take care of your energy", size: 19, weight: .medium, color: .white.opacity(0.92), topGap: 22, tracking: -0.2),
        .init(text: "before you crash.", size: 19, weight: .medium, color: .white.opacity(0.92), topGap: 4, tracking: -0.2),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    lineView(i, line)
                        .padding(.top, line.topGap)
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
            .animation(.easeOut(duration: 0.6), value: done)
        }
        .padding(.horizontal, 28)
        .padding(.top, 54)
        .padding(.bottom, 32)
        .task { await runTypewriter() }
    }

    /// One hook line: the visible substring (up to charCount on the active line)
    /// plus a blinking caret while it is the line being typed.
    @ViewBuilder
    private func lineView(_ i: Int, _ line: HookLine) -> some View {
        let shown: String = {
            if done || i < lineIndex { return line.text }
            if i == lineIndex { return String(line.text.prefix(charCount)) }
            return ""
        }()
        let caretHere = !done && i == lineIndex

        HStack(spacing: 3) {
            Text(shown)
                .font(.system(size: line.size, weight: line.weight, design: .rounded))
                .tracking(line.tracking)
                .foregroundStyle(line.color)
            if caretHere {
                Caret(height: line.size * 1.05)
            }
        }
        .lineLimit(1)
        .shadow(color: .black.opacity(0.34), radius: 12, y: 1)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(line.text)
    }

    /// startHook() / _typeStep(): ~30–60ms per char, 460ms between lines.
    private func runTypewriter() async {
        if reduceMotion {
            lineIndex = lines.count
            done = true
            return
        }
        lineIndex = 0; charCount = 0; done = false
        for (i, line) in lines.enumerated() {
            lineIndex = i
            charCount = 0
            for _ in line.text {
                try? await Task.sleep(for: .milliseconds(Int(30 + Double.random(in: 0..<30))))
                if app.screen != .intro { return }
                charCount += 1
            }
            if i < lines.count - 1 {
                try? await Task.sleep(for: .milliseconds(460))
                if app.screen != .intro { return }
            }
        }
        withAnimation(.easeOut(duration: 0.6)) { done = true }
    }
}

/// A blinking text caret (komoCaret 0.85s, hard on/off).
private struct Caret: View {
    var height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                bar.opacity(1)
            } else {
                TimelineView(.periodic(from: .now, by: 0.425)) { ctx in
                    let phase = Int(ctx.date.timeIntervalSinceReferenceDate / 0.425) % 2
                    bar.opacity(phase == 0 ? 1 : 0)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.white)
            .frame(width: 3, height: height)
            .offset(y: height * 0.08)
    }
}
