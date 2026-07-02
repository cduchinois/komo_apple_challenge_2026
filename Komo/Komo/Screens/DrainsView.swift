//  DrainsView.swift
//  Komo
//
//  Page 6 — Q4 "Drains". The blob is tired (half-lidded, more saturated,
//  komoTired). Unlimited multi-select; "not sure yet" is exclusive. Next → signals.

import SwiftUI

struct DrainsView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    private let options = ["poor sleep", "screen time", "meetings", "sitting too long",
                           "intense work", "social plans", "commute / travel", "not sure yet"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 4) { app.go(.restores) }
                .padding(.bottom, 14)

            QuestionTitle(text: "what usually\ndrains you?", subtitle: "select all that apply")

            KomoMascotView(size: KomoMascotView.standardSize,
                           namespace: namespace,
                           geometryID: "companion",
                           accessibilityLabelText: app.companionDisplayName)
                .frame(maxHeight: .infinity)

            FlowChips(options: options, selected: app.drains) { label in
                app.toggleDrain(label)
            }

            PrimaryButton(title: "next", enabled: !app.drains.isEmpty) {
                // Contextual branch: only ask for calendar access if the user
                // picked a drain where it would actually help.
                if app.needsCalendarPermission {
                    app.go(.calendarPermission)
                } else {
                    app.go(.loading)
                }
            }
            .padding(.top, 16)
        }
        .padding(.top, Theme.Space.screenTop)
        .padding(.bottom, 32)
        .safeAreaPadding(.horizontal, 40)
        .animation(.spring(response: 0.25), value: app.drains)
    }
        
}

/// A centered wrapping row of multi-select pills.
struct FlowChips: View {
    var options: [String]
    var selected: [String]
    var onTap: (String) -> Void
    let colorPool: [Color] = [.green, .blue, .purple, .orange, .pink, .teal, .indigo]

    var body: some View {
        FlowLayout(spacing: 10, alignment: .center) {
            ForEach(Array(zip(options.indices, options)), id: \.1) { index, opt in
                let isSelected = selected.contains(opt)
                let baseColor = colorPool[index % colorPool.count]
                
                PillChip(label: opt, selected: isSelected) { onTap(opt) }
                    // 1. Pop the opacity up significantly when selected
                    .background(
                        baseColor.opacity(isSelected ? 0.8 : 0.2),
                        in: Capsule()
                    )
                    // 2. Switch to heavy frosted '.regular' glass when selected
                    //    so it catches the light and looks distinctly "pressed in"
                    .glassEffect(.clear.interactive())
                    // 3. Optional visual pop: Scale selected items slightly
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    // Smooths out the transition when a user taps a chip
                    .animation(.snappy(duration: 0.2), value: isSelected)
            }
        }
    }
}
