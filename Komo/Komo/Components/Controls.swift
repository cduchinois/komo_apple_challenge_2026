//  Controls.swift
//  Komo
//
//  Small shared controls used across the onboarding and main screens: glass
//  option rows, multi-select pills, the primary CTA, and the onboarding header.

import SwiftUI

/// A full-width glass row with a label and chevron (energy / sleep questions).
/// The whole row — including padding and the trailing chevron — is a single tap
/// target that both selects and advances. The chevron is decorative.
struct OptionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var label: String
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Theme.Font.label(17))
                    .foregroundStyle(.white)
                    // 1. This parameter forces the text block to occupy 100% width and center perfectly
                    .frame(maxWidth: .infinity, alignment: .center)
                    // 2. This places the chevron on the far right edge without touching the text layout
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(selected ? 0.9 : 0.5))
                    }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            // Full-bounds hit target — the Spacer + padding must register taps.
            .contentShape(Rectangle())
            
            .scaleEffect(selected ? 1.0 : 0.99)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: selected)
        }
//        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint("Selects \(label)")
        .glassEffect(.clear.interactive())
    }
}

/// A multi-select pill (drains / restores), max-2 selection handled by AppState.
struct PillChip: View {
    var label: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Font.label(15))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                // Full padded-pill hit target so every tap on the chip registers,
                // regardless of where inside the padding it lands.
                .contentShape(Rectangle())
                .komoGlassButton(
                    cornerRadius: Theme.Radius.chip,
                    tint: selected ? Color.white.opacity(0.22) : nil,
                    strokeOpacity: selected ? 0.92 : 0.24)
                .scaleEffect(selected ? 1.0 : 0.99)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The light primary CTA used to advance the flow. Dim + disabled until ready.
struct PrimaryButton: View {
    var title: String
    var enabled: Bool = true
    var filledGreen: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(Theme.Font.label(17))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
//                .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .shadow(color: .black.opacity(enabled ? 0.18 : 0), radius: 12, y: 8)
        }
//        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .glassEffect(.clear.interactive())
    }

//    private var background: Color {
//        if filledGreen { return Theme.Palette.primaryGreen }
//        return enabled ? Color.white.opacity(0.96) : Color.white.opacity(0.22)
//    }
//    private var foreground: Color {
//        if filledGreen { return .white }
//        return enabled ? Theme.Palette.ink : .white.opacity(0.6)
//    }
}

/// Back button + progress dots shared by every onboarding question.
struct OnboardingHeader: View {
    var step: Int
    var onBack: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            GlassBackButton(action: onBack)
            StepDots(current: step)
            Spacer()
        }
    }
}

/// A question title styled like the prototype's 25pt white headings.
struct QuestionTitle: View {
    var text: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(Theme.Font.display(25))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 14, y: 2)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.body(14))
                    .foregroundStyle(.white.opacity(0.82))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
