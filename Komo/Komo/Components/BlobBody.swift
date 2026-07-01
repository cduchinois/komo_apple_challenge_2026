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

    // OKLCH ramps
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
            // Base internal gradient
            shape.fill(RadialGradient(
                colors: [c2, c3],
                center: UnitPoint(x: 0.5, y: 0.74),
                startRadius: 0,
                endRadius: size * 0.52))

            // Grand glow central
            shape.fill(RadialGradient(
                colors: [.white.opacity(0.7), .white.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.5),
                startRadius: 0,
                endRadius: size * 0.45))
                .blendMode(.screen)

            // Top glow highlight (the inner light source).
            shape.fill(RadialGradient(
                colors: [c1, c1.opacity(0)],
                center: UnitPoint(x: 0.46, y: 0.18),
                startRadius: 0,
                endRadius: size * 0.35))
                .blendMode(.screen)

            // Inner top light + bottom shade for volume.
            shape.fill(RadialGradient(
                colors: [.white.opacity(cute ? 0.75 : 0.5), .clear],
                center: UnitPoint(x: 0.5, y: 0.1),
                startRadius: 0, endRadius: size * 0.35))
                .blendMode(.screen)
            shape.fill(RadialGradient(
                colors: [.clear, Color(oklch: 0.5, 0.13, hue + 30, opacity: 0.7)],
                center: UnitPoint(x: 0.5, y: 0.95),
                startRadius: size * 0.2, endRadius: size * 0.6))
                .blendMode(.multiply)

            styleOverlay
        }
        .frame(width: size, height: size)
        .opacity(cute ? (tired ? 0.96 : 0.94) : 1)
        .blur(radius: cute ? 0.5 : (style == .aurora ? 2 : 0))
        .compositingGroup()
        .shadow(color: Color(oklch: 0.6, 0.12, hue + 20, opacity: 0.42), radius: 18, x: 0, y: 14)
    }

    // MARK: Surface styles

    @ViewBuilder
    private var styleOverlay: some View {
        switch style {
        case .glossy:
            // High-fidelity 3D Liquid Glass effect (Pure SwiftUI)
            ZStack {
                // 1. Core reflection - specular highlight on top left
                shape.fill(RadialGradient(
                    colors: [.white.opacity(0.9), .white.opacity(0)],
                    center: UnitPoint(x: 0.25, y: 0.2),
                    startRadius: 0, endRadius: size * 0.3))
                    .blendMode(.screen)
                
                // 2. Caustic bounce - warm light bounce on the bottom right
                shape.fill(RadialGradient(
                    colors: [c1.opacity(0.6), .clear],
                    center: UnitPoint(x: 0.75, y: 0.8),
                    startRadius: 0, endRadius: size * 0.4))
                    .blendMode(.screen)
                
                // 3. Liquid Glass overlay (using iOS 26+ native glassEffect via theme)
                Color.white.opacity(0.01)
                    .komoGlass(shape, tint: .white.opacity(0.1))
                
                // 4. Sharp inner rim light to define the 3D edge
                shape.stroke(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.4), .clear, .white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: size * 0.02
                )
                .blendMode(.screen)
                
                // 5. Secondary rim light for thickness (Fresnel effect)
                shape.stroke(
                    LinearGradient(
                        colors: [.clear, .clear, .white.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: size * 0.04
                )
                .blur(radius: 3)
                .blendMode(.screen)

                // 6. Magical dust (sparkles inside the liquid)
                MagicalDustOverlay(seed: 42, opacity: 0.8, dot: size * 0.008)
                    .clipShape(shape)
                    .blendMode(.screen)
            }
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

/// Tiny white glowing particles for the glossy 3D blob look.
struct MagicalDustOverlay: View {
    var seed: UInt64
    var opacity: Double
    var dot: CGFloat

    var body: some View {
        Canvas { ctx, sizeIn in
            var rng = SplitMix64(seed: seed)
            let count = 180
            for _ in 0..<count {
                let x = CGFloat(rng.nextUnit()) * sizeIn.width
                let y = CGFloat(rng.nextUnit()) * sizeIn.height
                let a = 0.15 + rng.nextUnit() * 0.85
                let r = dot * (0.5 + rng.nextUnit() * 1.5)
                let rect = CGRect(x: x, y: y, width: r, height: r)
                ctx.fill(Path(ellipseIn: rect),
                         with: .color(.white.opacity(a * opacity)))
            }
        }
    }
}
