//  CompanionConfig.swift
//  Komo
//
//  The customizable identity of the companion plus the static option catalogs,
//  ported verbatim from the prototype's data tables (characters, blobStyles,
//  eyeOptions, legOptions, tones, backgrounds).

import SwiftUI

// MARK: - Motion trait

enum CompanionMotion: String, CaseIterable {
    case calm, bounce, dynamic, energy
}

// MARK: - Character

struct CompanionCharacter: Identifiable, Hashable {
    let id: String
    let name: String
    let trait: String
    let motion: CompanionMotion
    let desc: String

    static let all: [CompanionCharacter] = [
        .init(id: "pobble", name: "Pobble", trait: "Bouncy", motion: .bounce,
              desc: "Can’t sit still — springs up to celebrate the tiny wins."),
        .init(id: "moku", name: "Moku", trait: "Calm", motion: .calm,
              desc: "Settles the room. Slow breaths, slow drift, steady company."),
        .init(id: "lumie", name: "Lumie", trait: "Dynamic", motion: .dynamic,
              desc: "Curious and swaying, always leaning toward what’s next."),
        .init(id: "gloop", name: "Gloop", trait: "Energetic", motion: .energy,
              desc: "Big wobbly enthusiasm — a little chaotic, fully sincere."),
    ]
}

// MARK: - Surface style

enum BlobStyle: String, CaseIterable, Identifiable {
    case aurora, glossy, clay, fuse
    var id: String { rawValue }

    /// Display name used by the prototype's chips.
    var name: String {
        switch self {
        case .aurora: return "Aurora"
        case .glossy: return "Glossy"
        case .clay:   return "Furry"
        case .fuse:   return "Grain"
        }
    }
    var desc: String {
        switch self {
        case .aurora: return "drifting gradient mist"
        case .glossy: return "liquid glass jelly"
        case .clay:   return "fuzzy soft fur"
        case .fuse:   return "grainy matte sphere"
        }
    }
}

// MARK: - Eyes

enum EyeStyle: String, CaseIterable, Identifiable {
    case cartoon, happy, cool, spark
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

// MARK: - Legs

enum LegStyle: String, CaseIterable, Identifiable {
    case none, stubs, wiggly, wheels
    var id: String { rawValue }
    var name: String {
        switch self {
        case .none:   return "Floating"
        case .stubs:  return "Stubs"
        case .wiggly: return "Wiggly"
        case .wheels: return "Skate"
        }
    }
}

// MARK: - Voice / tone

struct CompanionTone: Identifiable, Hashable {
    let id: String
    let name: String
    let desc: String

    static let all: [CompanionTone] = [
        .init(id: "gentle", name: "Gentle", desc: "“Take it slow today — you’ve earned a little ease.”"),
        .init(id: "cheerful", name: "Cheerful", desc: "“Look at you go! Your energy is contagious today ✦”"),
        .init(id: "wise", name: "Wise", desc: "“Rest is not idleness. Your body is restoring itself.”"),
        .init(id: "playful", name: "Playful", desc: "“Psst… your couch misses you less than your trainers do.”"),
        .init(id: "gossip", name: "Gossip", desc: "“Okay don’t tell anyone… but your HRV is THRIVING today 👀”"),
    ]
}

// MARK: - Worlds / backgrounds

struct CompanionWorld: Identifiable, Hashable {
    let id: Int
    let name: String
    let locked: Bool

    static let all: [CompanionWorld] = [
        .init(id: 0, name: "Mystic Forest", locked: false),
        .init(id: 1, name: "Neon Cyberpunk", locked: false),
        .init(id: 2, name: "Sakura Bloom", locked: false),
        .init(id: 3, name: "Cosmic Starry", locked: false),
        .init(id: 4, name: "Tidepool", locked: true),
        .init(id: 5, name: "Ember Night", locked: true),
    ]
}
