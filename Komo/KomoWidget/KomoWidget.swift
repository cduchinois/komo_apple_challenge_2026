import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

struct KomoEnergyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetEnergySnapshot
}

struct KomoEnergyProvider: TimelineProvider {
    func placeholder(in context: Context) -> KomoEnergyEntry {
        KomoEnergyEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (KomoEnergyEntry) -> Void) {
        let snapshot = context.isPreview ? .preview : WidgetEnergySnapshot.load()
        completion(KomoEnergyEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KomoEnergyEntry>) -> Void) {
        let entry = KomoEnergyEntry(date: Date(), snapshot: WidgetEnergySnapshot.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date)
            ?? entry.date.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct KomoEnergyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KomoEnergyEntry

    private var snapshot: WidgetEnergySnapshot { entry.snapshot }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(family == .systemMedium ? 16 : 12)
        .containerBackground(for: .widget) {
            KomoWidgetPalette.backgroundGradient
        }
    }

    // MARK: - Medium

    private var mediumLayout: some View {
        HStack(alignment: .center, spacing: 14) {
            mascotBadge(size: 88)

            VStack(alignment: .leading, spacing: 8) {
                brandRow

                Text(snapshot.hasPublishedData ? snapshot.energyHeadline : String(localized: "open komo"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(snapshot.widgetSubtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            brandRow

            HStack(alignment: .center, spacing: 10) {
                mascotBadge(size: 50)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.hasPublishedData ? snapshot.energyHeadline : String(localized: "open komo"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if snapshot.hasPublishedData {
                        Text("\(snapshot.clampedPercent)%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(KomoWidgetPalette.leaf)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(snapshot.widgetSubtitle)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: - Shared pieces

    private var brandRow: some View {
        HStack(spacing: 6) {
            appLogoImage
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text("Komo")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    private func mascotBadge(size: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            appLogoImage
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }

            if snapshot.hasPublishedData {
                Text("\(snapshot.clampedPercent)%")
                    .font(.system(size: size > 60 ? 12 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(.black.opacity(0.42))
                    }
                    .offset(y: 5)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var appLogoImage: some View {
        #if canImport(UIKit)
        if let image = Self.appLogoImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallbackLogo
        }
        #else
        fallbackLogo
        #endif
    }

    #if canImport(UIKit)
    private static var appLogoImage: UIImage? {
        ["KomoAppLogo", "Blob_App_Icon.png 1-2", "Blob_App_Icon.png 1-2.png", "AppIcon"]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
    #endif

    private var fallbackLogo: some View {
        Circle()
            .fill(KomoWidgetPalette.leaf.gradient)
            .overlay {
                Text("K")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
    }
}

private enum KomoWidgetPalette {
    static let forestDark = Color(red: 0.12, green: 0.18, blue: 0.11)
    static let forestMid = Color(red: 0.18, green: 0.28, blue: 0.16)
    static let leaf = Color(red: 0.58, green: 0.84, blue: 0.43)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                forestDark,
                forestMid,
                leaf.opacity(0.55)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct KomoWidget: Widget {
    let kind = "KomoEnergyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KomoEnergyProvider()) { entry in
            KomoEnergyWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "KOMO"))
        .description(String(localized: "Your energy and today's insight, synced from Komo."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private extension WidgetEnergySnapshot {
    static let preview = WidgetEnergySnapshot(
        percent: 72,
        word: "Steady",
        rechargedBy: "resting hr",
        usedBy: "",
        insightText: "your focus usually improves after a short walk.",
        insightSuggestion: "take a 7-minute walk without your phone.",
        updatedAt: .now
    )
}

#Preview(as: .systemSmall) {
    KomoWidget()
} timeline: {
    KomoEnergyEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    KomoWidget()
} timeline: {
    KomoEnergyEntry(date: .now, snapshot: .preview)
}
