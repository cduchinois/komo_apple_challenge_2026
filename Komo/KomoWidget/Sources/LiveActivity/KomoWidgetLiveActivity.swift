import ActivityKit
import WidgetKit
import SwiftUI

struct KomoWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KomoLiveActivityAttributes.self) { context in
            // Lock Screen (Banner)
            HStack {
                // Left
                VStack(alignment: .leading) {
                    Text("\(context.state.emoji) \(context.state.stressLevel.rawValue)")
                        .font(.headline)
                        .foregroundColor(color(for: context.state.stressLevel))
                }
                
                Spacer()
                
                // Center
                Text(context.state.message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                
                Spacer()
                
                // Right
                VStack(alignment: .trailing) {
                    Text("\(context.state.currentHR) BPM")
                        .font(.subheadline)
                        .bold()
                    ProgressView(value: context.state.progress)
                        .tint(color(for: context.state.stressLevel))
                        .frame(width: 50)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.emoji)
                        .font(.system(size: 32))
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text(context.state.message)
                            .font(.caption)
                        ProgressView(value: context.state.progress)
                            .tint(color(for: context.state.stressLevel))
                            .frame(width: 100)
                    }
                    .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Komo is monitoring your health")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            } compactLeading: {
                // Compact (collapsed bar) - Leading
                Text(context.state.emoji)
            } compactTrailing: {
                // Compact (collapsed bar) - Trailing
                Text("\(context.state.currentHR) BPM")
                    .font(.caption2)
                    .foregroundColor(color(for: context.state.stressLevel))
            } minimal: {
                Text(context.state.emoji)
            }
        }
    }
    
    private func color(for stressLevel: ActivityStressLevel) -> Color {
        switch stressLevel {
        case .calm:
            return .blue
        case .moderate:
            return .orange
        case .high:
            return .red
        case .analyzing:
            return .purple
        }
    }
}
