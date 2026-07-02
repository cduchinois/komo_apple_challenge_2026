//  OKLCH.swift
//  Komo
//
//  The web prototype builds the blob's gradient ramps in the OKLCH color space
//  (e.g. `oklch(0.84 0.11 150)`). SwiftUI's `Color` has no native OKLCH
//  initializer, so we convert OKLCH -> OKLab -> linear sRGB -> gamma sRGB here.
//  This keeps the creature's color identical to the source of truth for any hue,
//  which matters because the daily hue can shift with the user's energy later.

import SwiftUI

/// A lightweight OKLCH color value. `l` is perceptual lightness (0...1),
/// `c` is chroma (~0...0.4), `h` is hue in degrees (0...360).
struct OKLCH: Equatable {
    var l: Double
    var c: Double
    var h: Double

    init(_ l: Double, _ c: Double, _ h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }
}

extension Color {

    /// Build a SwiftUI Color from OKLCH components, matching CSS `oklch()`.
    init(oklch l: Double, _ c: Double, _ h: Double, opacity: Double = 1) {
        let (r, g, b) = OKLCHConverter.toLinearSRGB(l: l, c: c, h: h)
        self = Color(
            .sRGB,
            red: OKLCHConverter.gammaEncode(r),
            green: OKLCHConverter.gammaEncode(g),
            blue: OKLCHConverter.gammaEncode(b),
            opacity: opacity
        )
    }

    init(_ oklch: OKLCH, opacity: Double = 1) {
        self.init(oklch: oklch.l, oklch.c, oklch.h, opacity: opacity)
    }
}

enum OKLCHConverter {

    /// OKLCH -> linear (un-gamma'd) sRGB, each channel clamped to 0...1.
    static func toLinearSRGB(l: Double, c: Double, h: Double) -> (Double, Double, Double) {
        let hr = h * .pi / 180.0
        let a = c * cos(hr)
        let b = c * sin(hr)

        // OKLab -> approximate LMS (cube of cone responses)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b

        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_

        let r =  4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let bl = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        return (clamp01(r), clamp01(g), clamp01(bl))
    }

    /// Linear sRGB channel -> gamma-encoded sRGB (the value SwiftUI's `.sRGB`
    /// space expects).
    static func gammaEncode(_ c: Double) -> Double {
        let v = clamp01(c)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }

    private static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
}
