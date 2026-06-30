//  Glass.swift
//  Komo
//
//  Liquid Glass surface helpers. The prototype fakes glass in CSS with
//  `backdrop-filter: blur() saturate()` over translucent white. On iOS 26 we use
//  the real `glassEffect(_:in:)` API, falling back to a material on older OSes so
//  the project still previews if the deployment target is lowered.

import SwiftUI

extension View {

    /// Apply an iOS 26 Liquid Glass surface clipped to `shape`.
    /// - Parameters:
    ///   - shape: the clip/region for the glass.
    ///   - tint: optional tint pulled through the glass.
    ///   - interactive: whether the glass reacts to touch (use on buttons).
    @ViewBuilder
    func komoGlass(
        _ shape: some Shape,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            var glass: Glass = .regular
            if let tint { glass = glass.tint(tint) }
            if interactive { glass = glass.interactive() }
            self.glassEffect(glass, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
    }

    /// A frosted translucent-white card the way the prototype draws its insight
    /// card and option chips: white fill + hairline white stroke + soft shadow,
    /// layered on top of real glass for the blur/saturation.
    func komoGlassCard(
        cornerRadius: CGFloat,
        fillOpacity: Double = 0.16,
        strokeOpacity: Double = 0.30,
        shadow: Bool = false,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(Theme.Palette.glassFill(fillOpacity), in: shape)
            .komoGlass(shape, tint: tint, interactive: interactive)
            .overlay(shape.strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1))
            .compositingGroup()
            .shadow(
                color: shadow ? Theme.cardShadow : .clear,
                radius: shadow ? 22 : 0,
                x: 0, y: shadow ? 16 : 0
            )
    }
}

/// A circular glass back-button, reused on every onboarding header
/// (matches the prototype's 42pt translucent circle with a chevron).
struct GlassBackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .komoGlassCard(cornerRadius: 21, fillOpacity: 0.16, strokeOpacity: 0.28, interactive: true)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}
