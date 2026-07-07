//  BlobShape.swift
//  Komo
//
//  Legacy jelly silhouette kept only as the clip shape for `ChargeFill`
//  (the Restores screen's liquid-rise hero). The old BlobView that used to
//  morph this shape is gone; `morph` is now supplied by `ChargeFill` directly.
//  Original per-corner elliptical-arc morph (komoMochi) preserved verbatim.

import SwiftUI

struct BlobShape: Shape {
    /// Loop phase in 0...1 (wraps). Animatable.
    var morph: Double

    var animatableData: Double {
        get { morph }
        set { morph = newValue }
    }

    // komoMochi keyframes. Per corner order [TL, TR, BR, BL]:
    //   h = horizontal radii (% of width), v = vertical radii (% of height).
    // Matches: border-radius: a% b% c% d% / e% f% g% h%
    private static let keyframes: [(h: [Double], v: [Double])] = [
        (h: [56, 44, 47, 53], v: [64, 66, 38, 36]),   // 0%
        (h: [50, 50, 43, 57], v: [60, 63, 41, 40]),   // 25%
        (h: [47, 53, 52, 48], v: [69, 59, 43, 33]),   // 50%
        (h: [54, 46, 48, 52], v: [61, 65, 37, 39]),   // 75%
        (h: [56, 44, 47, 53], v: [64, 66, 38, 36]),   // 100% (== 0%)
    ]
    private static let stops: [Double] = [0, 0.25, 0.5, 0.75, 1.0]

    func path(in rect: CGRect) -> Path {
        let p = morph - floor(morph)               // wrap to 0...1

        // Find the active keyframe segment and ease across it.
        var i = 0
        while i < BlobShape.stops.count - 2 && p > BlobShape.stops[i + 1] { i += 1 }
        let a = BlobShape.keyframes[i]
        let b = BlobShape.keyframes[i + 1]
        let span = BlobShape.stops[i + 1] - BlobShape.stops[i]
        let local = span <= 0 ? 0 : (p - BlobShape.stops[i]) / span
        let e = local * local * (3 - 2 * local)    // smoothstep (ease-in-out)

        func lerp(_ x: Double, _ y: Double) -> CGFloat { CGFloat(x + (y - x) * e) }

        var hr = [CGFloat](repeating: 0, count: 4)
        var vr = [CGFloat](repeating: 0, count: 4)
        for c in 0..<4 {
            hr[c] = lerp(a.h[c], b.h[c]) / 100 * rect.width
            vr[c] = lerp(a.v[c], b.v[c]) / 100 * rect.height
        }
        return BlobShape.roundedBlob(in: rect, hr: hr, vr: vr)
    }

    /// A rounded rectangle with independent elliptical radii per corner
    /// ([TL, TR, BR, BL]), drawn with cubic-Bézier quarter-ellipses.
    static func roundedBlob(in rect: CGRect, hr: [CGFloat], vr: [CGFloat]) -> Path {
        let k: CGFloat = 0.5522847498              // circle/ellipse Bézier constant
        let xL = rect.minX, xR = rect.maxX
        let yT = rect.minY, yB = rect.maxY

        var p = Path()
        // Start on the top edge, just right of the top-left corner.
        p.move(to: CGPoint(x: xL + hr[0], y: yT))
        p.addLine(to: CGPoint(x: xR - hr[1], y: yT))
        // Top-right corner.
        p.addCurve(to: CGPoint(x: xR, y: yT + vr[1]),
                   control1: CGPoint(x: xR - hr[1] + hr[1] * k, y: yT),
                   control2: CGPoint(x: xR, y: yT + vr[1] - vr[1] * k))
        p.addLine(to: CGPoint(x: xR, y: yB - vr[2]))
        // Bottom-right corner.
        p.addCurve(to: CGPoint(x: xR - hr[2], y: yB),
                   control1: CGPoint(x: xR, y: yB - vr[2] + vr[2] * k),
                   control2: CGPoint(x: xR - hr[2] + hr[2] * k, y: yB))
        p.addLine(to: CGPoint(x: xL + hr[3], y: yB))
        // Bottom-left corner.
        p.addCurve(to: CGPoint(x: xL, y: yB - vr[3]),
                   control1: CGPoint(x: xL + hr[3] - hr[3] * k, y: yB),
                   control2: CGPoint(x: xL, y: yB - vr[3] + vr[3] * k))
        p.addLine(to: CGPoint(x: xL, y: yT + vr[0]))
        // Top-left corner.
        p.addCurve(to: CGPoint(x: xL + hr[0], y: yT),
                   control1: CGPoint(x: xL, y: yT + vr[0] - vr[0] * k),
                   control2: CGPoint(x: xL + hr[0] - hr[0] * k, y: yT))
        p.closeSubpath()
        return p
    }
}
