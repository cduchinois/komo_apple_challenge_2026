//  Theme.swift
//  Komo
//
//  The single shared design system extracted from the exported prototype
//  (KOMO Pages.dc.html). Every screen reads its colors, radii, type, and spacing
//  from here so the visual language stays consistent and tweakable in one place.
//
//  Aesthetic: Apple Liquid Glass over warm creamy off-white -> pale honey, with a
//  living green companion. Tone is calm and non-punitive.

import SwiftUI

enum Theme {

    // MARK: - Palette (exact values from the prototype's inline styles)

    enum Palette {
        /// App canvas behind everything (the warm creamy off-white).
        static let cream = Color(hex: 0xFAF9F5)

        // Ink / text on light glass surfaces
        static let ink = Color(hex: 0x1C1C1E)
        static let inkSoft = Color(hex: 0x2A3A2F)
        static let inkForest = Color(hex: 0x22382B)
        static let inkMuted = Color(hex: 0x2C3C30)

        /// Primary call-to-action green ("Let KOMO read my Health Data").
        static let primaryGreen = Color(hex: 0x2F6B41)

        /// Energy bar gradient stops.
        static let energyBarStart = Color(hex: 0x4EA35E)
        static let energyBarEnd = Color(hex: 0x93D76E)

        /// Sprout / leaf accents used on glyphs and small strokes.
        static let leaf = Color(hex: 0x3F7D52)

        /// Heart "liked" color.
        static let heart = Color(hex: 0xFF6B81)

        /// The daily energy accent — `oklch(0.72 0.15 150)` in the source.
        static let accent = Color(oklch: 0.72, 0.15, 150)

        // Translucent white "glass" fills, by strength.
        static func glassFill(_ a: Double) -> Color { Color.white.opacity(a) }
        static func glassStroke(_ a: Double) -> Color { Color.white.opacity(a) }
    }

    // MARK: - Corner radii (matched to the prototype's border-radius values)

    enum Radius {
        static let chip: CGFloat = 16
        static let field: CGFloat = 14
        static let button: CGFloat = 18
        static let card: CGFloat = 20
        static let action: CGFloat = 26
        static let insight: CGFloat = 28
        static let nav: CGFloat = 28
        static let dock: CGFloat = 34
    }

    // MARK: - Spacing scale

    enum Space {
        static let screenH: CGFloat = 24      // horizontal screen padding
        static let optionGap: CGFloat = 10
        static let sectionGap: CGFloat = 16
        static let cardPad: CGFloat = 18
    }

    /// The fixed design canvas the prototype was authored at (iPhone logical pts).
    enum Canvas {
        static let width: CGFloat = 393
        static let height: CGFloat = 852
    }

    // MARK: - Typography
    //
    // The prototype mixed display webfonts, but the brief asks for a native Apple
    // feel. We use the system font, rounded for the soft companion voice, and let
    // everything scale with Dynamic Type via `relativeTo:`.

    enum Font {
        static func wordmark(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        static func display(_ size: CGFloat, relativeTo style: SwiftUI.Font.TextStyle = .title) -> SwiftUI.Font {
            .system(size: size, weight: .bold, design: .rounded).leading(.tight)
        }
        static func title(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func label(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }
    }

    /// Soft shadow used under glass cards (matches `0 18px 42px rgba(28,58,40,0.22)`).
    static let cardShadow = Color(hex: 0x1C3A28).opacity(0.22)
}

// MARK: - Hex convenience

extension Color {
    /// Build a color from a 0xRRGGBB integer.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
