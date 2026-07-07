//  Effects.swift
//  Komo
//
//  Screen-level ambient effects ported from the prototype's CSS: the global photo
//  backdrop, the soft glow halo (komoGlowSoft), the rotating sun-ray fans
//  (komoRays), the liquid charge fill (komoCharge), the onboarding step dots, and
//  the tap speech bubble (komoPop). All animations honor Reduce Motion.

import SwiftUI

// MARK: - Global background

/// The warm photographic backdrop used behind every screen, with the prototype's
/// gradient veil and an extra darkening tint on non-main screens so white text
/// stays legible.
struct KomoBackground: View {
    var darken: Bool

    var body: some View {
        // GeometryReader with `.ignoresSafeArea()` on the OUTSIDE reports the
        // full window size (safe-area extension included). We then set the
        // Image's frame to that explicit height, so `.aspectRatio(.fill)`
        // scales the image based on the FULL screen height — the width
        // naturally overshoots for tall containers (iPad's iPhone-app compat
        // frame) and gets `.clipped()`. This is the user's ask: fit the
        // background to the full height, let the width bleed off-screen.
        //
        // Previous approach used `.scaledToFill()` + `.frame(maxHeight:.infinity)`
        // which was subtly wrong on iPad: the layout frame was computed AT
        // safe-area-inset height (~20pt short), so the image never covered
        // the strip below the translucent tab bar and the cream fallback
        // leaked through as a "white band".
        GeometryReader { proxy in
            Image("BackgroundImage")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                .clipped()
                .background(Theme.Palette.cream)   // fallback if the asset is missing
                .overlay(
                    // Top warm sheen -> bottom forest shade (matches the source veil).
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0xFFFAE4).opacity(0.30), location: 0),
                            .init(color: .white.opacity(0), location: 0.24),
                            .init(color: Color(hex: 0x163026).opacity(0.04), location: 0.62),
                            .init(color: Color(hex: 0x163026).opacity(0.20), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    darken
                        ? LinearGradient(
                            stops: [
                                .init(color: Color(hex: 0x12281C).opacity(0.55), location: 0),
                                .init(color: Color(hex: 0x142A1E).opacity(0.34), location: 0.4),
                                .init(color: Color(hex: 0x102419).opacity(0.52), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                        : nil
                )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glow halo (komoGlowSoft)

struct GlowHalo: View {
    var color: Color
    var diameter: CGFloat
    var period: Double = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                halo(opacity: 0.6, scale: 1.05)
            } else {
                TimelineView(.animation) { tl in
                    let p = (tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)) / period
                    let s = sin(p * 2 * .pi)
                    halo(opacity: 0.42 + 0.36 * (s * 0.5 + 0.5), scale: 1 + 0.14 * (s * 0.5 + 0.5))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    private func halo(opacity: Double, scale: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: diameter / 2))
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

// MARK: - Sun rays (komoRays) — the Energy screen signature

struct SunRays: View {
    var diameter: CGFloat
    var color: Color
    var spokes: Int
    var period: Double
    var reversed: Bool
    var blur: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var gradient: AngularGradient {
        var stops: [Gradient.Stop] = []
        for i in 0..<spokes {
            let base = Double(i) / Double(spokes)
            stops.append(.init(color: color, location: base))
            stops.append(.init(color: color, location: base + 0.18 / Double(spokes)))
            stops.append(.init(color: color.opacity(0), location: base + 0.2 / Double(spokes)))
            stops.append(.init(color: color.opacity(0), location: base + 1.0 / Double(spokes) - 0.001))
        }
        return AngularGradient(gradient: Gradient(stops: stops), center: .center)
    }

    var body: some View {
        Group {
            if reduceMotion {
                rays(angle: 0)
            } else {
                TimelineView(.animation) { tl in
                    let p = (tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)) / period
                    rays(angle: (reversed ? -p : p) * 360)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    private func rays(angle: Double) -> some View {
        Circle()
            .fill(gradient)
            .mask(
                Circle().strokeBorder(.black, lineWidth: diameter * 0.24)
                    .blur(radius: diameter * 0.04)
            )
            .blur(radius: blur)
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Charge fill (komoCharge) — the Restores screen hero

struct ChargeFill: View {
    var size: CGFloat
    var period: Double = 5.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = BlobShape(morph: 0.8)

    var body: some View {
        Group {
            if reduceMotion {
                fill(heightFrac: 0.6, opacity: 1)
            } else {
                TimelineView(.animation) { tl in
                    let p = (tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)) / period
                    let (h, o) = charge(p)
                    fill(heightFrac: h, opacity: o)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    /// komoCharge keyframe: height 8→14→92→94→8%, fading out on the drop.
    private func charge(_ p: Double) -> (CGFloat, Double) {
        let h = track(p, [
            KeyStop(0, 0.08), KeyStop(0.12, 0.14), KeyStop(0.72, 0.92),
            KeyStop(0.82, 0.94), KeyStop(1, 0.08)
        ])
        let o = track(p, [KeyStop(0, 1), KeyStop(0.90, 1), KeyStop(1, 0.15)])
        return (CGFloat(h), o)
    }

    private func fill(heightFrac: CGFloat, opacity: Double) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .top) {
                Rectangle().fill(LinearGradient(
                    colors: [Color(hex: 0xBEF8A5).opacity(0.32),
                             Color(hex: 0x96EE8C).opacity(0.52),
                             Color(hex: 0x60DE78).opacity(0.74)],
                    startPoint: .top, endPoint: .bottom))
                // bright meniscus line riding the top
                Capsule().fill(Color(hex: 0xD6FFB9).opacity(0.85))
                    .frame(height: 6)
                    .blur(radius: 1)
                    .offset(y: -3)
            }
            .frame(height: size * heightFrac)
        }
        .opacity(opacity)
    }
}

// MARK: - Onboarding step dots

struct StepDots: View {
    /// Index of the current step among intro/energy/sleep/drains/restores.
    var current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.white : Color.white.opacity(0.35))
                    .frame(width: i == current ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.3), value: current)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of 5")
    }
}

// MARK: - Speech bubble (komoPop)

struct SpeechBubble: View {
    var text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.body(15, weight: .semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 260)
            .komoGlassCard(cornerRadius: 22, fillOpacity: 0.7, strokeOpacity: 0.75, shadow: true)
            .overlay(alignment: .bottom) {
                BubbleTail()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 18, height: 12)
                    .offset(y: 10)
            }
            .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                       control: CGPoint(x: rect.minX + 2, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - 2, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
