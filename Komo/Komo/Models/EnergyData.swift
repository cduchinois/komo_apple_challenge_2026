//  EnergyData.swift
//  Komo
//
//  Plain models for the energy snapshot, the day's stats, and the companion's
//  insight lines. These are deliberately simple value types so a real HealthKit
//  source can produce them later without touching any view code.

import SwiftUI

/// Whether a stat reads as restorative ("good") or draining ("warn").
enum StatTone {
    case good, warn

    /// The small status dot color the prototype uses
    /// (`oklch(0.72 0.14 150)` good / `oklch(0.8 0.14 72)` warn).
    var dotColor: Color {
        switch self {
        case .good: return Color(oklch: 0.72, 0.14, 150)
        case .warn: return Color(oklch: 0.80, 0.14, 72)
        }
    }
}

/// One passive signal shown on the stats scroll.
struct EnergyStat: Identifiable {
    let id: String
    let label: String
    let value: String
    let unit: String
    let sub: String
    let tone: StatTone

    var iconName: String {
        switch id {
        case "hr": return "heart.fill"
        case "steps": return "figure.walk"
        case "sleep": return "moon.stars.fill"
        case "stress": return "waveform.path.ecg"
        case "hrv": return "bolt.heart.fill"
        case "activity": return "flame.fill"
        case "calendar": return "calendar"
        case "screen": return "iphone"
        case "standing": return "figure.stand"
        default: return "circle.fill"
        }
    }
}

/// The current energy reading shown on the main screen.
struct EnergySnapshot {
    var word: String          // "High", "Bright", ...
    var percent: Int          // 0...100
    var daysTogether: Int
    var rechargedBy: String
    var usedBy: String
    var headlineInsight: String
}
