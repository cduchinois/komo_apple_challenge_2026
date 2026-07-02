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

// MARK: - Legacy BlobView compatibility

struct BlobTransform {
    var dx: Double = 0
    var dy: Double = 0
    var scaleX: Double = 1
    var scaleY: Double = 1
    var rotation: Double = 0
}

enum BlobAnim: Equatable {
    case none, float, listen, bounce, charge

    var moodDuration: Double {
        switch self {
        case .none: return 1
        case .float: return 6.5
        case .listen: return 4.8
        case .bounce: return 2.8
        case .charge: return 3.6
        }
    }

    func transform(at phase: Double) -> BlobTransform {
        let p = phase * 2 * .pi
        switch self {
        case .none:
            return BlobTransform()
        case .float:
            return BlobTransform(dy: -7 * sin(p), rotation: 0.7 * cos(p))
        case .listen:
            return BlobTransform(dy: -3 * sin(p), scaleX: 1 + 0.015 * sin(p), scaleY: 1 - 0.015 * sin(p))
        case .bounce:
            let hop = max(0, sin(p))
            return BlobTransform(dy: -10 * hop, scaleX: 1 + 0.035 * hop, scaleY: 1 - 0.035 * hop)
        case .charge:
            return BlobTransform(dy: -5 * sin(p), scaleX: 1 + 0.025 * sin(p), scaleY: 1 - 0.025 * sin(p))
        }
    }
}

struct MotionPreset {
    var outer: Double
    var breathe: Double
    var morph: Double
    var outerKind: BlobAnim

    static func forMotion(_ motion: CompanionMotion) -> MotionPreset {
        switch motion {
        case .calm:
            return MotionPreset(outer: 6.5, breathe: 3.6, morph: 8.0, outerKind: .float)
        case .bounce:
            return MotionPreset(outer: 2.8, breathe: 2.7, morph: 5.0, outerKind: .bounce)
        case .dynamic:
            return MotionPreset(outer: 4.8, breathe: 3.1, morph: 6.0, outerKind: .listen)
        case .energy:
            return MotionPreset(outer: 3.6, breathe: 2.4, morph: 4.5, outerKind: .charge)
        }
    }
}

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
