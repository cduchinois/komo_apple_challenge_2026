//
//  KomoWidgetLiveActivity.swift
//  KomoWidget
//
//  Created by Sacha Morin on 01/07/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct KomoWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct KomoWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KomoWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension KomoWidgetAttributes {
    fileprivate static var preview: KomoWidgetAttributes {
        KomoWidgetAttributes(name: "World")
    }
}

extension KomoWidgetAttributes.ContentState {
    fileprivate static var smiley: KomoWidgetAttributes.ContentState {
        KomoWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: KomoWidgetAttributes.ContentState {
         KomoWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: KomoWidgetAttributes.preview) {
   KomoWidgetLiveActivity()
} contentStates: {
    KomoWidgetAttributes.ContentState.smiley
    KomoWidgetAttributes.ContentState.starEyes
}
