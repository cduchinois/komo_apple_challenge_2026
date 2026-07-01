//  BlobLegs.swift
//  Komo
//
//  Native port of renderLegs(): floating (none), stubs, wiggly, or a little
//  skateboard. Drawn behind the body so they tuck under the silhouette.

import SwiftUI

struct BlobLegs: View {
    var size: CGFloat
    var color: Color
    var style: LegStyle
    /// Wiggle rotation in degrees (driven by BlobView's clock); only used by .wiggly.
    var wiggle: Double = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch style {
            case .none:
                EmptyView()
            case .wheels:
                skateboard
            case .stubs, .wiggly:
                legs
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private var gap: CGFloat { size * 0.13 }
    private var top: CGFloat { size * 0.86 }

    private var legs: some View {
        let isWiggly = style == .wiggly
        let lw = isWiggly ? size * 0.05 : size * 0.13
        let lh = isWiggly ? size * 0.17 : size * 0.10
        return ForEach([-1.0, 1.0], id: \.self) { s in
            RoundedRectangle(cornerRadius: lw / 2, style: .continuous)
                .fill(color)
                .frame(width: lw, height: lh)
                .rotationEffect(.degrees(isWiggly ? (s < 0 ? wiggle : -wiggle) : 0), anchor: .top)
                .offset(x: size / 2 + CGFloat(s) * gap - lw / 2, y: top)
        }
    }

    private var skateboard: some View {
        let bw = size * 0.52
        let deckH = size * 0.055
        let wh = size * 0.10
        return ZStack(alignment: .topLeading) {
            Capsule().fill(color)
                .frame(width: bw, height: deckH)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            ForEach([0.13, 0.87], id: \.self) { fx in
                Circle().fill(Color(hex: 0x2B2B32))
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: wh * 0.3))
                    .frame(width: wh, height: wh)
                    .offset(x: bw * fx - wh / 2, y: deckH * 0.55)
            }
        }
        .frame(width: bw, alignment: .topLeading)
        .offset(x: (size - bw) / 2, y: top + size * 0.02)
    }
}
