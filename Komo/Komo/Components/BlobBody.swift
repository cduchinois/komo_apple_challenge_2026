//  BlobBody.swift
//  Komo
//
//  The silhouette fill: the internal glowing gradient + inner light/shade that
//  give the creature volume, plus the four selectable surface styles. Colors are
//  the prototype's exact OKLCH ramps. When `cute` is true the body uses the soft
//  "mochi" look (the app's default companion); the non-cute ramp is used for the
//  small character previews.

import SwiftUI

struct BlobBody: View {
    var size: CGFloat
    var hue: Double
    var cute: Bool
    var tired: Bool
    var style: BlobStyle
    var morph: Double

    private var shape: BlobShape { BlobShape(morph: morph) }

    // OKLCH ramps (verbatim from renderBlob)
    private var c1: Color {
        if cute { return tired ? Color(oklch: 0.86, 0.10, hue - 6) : Color(oklch: 0.93, 0.05, hue) }
        return Color(oklch: 0.84, 0.11, hue)
    }
    private var c2: Color {
        if cute { return tired ? Color(oklch: 0.70, 0.15, hue + 14) : Color(oklch: 0.84, 0.075, hue + 16) }
        return Color(oklch: 0.68, 0.16, hue + 18)
    }
    private var c3: Color {
        if cute { return tired ? Color(oklch: 0.56, 0.18, hue + 30) : Color(oklch: 0.74, 0.09, hue + 32) }
        return Color(oklch: 0.56, 0.16, hue + 40)
    }

    var body: some View {
        ZStack {
            // Base internal gradient — bottom-weighted body color.
            shape.fill(RadialGradient(
                colors: [c2, c3],
                center: UnitPoint(x: 0.5, y: 0.74),
                startRadius: 0,
                endRadius: size * 0.52))

            // Top glow highlight (the inner light source).
            shape.fill(RadialGradient(
                colors: [c1, c1.opacity(0)],
                center: UnitPoint(x: 0.46, y: 0.22),
                startRadius: 0,
                endRadius: size * 0.34))

            // Inner top light + bottom shade for volume.
            shape.fill(RadialGradient(
                colors: [.white.opacity(cute ? 0.6 : 0.45), .clear],
                center: UnitPoint(x: 0.5, y: 0.12),
                startRadius: 0, endRadius: size * 0.3))
                .blendMode(.screen)
            shape.fill(RadialGradient(
                colors: [.clear, Color(oklch: 0.5, 0.13, hue + 30, opacity: 0.5)],
                center: UnitPoint(x: 0.5, y: 0.92),
                startRadius: size * 0.18, endRadius: size * 0.55))
                .blendMode(.multiply)

            styleOverlay
        }
        .frame(width: size, height: size)
        .opacity(cute ? (tired ? 0.95 : 0.86) : 1)
        .blur(radius: cute ? 0.5 : (style == .aurora ? 2 : 0))
        .compositingGroup()
        .shadow(color: Color(oklch: 0.6, 0.12, hue + 20, opacity: 0.42), radius: 18, x: 0, y: 14)
    }

    // MARK: Surface styles

    @ViewBuilder
    private var styleOverlay: some View {
        switch style {
        case .glossy:
            // Bright specular cap, liquid-glass jelly.
            shape.fill(RadialGradient(
                colors: [.white.opacity(0.85), .white.opacity(0)],
                center: UnitPoint(x: 0.34, y: 0.26),
                startRadius: 0, endRadius: size * 0.28))
                .blendMode(.screen)
        case .fuse:
            GrainOverlay(seed: 11, opacity: 0.5, dot: size * 0.012)
                .clipShape(shape)
                .blendMode(.overlay)
        case .clay:
            GrainOverlay(seed: 7, opacity: 0.35, dot: size * 0.02)
                .clipShape(shape)
                .blendMode(.softLight)
        case .aurora:
            shape.fill(RadialGradient(
                colors: [c1.opacity(0.6), .clear],
                center: UnitPoint(x: 0.7, y: 0.5),
                startRadius: 0, endRadius: size * 0.4))
                .blendMode(.screen)
        }
    }
}

/// A cheap, deterministic speckle texture for the grain / fur surfaces,
/// approximating the prototype's feTurbulence filters without SVG.
struct GrainOverlay: View {
    var seed: UInt64
    var opacity: Double
    var dot: CGFloat

    var body: some View {
        Canvas { ctx, sizeIn in
            var rng = SplitMix64(seed: seed)
            let count = 220
            for _ in 0..<count {
                let x = CGFloat(rng.nextUnit()) * sizeIn.width
                let y = CGFloat(rng.nextUnit()) * sizeIn.height
                let a = 0.25 + rng.nextUnit() * 0.6
                let bright = rng.nextUnit() > 0.5
                let r = dot * (0.6 + rng.nextUnit())
                let rect = CGRect(x: x, y: y, width: r, height: r)
                ctx.fill(Path(ellipseIn: rect),
                         with: .color((bright ? Color.white : Color.black).opacity(a * opacity)))
            }
        }
    }
}

/// Tiny deterministic PRNG so grain looks identical every frame (no flicker).
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}
