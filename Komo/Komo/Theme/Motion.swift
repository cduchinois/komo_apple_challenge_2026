//  Motion.swift
//  Komo
//
//  Native re-implementation of the prototype's CSS @keyframes (documented in
//  jsanimationguide.md). Each web keyframe becomes a pure function mapping a loop
//  phase in 0...1 to a `BlobTransform`. We drive these with a TimelineView in
//  BlobView, so the whole creature animates from a single clock and freezes
//  cleanly when Reduce Motion is on.
//
//  Design rule carried over from the guide: durations are intentionally desynced
//  (outer != breathe != morph) so the idle never beats mechanically, and every
//  squash/tilt pivots from bottom-center (transform-origin: 50% 90%).

import SwiftUI

/// The composed 2D transform applied to a blob layer for a given moment.
struct BlobTransform {
    var dx: CGFloat = 0          // translate X (pt at size 200, scaled by caller)
    var dy: CGFloat = 0          // translate Y
    var rotation: Double = 0     // degrees
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1

    static let identity = BlobTransform()
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

// MARK: - Motion presets (per the companion's `motion` trait)

/// Durations (seconds) for the three desynced idle layers, by character motion.
struct MotionPreset {
    var outer: Double
    var breathe: Double
    var morph: Double
    /// Which named outer animation to run.
    var outerKind: BlobAnim
}

extension MotionPreset {
    static func forMotion(_ motion: CompanionMotion) -> MotionPreset {
        switch motion {
        case .calm:    return .init(outer: 14, breathe: 6,   morph: 12,  outerKind: .drift)
        case .bounce:  return .init(outer: 1.5, breathe: 3,  morph: 8,   outerKind: .bounce)
        case .dynamic: return .init(outer: 4.5, breathe: 3.4, morph: 6,  outerKind: .sway)
        case .energy:  return .init(outer: 5,  breathe: 2.2, morph: 4.5, outerKind: .drift)
        }
    }
}

// MARK: - Named animations

/// Every choreography the blob can play (idle outer motions + per-screen moods).
enum BlobAnim {
    // idle outer motions
    case none, drift, sway, bounce, float
    // per-screen moods
    case greet, curious, listen, drowsy, perk, tired

    /// Evaluate this animation at a loop `phase` in 0...1.
    /// Translation values are expressed at a 200pt reference and scaled later.
    func transform(at phase: Double) -> BlobTransform {
        switch self {
        case .none:
            return .identity

        case .drift:
            // komoDrift: 0/100 (0,0) · 33 (6,-9) · 66 (-6,6)
            return BlobTransform(
                dx: track(phase, [KeyStop(0, 0), KeyStop(0.33, 6), KeyStop(0.66, -6), KeyStop(1, 0)]),
                dy: track(phase, [KeyStop(0, 0), KeyStop(0.33, -9), KeyStop(0.66, 6), KeyStop(1, 0)])
            )

        case .sway:
            // komoSway: translate(-7,1) rot -4.5 -> translate(7,-6) rot 4.5
            return BlobTransform(
                dx: track(phase, [KeyStop(0, -7), KeyStop(0.5, 7), KeyStop(1, -7)]),
                dy: track(phase, [KeyStop(0, 1), KeyStop(0.5, -6), KeyStop(1, 1)]),
                rotation: track(phase, [KeyStop(0, -4.5), KeyStop(0.5, 4.5), KeyStop(1, -4.5)])
            )

        case .bounce:
            // komoBounce: 0 -> -16 @22 -> 0 @44 -> -6 @58 -> 0
            return BlobTransform(
                dy: track(phase, [
                    KeyStop(0, 0), KeyStop(0.22, -16), KeyStop(0.44, 0),
                    KeyStop(0.58, -6), KeyStop(0.72, 0), KeyStop(1, 0)
                ])
            )

        case .float:
            // komoFloat: 0 -> -9 -> 0
            return BlobTransform(dy: track(phase, [KeyStop(0, 0), KeyStop(0.5, -9), KeyStop(1, 0)]))

        case .greet:
            // komoGreet one-shot arrival (used here as a gentle settle loop)
            return BlobTransform(
                dy: track(phase, [
                    KeyStop(0, 0), KeyStop(0.20, -11), KeyStop(0.38, 3),
                    KeyStop(0.53, -5), KeyStop(0.70, 0), KeyStop(0.84, -1), KeyStop(1, 0)
                ]),
                rotation: track(phase, [
                    KeyStop(0, 0), KeyStop(0.53, 2.5), KeyStop(0.70, -1.5), KeyStop(0.84, 0.5), KeyStop(1, 0)
                ]),
                scaleX: track(phase, [
                    KeyStop(0, 1), KeyStop(0.20, 0.96), KeyStop(0.38, 1.07),
                    KeyStop(0.53, 0.99), KeyStop(0.70, 1.02), KeyStop(1, 1)
                ]),
                scaleY: track(phase, [
                    KeyStop(0, 1), KeyStop(0.20, 1.06), KeyStop(0.38, 0.93),
                    KeyStop(0.53, 1.02), KeyStop(0.70, 0.99), KeyStop(1, 1)
                ])
            )

        case .curious:
            // komoCurious: tilt -4 -> +5, slight lift
            return BlobTransform(
                dy: track(phase, [KeyStop(0, 0), KeyStop(0.28, -4), KeyStop(0.50, -6), KeyStop(0.74, -2), KeyStop(1, 0)]),
                rotation: track(phase, [KeyStop(0, -4), KeyStop(0.28, 0.5), KeyStop(0.50, 5), KeyStop(0.74, 2), KeyStop(1, -4)]),
                scaleX: track(phase, [KeyStop(0, 1), KeyStop(0.28, 0.98), KeyStop(0.50, 1.02), KeyStop(1, 1)]),
                scaleY: track(phase, [KeyStop(0, 1), KeyStop(0.28, 1.03), KeyStop(0.50, 0.98), KeyStop(1, 1)])
            )

        case .listen:
            // komoListen: attentive lean -3 -> +4
            return BlobTransform(
                dy: track(phase, [KeyStop(0, 1), KeyStop(0.26, -3), KeyStop(0.50, -5), KeyStop(0.74, -1), KeyStop(1, 1)]),
                rotation: track(phase, [KeyStop(0, -3), KeyStop(0.26, -0.5), KeyStop(0.50, 4), KeyStop(0.74, 1.5), KeyStop(1, -3)]),
                scaleX: track(phase, [KeyStop(0, 1), KeyStop(0.26, 1.015), KeyStop(0.50, 0.99), KeyStop(1, 1)]),
                scaleY: track(phase, [KeyStop(0, 1), KeyStop(0.26, 0.985), KeyStop(0.50, 1.01), KeyStop(1, 1)])
            )

        case .drowsy:
            // komoDrowsy: droop, squashed
            return BlobTransform(
                dy: track(phase, [KeyStop(0, 6), KeyStop(0.33, 9), KeyStop(0.66, 8), KeyStop(1, 6)]),
                rotation: track(phase, [KeyStop(0, -1.5), KeyStop(0.33, 0.5), KeyStop(0.66, 1.8), KeyStop(1, -1.5)]),
                scaleX: track(phase, [KeyStop(0, 1.04), KeyStop(0.33, 1.05), KeyStop(0.66, 1.045), KeyStop(1, 1.04)]),
                scaleY: track(phase, [KeyStop(0, 0.94), KeyStop(0.33, 0.93), KeyStop(0.66, 0.935), KeyStop(1, 0.94)])
            )

        case .perk:
            // komoPerk: perk back up, springy bob
            return BlobTransform(
                dy: track(phase, [
                    KeyStop(0, -1), KeyStop(0.26, -12), KeyStop(0.48, 2),
                    KeyStop(0.66, -5), KeyStop(0.82, -1), KeyStop(1, -1)
                ]),
                scaleX: track(phase, [
                    KeyStop(0, 1), KeyStop(0.26, 0.96), KeyStop(0.48, 1.06),
                    KeyStop(0.66, 0.99), KeyStop(0.82, 1.01), KeyStop(1, 1)
                ]),
                scaleY: track(phase, [
                    KeyStop(0, 1), KeyStop(0.26, 1.06), KeyStop(0.48, 0.94),
                    KeyStop(0.66, 1.02), KeyStop(0.82, 0.99), KeyStop(1, 1)
                ])
            )

        case .tired:
            // komoTired: heavy slow sway translateY +3->+6, ±2°
            return BlobTransform(
                dy: track(phase, [KeyStop(0, 3), KeyStop(0.5, 6), KeyStop(1, 3)]),
                rotation: track(phase, [KeyStop(0, -2), KeyStop(0.5, 2), KeyStop(1, -2)])
            )
        }
    }

    /// Default loop duration (s) for the mood animations. Idle outer motions get
    /// their duration from the `MotionPreset` instead.
    var moodDuration: Double {
        switch self {
        case .greet:   return 2.6
        case .curious: return 4.3
        case .listen:  return 5.2
        case .drowsy:  return 6.4
        case .perk:    return 4.1
        case .tired:   return 4.8
        case .float:   return 5
        default:       return 6
        }
    }
}

// MARK: - Reduce Motion

extension EnvironmentValues {
    /// A blob phase to use when motion should be still: a calm, slightly-open
    /// resting pose rather than a hard 0.
    var blobRestPhase: Double { 0.18 }
}
