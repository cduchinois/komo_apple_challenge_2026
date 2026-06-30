//  BlobView.swift
//  Komo
//
//  The reusable living companion. One TimelineView clock drives every layer —
//  outer choreography, breathing, silhouette morph, blink, twinkle, leg wiggle —
//  each on its own desynced period so the idle never beats mechanically
//  (transform-origin pivots from bottom-center: anchor 50% 90%).
//
//  When Reduce Motion is on, the whole creature freezes into a calm resting pose
//  and the TimelineView is bypassed entirely.

import SwiftUI

struct BlobView: View {
    // Identity / look
    var size: CGFloat = 200
    var cute: Bool = true
    var tired: Bool = false
    var hue: Double = 150
    var style: BlobStyle = .glossy
    var eyes: EyeStyle = .cartoon
    var legs: LegStyle = .stubs
    var showFace: Bool = true
    var showLegs: Bool = true

    // Motion
    var motion: CompanionMotion = .calm
    /// Per-screen mood override. `nil` -> use the motion preset's outer drift.
    var mood: BlobAnim? = nil
    var seed: Double = 0

    // Interaction & transitions
    var onTap: (() -> Void)? = nil
    var namespace: Namespace.ID? = nil
    var geometryID: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var preset: MotionPreset { .forMotion(motion) }
    private var outerAnim: BlobAnim { mood ?? preset.outerKind }
    private var outerDuration: Double {
        if let mood, mood != .none { return mood.moodDuration }
        return preset.outer
    }

    var body: some View {
        Group {
            if reduceMotion {
                rendered(values: restValues)
            } else {
                TimelineView(.animation) { timeline in
                    rendered(values: liveValues(at: timeline.date))
                }
            }
        }
        .frame(width: size, height: size)
        .modifier(MatchedGeometry(namespace: namespace, id: geometryID))
        .contentShape(Circle())
        .onTapGesture { onTap?() }
    }

    // MARK: - Per-frame computed values

    private struct Values {
        var outer: BlobTransform
        var breathe: CGFloat
        var morph: Double
        var blink: CGFloat
        var twinkle: CGFloat
        var wiggle: Double
    }

    private var restValues: Values {
        Values(outer: outerAnim.transform(at: 0.18), breathe: 1, morph: 0.0, blink: 1, twinkle: 1, wiggle: 0)
    }

    private func liveValues(at date: Date) -> Values {
        let t = date.timeIntervalSinceReferenceDate
        func phase(_ dur: Double) -> Double { (t.truncatingRemainder(dividingBy: dur)) / dur }

        let outer = outerAnim.transform(at: phase(outerDuration))
        let breatheScale = 1 + 0.045 * sin(phase(preset.breathe) * 2 * .pi)
        // 0...1 loop phase through the komoMochi border-radius keyframes.
        let morph = phase(preset.morph)
        let blink = blinkScale(phase(6.0))
        let twinkle = 1 + 0.13 * sin(phase(2.4) * 2 * .pi)
        let wiggle = 8 * sin(phase(0.9) * 2 * .pi)
        return Values(outer: outer, breathe: CGFloat(breatheScale), morph: morph,
                      blink: blink, twinkle: CGFloat(twinkle), wiggle: wiggle)
    }

    /// Eyes stay open, then snap shut briefly near 94% of the loop (komoBlink).
    private func blinkScale(_ p: Double) -> CGFloat {
        guard p >= 0.92 else { return 1 }
        let local = (p - 0.92) / 0.08            // 0...1 across the blink window
        let v = local < 0.5 ? (1 - local / 0.5) : (local - 0.5) / 0.5
        return CGFloat(0.12 + (1 - 0.12) * (1 - v))
    }

    // MARK: - Render

    @ViewBuilder
    private func rendered(values v: Values) -> some View {
        let scale = size / 200

        ZStack {
            if showLegs {
                BlobLegs(size: size, color: legColor, style: legs, wiggle: v.wiggle)
            }
            BlobBody(size: size, hue: hue, cute: cute, tired: tired, style: style, morph: v.morph)
            if showFace {
                BlobFace(size: size, eyes: eyes, cute: cute, tired: tired, blink: v.blink, twinkle: v.twinkle)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(v.breathe)
        // Outer choreography, pivoting from the weighted base (50% 90%).
        .scaleEffect(x: v.outer.scaleX, y: v.outer.scaleY, anchor: UnitPoint(x: 0.5, y: 0.9))
        .rotationEffect(.degrees(v.outer.rotation), anchor: UnitPoint(x: 0.5, y: 0.9))
        .offset(x: v.outer.dx * scale, y: v.outer.dy * scale)
    }

    // The darkest ramp color, reused for legs.
    private var legColor: Color {
        if cute {
            return tired ? Color(oklch: 0.56, 0.18, hue + 30) : Color(oklch: 0.74, 0.09, hue + 32)
        }
        return Color(oklch: 0.56, 0.16, hue + 40)
    }
}

/// Applies a matchedGeometryEffect only when a namespace + id are supplied.
private struct MatchedGeometry: ViewModifier {
    var namespace: Namespace.ID?
    var id: String?
    func body(content: Content) -> some View {
        if let namespace, let id {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
