//import WidgetKit
//import SwiftUI
//
//@main
//struct DotWidget: Widget {
//    var body: some WidgetConfiguration {
//        ActivityConfiguration(for: DotAttributes.self) { context in
//            Text("Activity Active") // Lock screen fallback
//        } dynamicIsland: { context in
//            DynamicIsland {
//                // Expanded view (blank for now since you only want the initial view)
//                DynamicIslandExpandedRegion(.center) {
//                    Text("Expanded View")
//                }
//            } compactLeading: {
//                // INITIAL STATE: This puts a native green dot on the left flank of the Island
//                Circle()
//                    .fill(.green)
//                    .frame(width: 10, height: 10)
//                    .padding(.leading, 4) // Slight nudge so it's not hugging the edge
//            } compactTrailing: {
//                // Leave right side empty
//                Spacer()
//            } minimal: {
//                // This handles the view if another app takes priority
//                Circle()
//                    .fill(.green)
//                    .frame(width: 10, height: 10)
//            }
//        }
//    }
//}
