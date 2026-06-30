//  BlobShape.swift
//  Komo
//
//  The companion's organic silhouette. The web prototype morphs an asymmetric
//  CSS `border-radius` between two states (komoMorph / komoMochi). We reproduce
//  that "gel settling" feel natively with a radial sum-of-sines blob whose
//  harmonics are desynced so it never wobbles mechanically. `morph` is the
//  animatable phase driven by BlobView's TimelineView.

import SwiftUI

struct BlobShape: Shape {
    /// Loop phase in radians-ish (0...2π worth of travel); animatable.
    var morph: Double
    /// Per-instance offset so two blobs never share the exact same wobble.
    var seed: Double = 0
    /// Overall wobble strength (fraction of radius).
    var amplitude: Double = 0.06
    /// Slight vertical squash to read as "weighted" / sitting.
    var squash: Double = 0.96

    var animatableData: Double {
        get { morph }
        set { morph = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let baseR = min(rect.width, rect.height) / 2
        let segments = 64
        var points: [CGPoint] = []
        points.reserveCapacity(segments)

        for i in 0..<segments {
            let a = Double(i) / Double(segments) * 2 * .pi
            // Three desynced harmonics → asymmetric, living deformation.
            let r = baseR * (1
                + amplitude * sin(3 * a + morph + seed)
                + amplitude * 0.6 * sin(2 * a - morph * 0.8 + seed * 1.7)
                + amplitude * 0.35 * sin(5 * a + morph * 1.3 + seed * 0.5))
            let x = cx + cos(a) * r
            // Apply the gentle squash so the base feels grounded.
            let y = cy + sin(a) * r * squash
            points.append(CGPoint(x: x, y: y))
        }
        return Path.smoothClosed(points)
    }
}

extension Path {
    /// Build a smooth closed curve through `points` using a Catmull-Rom spline
    /// converted to cubic Béziers.
    static func smoothClosed(_ points: [CGPoint]) -> Path {
        var path = Path()
        let n = points.count
        guard n > 2 else {
            path.addLines(points)
            path.closeSubpath()
            return path
        }
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}
