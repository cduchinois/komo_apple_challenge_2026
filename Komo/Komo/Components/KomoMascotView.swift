//  KomoMascotView.swift
//  Komo
//
//  The new jelly-blob mascot, ported from `komo_mascot.html` to native SwiftUI
//  (Path + gradients + soft strokes). This is a NEW reusable component that
//  coexists with the existing BlobView during the staged rollout.
//
//  Stage 1 swaps this mascot in on the splash screen only. Other screens keep
//  BlobView until validated.
//
//  Note on WebView: `description_usage_manual.md` documents embedding the
//  mascot via `WKWebView`. Per project instruction, we render it natively so
//  the mascot participates in SwiftUI transitions, matched geometry, and
//  Reduce-Motion. Where the manual and the SwiftUI implementation conflict
//  (e.g. pointer / eye tracking, glint dart, atmosphere particles), the
//  visual essence is preserved but the interaction layer is trimmed.

import SwiftUI

// MARK: - Public API

struct KomoMascotView: View {
    /// One shared size across every screen. Validated on the splash page and
    /// applied uniformly during the Stage-2 rollout — every screen shows the
    /// mascot at the same visual footprint.
    static let standardSize: CGFloat = 220

    /// Total square footprint. The mascot scales to fit within a 400×400 design
    /// viewBox, then everything is proportioned from `size`.
    var size: CGFloat = 200
    /// Optional tap handler — mirrors BlobView's `onTap` closure.
    var onTap: (() -> Void)? = nil
    /// Matched-geometry namespace so callers can reuse the same slot across
    /// screens (mirrors BlobView's `namespace`/`geometryID` shape).
    var namespace: Namespace.ID? = nil
    var geometryID: String? = nil
    /// VoiceOver label. Defaults to "Komo" if nil.
    var accessibilityLabelText: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // Reduce Motion: static resting pose. No idle float, breathe,
                // or blink — the mascot sits still, exactly per the manual's
                // reduced-motion guidance.
                KomoMascotBody(
                    size: size,
                    breatheScaleX: 1, breatheScaleY: 1,
                    floatY: 0, floatRotationDeg: 0,
                    blinkY: 1
                )
            } else {
                TimelineView(.animation) { timeline in
                    let v = animatedValues(at: timeline.date.timeIntervalSinceReferenceDate)
                    KomoMascotBody(
                        size: size,
                        breatheScaleX: v.bx, breatheScaleY: v.by,
                        floatY: v.floatY, floatRotationDeg: v.rot,
                        blinkY: v.blinkY
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture { onTap?() }
        .modifier(KomoMatchedGeometry(namespace: namespace, id: geometryID))
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabelText ?? "Komo")
    }

    /// Per-frame animation values. Approximates the manual's:
    ///   • komoFloat   — 6.5s ease-in-out, translateY 0↔-7 + rotate ±0.7°
    ///   • komoBreathe — 3.6s ease-in-out, scale 1↔1.04×0.96 (bottom-anchored)
    ///   • blinkLoop   — random 1.8..6s, quick close then open (+ occasional double)
    private func animatedValues(at t: TimeInterval) -> (bx: CGFloat, by: CGFloat, floatY: CGFloat, rot: Double, blinkY: CGFloat) {
        // Breathe — sin-based ease-in-out on scale.
        let bp = (t.truncatingRemainder(dividingBy: 3.6)) / 3.6
        let breatheDelta = 0.04 * sin(bp * 2 * .pi)
        let bx = 1 + breatheDelta
        let by = 1 - breatheDelta

        // Float — sinusoidal y + slight rotation coupling.
        let fp = (t.truncatingRemainder(dividingBy: 6.5)) / 6.5
        let floatY = -7.0 * sin(fp * 2 * .pi)
        let rot = 0.7 * cos(fp * 2 * .pi)

        // Blink — deterministic pseudo-random from `t`, ~one primary blink
        // per 4s cycle, with a 28% chance of a second blink 300ms later
        // (approximated by widening the close window when it triggers).
        let cycleLen: TimeInterval = 4.0
        let cycleIndex = floor(t / cycleLen)
        let inCycle = t - cycleIndex * cycleLen
        // Pseudo-random seed derived from the cycle index.
        let seed = abs(sin(cycleIndex * 12.345 + 0.7))
        let blinkStart = 0.6 + seed * 2.8
        let blinkDur = 0.22
        var blinkY: CGFloat = 1
        if inCycle >= blinkStart && inCycle < blinkStart + blinkDur {
            let local = (inCycle - blinkStart) / blinkDur
            // Triangle 0..1..0 → close then open.
            let closeness = 1 - abs(local - 0.5) * 2
            blinkY = 1 - CGFloat(closeness) * 0.92
        }
        // Double-blink: 300ms after the first, 28% chance.
        let doubleTrigger = abs(sin(cycleIndex * 4.31)) > 0.72
        if doubleTrigger {
            let secondStart = blinkStart + 0.3
            if inCycle >= secondStart && inCycle < secondStart + blinkDur {
                let local = (inCycle - secondStart) / blinkDur
                let closeness = 1 - abs(local - 0.5) * 2
                blinkY = 1 - CGFloat(closeness) * 0.92
            }
        }

        return (CGFloat(bx), CGFloat(by), CGFloat(floatY), rot, blinkY)
    }
}

// MARK: - Composed body (body + face + shadow)

private struct KomoMascotBody: View {
    var size: CGFloat
    var breatheScaleX: CGFloat
    var breatheScaleY: CGFloat
    var floatY: CGFloat
    var floatRotationDeg: Double
    var blinkY: CGFloat

    var body: some View {
        ZStack {
            // Ground contact shadow (bottom -3% of the frame in the source).
            Ellipse()
                .fill(RadialGradient(
                    colors: [Color(hex: 0x374B2D).opacity(0.42), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.35
                ))
                .frame(width: size * 0.66, height: size * 0.10)
                .offset(y: size * 0.44)
                .blur(radius: max(3, size * 0.02))

            // Blob stage — nested transforms mirror the source:
            // float (translate + rotate) → breathe (scale, bottom anchor).
            ZStack {
                blobBody
                faceLayer
            }
            .scaleEffect(x: breatheScaleX, y: breatheScaleY, anchor: .bottom)
            .rotationEffect(.degrees(floatRotationDeg), anchor: .bottom)
            .offset(y: floatY)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Blob body (base + inner light + rim highlights)

    @ViewBuilder
    private var blobBody: some View {
        ZStack {
            // Base body: teal → mint linear gradient (top to bottom).
            KomoBlobShape().fill(bodyGradient)

            // Inner decorations, clipped to the blob outline.
            ZStack {
                // Teal grounding wash at the base.
                Ellipse()
                    .fill(Color(hex: 0x33C2BE).opacity(0.4))
                    .frame(width: size * 0.61, height: size * 0.23)
                    .offset(y: size * 0.33)
                    .blur(radius: max(4, size * 0.033))

                // Warm inner core glow (approximates SVG mix-blend-mode: screen).
                KomoBlobShape()
                    .fill(coreGlow)
                    .blendMode(.screen)

                // Upper-left specular highlight — rotated ellipse, blurred.
                Ellipse()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.85), .white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.14
                    ))
                    .frame(width: size * 0.23, height: size * 0.48)
                    .rotationEffect(.degrees(-27))
                    .offset(x: -size * 0.15, y: -size * 0.12)
                    .blur(radius: max(2, size * 0.015))

                // Small bright top-highlight dot.
                Ellipse()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: size * 0.13, height: size * 0.075)
                    .offset(x: -size * 0.07, y: -size * 0.22)
                    .blur(radius: max(2, size * 0.015))
            }
            .clipShape(KomoBlobShape())

            // Rim highlights — a soft mint outer glow + a thin white liner.
            KomoBlobShape()
                .stroke(Color(hex: 0xC5F1EB).opacity(0.5), lineWidth: max(1, size * 0.006))
                .blur(radius: max(1, size * 0.015))
            KomoBlobShape()
                .stroke(Color.white.opacity(0.35), lineWidth: max(0.6, size * 0.0035))
        }
        .frame(width: size, height: size)
    }

    private var bodyGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0xE6F3C6), location: 0.00),
                .init(color: Color(hex: 0xC4EDC6), location: 0.38),
                .init(color: Color(hex: 0x82E2D4), location: 0.70),
                .init(color: Color(hex: 0x54D3CF), location: 1.00),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var coreGlow: RadialGradient {
        RadialGradient(
            stops: [
                .init(color: Color(hex: 0xF7F9CA).opacity(0.90), location: 0.00),
                .init(color: Color(hex: 0xDAF2B6).opacity(0.28), location: 0.55),
                .init(color: Color(hex: 0xDAF2B6).opacity(0.00), location: 1.00),
            ],
            center: UnitPoint(x: 0.5, y: 0.6),
            startRadius: 0,
            endRadius: size * 0.58
        )
    }

    // MARK: - Face (blush, eyes + glints, smile)

    @ViewBuilder
    private var faceLayer: some View {
        ZStack(alignment: .topLeading) {
            // Blush cheeks (peach radial). SVG cx = 128 / 272, cy = 226.
            blushEllipse.svgPosition(size: size, x: 128, y: 226)
            blushEllipse.svgPosition(size: size, x: 272, y: 226)

            // Left eye group  — eye (148,185), glint (156,176), reflection (141,195).
            eyeGroup(cx: 148, cy: 185, glintDx: 8, glintDy: -9, refDx: -7, refDy: 10)
            // Right eye group — eye (252,185), glint (260,176), reflection (245,195).
            eyeGroup(cx: 252, cy: 185, glintDx: 8, glintDy: -9, refDx: -7, refDy: 10)

            // Smile — quadratic curve M186,190 Q200,203 214,190.
            smilePath
        }
        .frame(width: size, height: size)
    }

    private var blushEllipse: some View {
        Ellipse()
            .fill(RadialGradient(
                colors: [Color(hex: 0xFFB6A3).opacity(0.85), Color(hex: 0xFFB6A3).opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.06
            ))
            .frame(width: size * 0.12, height: size * 0.06)
            .blur(radius: max(2, size * 0.008))
    }

    /// Full eye (dark-green base + white glint + tiny reflection dot). The
    /// whole group scales-Y with `blinkY` so glint and reflection close with
    /// the eye — mirrors the SVG's `.komo-eye` transform group.
    private func eyeGroup(cx: CGFloat, cy: CGFloat, glintDx: CGFloat, glintDy: CGFloat, refDx: CGFloat, refDy: CGFloat) -> some View {
        let eyeW = size * 0.10        // rx 20 → w 40 → /400 = 0.10
        let eyeH = size * 0.115       // ry 23 → h 46 → /400 = 0.115
        let glintR = size * 0.01875   // r 7.5 → 15/400 / 2 → 0.01875
        let refR = size * 0.009       // r 3.6 → 7.2/400 / 2 → 0.009
        let f = size / 400
        return ZStack {
            // Base eye — dark green radial gradient
            Ellipse()
                .fill(RadialGradient(
                    colors: [Color(hex: 0x1D5348), Color(hex: 0x0D3A31), Color(hex: 0x04201B)],
                    center: UnitPoint(x: 0.38, y: 0.30),
                    startRadius: 0,
                    endRadius: eyeH * 0.75
                ))
                .frame(width: eyeW, height: eyeH)

            // Big white catchlight (glint)
            Circle()
                .fill(Color.white.opacity(0.97))
                .frame(width: glintR * 2, height: glintR * 2)
                .offset(x: glintDx * f, y: glintDy * f)

            // Small pale-mint reflection dot
            Circle()
                .fill(Color(hex: 0xCFE6DF).opacity(0.4))
                .frame(width: refR * 2, height: refR * 2)
                .offset(x: refDx * f, y: refDy * f)
        }
        .scaleEffect(y: blinkY, anchor: .center)
        .svgPosition(size: size, x: cx, y: cy)
    }

    private var smilePath: some View {
        Path { p in
            let f = size / 400
            p.move(to: CGPoint(x: 186 * f, y: 190 * f))
            p.addQuadCurve(
                to: CGPoint(x: 214 * f, y: 190 * f),
                control: CGPoint(x: 200 * f, y: 203 * f)
            )
        }
        .stroke(Color(hex: 0x12463C),
                style: StrokeStyle(lineWidth: max(1, size * 0.0113), lineCap: .round))
    }
}

// MARK: - Blob outline (SVG viewBox 0..400)

private struct KomoBlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 400
        let sy = rect.height / 400
        var p = Path()
        p.move(to: CGPoint(x: 70 * sx, y: 250 * sy))
        p.addCurve(to: CGPoint(x: 200 * sx, y: 70 * sy),
                   control1: CGPoint(x: 70 * sx, y: 138 * sy),
                   control2: CGPoint(x: 122 * sx, y: 70 * sy))
        p.addCurve(to: CGPoint(x: 330 * sx, y: 250 * sy),
                   control1: CGPoint(x: 278 * sx, y: 70 * sy),
                   control2: CGPoint(x: 330 * sx, y: 138 * sy))
        p.addCurve(to: CGPoint(x: 200 * sx, y: 352 * sy),
                   control1: CGPoint(x: 330 * sx, y: 322 * sy),
                   control2: CGPoint(x: 284 * sx, y: 352 * sy))
        p.addCurve(to: CGPoint(x: 70 * sx, y: 250 * sy),
                   control1: CGPoint(x: 116 * sx, y: 352 * sy),
                   control2: CGPoint(x: 70 * sx, y: 322 * sy))
        p.closeSubpath()
        return p
    }
}

// MARK: - Positioning helper (SVG-style center coords)

private extension View {
    /// Position the receiver's center at SVG (x, y) inside a size×size canvas.
    func svgPosition(size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        self.position(x: x / 400 * size, y: y / 400 * size)
    }
}

// MARK: - Matched geometry (mirrors BlobView's helper)

private struct KomoMatchedGeometry: ViewModifier {
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
