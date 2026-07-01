//  Motion.swift
//  Komo
//
//  Keyframe-track interpolation utilities retained after the mascot rollout.
//  The old BlobView motion presets (BlobAnim / MotionPreset / BlobTransform)
//  were removed — the new KomoMascotView uses the timings from
//  `description_usage_manual.md` directly. `KeyStop` + `track(_:_:)` remain
//  because `ChargeFill` (Restores screen) still animates its liquid rise
//  through a keyframe track.

import SwiftUI

// MARK: - Keyframe interpolation

/// One stop on a keyframe track: a normalized time and the value at that time.
struct KeyStop {
    var t: Double
    var v: Double
    init(_ t: Double, _ v: Double) { self.t = t; self.v = v }
}

enum Easing {
    /// Smooth ease-in-out used to approximate CSS `ease-in-out` / soft
    /// cubic-beziers between adjacent keyframe stops.
    static func smooth(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }
}

/// Interpolate a track of `KeyStop`s at the given loop `phase` (0...1),
/// easing each segment. Tracks are assumed to start at t=0 and end at t=1.
func track(_ phase: Double, _ stops: [KeyStop]) -> Double {
    guard let first = stops.first else { return 0 }
    if phase <= first.t { return first.v }
    for i in 1..<stops.count {
        let a = stops[i - 1], b = stops[i]
        if phase <= b.t {
            let span = b.t - a.t
            let local = span <= 0 ? 0 : (phase - a.t) / span
            return a.v + (b.v - a.v) * Easing.smooth(local)
        }
    }
    return stops.last!.v
}
