//  BlobFace.swift
//  Komo
//
//  Native port of the prototype's renderEyes(): cartoon / happy / cool / spark
//  eye styles, the optional "cute" mouth + cheeks, and the half-lidded "tired"
//  face. Positions are computed from the blob size exactly like the source.

import SwiftUI

private let ink = Color(hex: 0x2B2B32)

struct BlobFace: View {
    var size: CGFloat
    var eyes: EyeStyle
    var cute: Bool
    var tired: Bool
    /// 1 = open, ~0.12 = mid-blink (driven by BlobView's clock).
    var blink: CGFloat
    var twinkle: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            if tired {
                tiredFace
            } else {
                switch eyes {
                case .cool:  coolGlasses
                case .happy: happyFace
                case .spark: sparkEyes
                case .cartoon: cartoonEyes
                }
                if cute { cuteMouthAndCheeks }
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: Geometry helpers

    private var gap: CGFloat { size * 0.16 }
    private var cy: CGFloat { size * (cute ? 0.385 : 0.44) }

    /// Place a view of (w,h) at CSS top/left coordinates.
    private func at(_ view: some View, left: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        view.frame(width: w, height: h).offset(x: left, y: top)
    }

    // MARK: Cartoon (default)

    private var cartoonEyes: some View {
        let ew = size * 0.14
        return ZStack(alignment: .topLeading) {
            ForEach([-1.0, 1.0], id: \.self) { s in
                let left = size / 2 + CGFloat(s) * gap - ew / 2
                at(cartoonEye(ew: ew), left: left, top: cy, w: ew, h: ew)
            }
        }
    }

    private func cartoonEye(ew: CGFloat) -> some View {
        ZStack {
            Circle().fill(.white)
                .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 1.5))
            Circle().fill(ink)
                .frame(width: ew * 0.54, height: ew * 0.54)
                .overlay(alignment: .topLeading) {
                    Circle().fill(.white.opacity(0.95))
                        .frame(width: ew * 0.54 * 0.4, height: ew * 0.54 * 0.4)
                        .offset(x: ew * 0.54 * 0.16, y: ew * 0.54 * 0.12)
                }
        }
        .scaleEffect(x: 1, y: blink, anchor: .center)
    }

    // MARK: Happy (arcs + cheeks)

    private var happyFace: some View {
        let ew = size * 0.09
        return ZStack(alignment: .topLeading) {
            ForEach([-1.0, 1.0], id: \.self) { s in
                let baseLeft = size / 2 + CGFloat(s) * gap - ew / 2
                at(
                    ArcShape(up: true)
                        .stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .scaleEffect(x: 1, y: blink, anchor: .bottom),
                    left: baseLeft - ew * 0.15, top: cy + ew * 0.1, w: ew * 1.3, h: ew * 0.85
                )
            }
            cheeks(spread: 1.85, ck: size * 0.13, top: cy + size * 0.13, color: Color(hex: 0xFF8AAA))
            cuteMouth
        }
    }

    // MARK: Cool (sunglasses)

    private var coolGlasses: some View {
        let w = size * 0.62
        let hh = size * 0.2
        let left = (size - w) / 2
        return at(
            HStack(spacing: size * 0.07) {
                lens(corner: hh, dir: 158)
                lens(corner: hh, dir: 202)
            }
            .overlay(
                Rectangle().fill(Color(hex: 0x15151B))
                    .frame(width: size * 0.07, height: 3)
            ),
            left: left, top: cy - hh * 0.2, w: w, h: hh
        )
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }

    private func lens(corner: CGFloat, dir: Double) -> some View {
        RoundedRectangle(cornerRadius: corner * 0.5, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(hex: 0x4D4D5C), Color(hex: 0x1C1C24), Color(hex: 0x050507)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topLeading) {
                Ellipse().fill(LinearGradient(
                    colors: [.white.opacity(0.9), .white.opacity(0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 14, height: 9)
                    .rotationEffect(.degrees(-20))
                    .offset(x: 6, y: 5)
            }
    }

    // MARK: Spark (twinkling stars)

    private var sparkEyes: some View {
        let ew = size * 0.17
        return ZStack(alignment: .topLeading) {
            ForEach([-1.0, 1.0], id: \.self) { s in
                let left = size / 2 + CGFloat(s) * gap - ew / 2
                at(
                    StarShape().fill(ink)
                        .scaleEffect(twinkle),
                    left: left, top: cy, w: ew, h: ew
                )
            }
        }
    }

    // MARK: Cute mouth + cheeks

    private var cuteMouthAndCheeks: some View {
        ZStack(alignment: .topLeading) {
            cuteMouth
            if eyes != .happy {
                cheeks(spread: 1.78, ck: size * 0.14, top: cy + size * 0.125, color: Color(hex: 0xFF96B2))
            }
        }
    }

    private var cuteMouth: some View {
        let mw = size * 0.155
        let mh = size * 0.085
        return at(
            ArcShape(up: false)
                .stroke(ink, style: StrokeStyle(lineWidth: max(2, size * 0.018), lineCap: .round)),
            left: size / 2 - mw / 2, top: cy + size * 0.14, w: mw, h: mh
        )
    }

    private func cheeks(spread: CGFloat, ck: CGFloat, top: CGFloat, color: Color) -> some View {
        ForEach([-1.0, 1.0], id: \.self) { s in
            at(
                Ellipse().fill(RadialGradient(
                    colors: [color.opacity(0.9), color.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: ck * 0.5)),
                left: size / 2 + CGFloat(s) * gap * spread - ck / 2, top: top, w: ck, h: ck * 0.66
            )
        }
    }

    // MARK: Tired (half-lidded)

    private var tiredFace: some View {
        let ew = size * 0.17
        let eh = size * 0.16
        let dl = max(2, size * 0.022)
        return ZStack(alignment: .topLeading) {
            ForEach([-1.0, 1.0], id: \.self) { s in
                let left = size / 2 + CGFloat(s) * gap - ew / 2
                at(
                    ZStack(alignment: .bottom) {
                        // lower half-disc "sleepy" eye
                        UnevenRoundedRectangle(bottomLeadingRadius: ew, bottomTrailingRadius: ew)
                            .fill(.white)
                            .frame(height: eh * 0.54)
                            .overlay(alignment: .bottom) {
                                Ellipse().fill(ink)
                                    .frame(width: ew * 0.58, height: eh * 0.54 * 0.92)
                                    .offset(y: -eh * 0.54 * 0.06)
                            }
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: ew, bottomTrailingRadius: ew))
                        // droopy lid line
                        Rectangle().fill(ink)
                            .frame(width: ew * 1.14, height: dl)
                            .cornerRadius(2)
                            .rotationEffect(.degrees(s < 0 ? -9 : 9))
                            .offset(y: -eh * 0.42)
                    },
                    left: left, top: cy, w: ew, h: eh
                )
            }
            // small tired mouth
            let mw = size * 0.12
            at(
                UnevenRoundedRectangle(bottomLeadingRadius: mw * 0.4, bottomTrailingRadius: mw * 0.4)
                    .fill(ink.opacity(0.5)),
                left: size / 2 - mw / 2, top: cy + size * 0.18, w: mw, h: size * 0.045
            )
        }
    }
}

// MARK: - Small shapes

/// A simple up (∩) or down (∪) arc used for smiles and happy eyes.
struct ArcShape: Shape {
    var up: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                           control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.4))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                           control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.4))
        }
        return p
    }
}

/// A 5-point star matching the spark eye's clip-path silhouette.
struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (0.50, 0.00), (0.61, 0.39), (1.00, 0.50), (0.61, 0.61),
            (0.50, 1.00), (0.39, 0.61), (0.00, 0.50), (0.39, 0.39)
        ]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let point = CGPoint(x: rect.minX + pt.0 * rect.width, y: rect.minY + pt.1 * rect.height)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}
