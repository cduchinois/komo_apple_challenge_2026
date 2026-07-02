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
        KomoEnergyEntry(date: Date(), snapshot: .fallback)
    }

    func getSnapshot(in context: Context, completion: @escaping (KomoEnergyEntry) -> Void) {
        completion(KomoEnergyEntry(date: Date(), snapshot: WidgetEnergySnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KomoEnergyEntry>) -> Void) {
        let entry = KomoEnergyEntry(date: Date(), snapshot: WidgetEnergySnapshot.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct KomoEnergyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KomoEnergyEntry

    private var progress: Double {
        Double(entry.snapshot.clampedPercent) / 100.0
    }

    private var energyColor: Color {
        switch entry.snapshot.clampedPercent {
        case 80...: return Color(red: 0.31, green: 0.64, blue: 0.37)
        case 60..<80: return Color(red: 0.58, green: 0.84, blue: 0.43)
        case 40..<60: return Color(red: 0.91, green: 0.73, blue: 0.24)
        case 20..<40: return Color(red: 0.90, green: 0.54, blue: 0.24)
        default: return Color(red: 0.85, green: 0.32, blue: 0.24)
        }
    }

    var body: some View {
        switch family {
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            logoRow

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot.word)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(entry.snapshot.hasPublishedData ? "\(entry.snapshot.clampedPercent)% energy" : "Sync energy")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            progressBar
        }
        .komoWidgetBackground()
    }

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            logoImage
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: energyColor.opacity(0.24), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 10) {
                Text("KOMO")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.snapshot.word)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if entry.snapshot.hasPublishedData {
                        Text("\(entry.snapshot.clampedPercent)%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(energyColor)
                            .lineLimit(1)
                    }
                }

                progressBar

                Text(entry.snapshot.hasPublishedData ? "Charged by \(entry.snapshot.rechargedBy)" : "Launch Komo to sync your energy")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .komoWidgetBackground()
    }

    private var logoRow: some View {
        HStack(spacing: 8) {
            logoImage
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text("KOMO")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var logoImage: some View {
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
        ["Blob_App_Icon.png 1-2", "Blob_App_Icon.png 1-2.png", "AppIcon"]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
    #endif

    private var fallbackLogo: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(energyColor.gradient)
            .overlay {
                Text("K")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.08))
                Capsule()
                    .fill(energyColor.gradient)
                    .frame(width: max(8, proxy.size.width * progress))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Energy")
        .accessibilityValue("\(entry.snapshot.clampedPercent) percent")
    }
}

private extension View {
    func komoWidgetBackground() -> some View {
        self
            .padding(16)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.98, blue: 0.96), Color(red: 0.91, green: 0.96, blue: 0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }
}

struct KomoWidget: Widget {
    let kind = "KomoEnergyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KomoEnergyProvider()) { entry in
            KomoEnergyWidgetView(entry: entry)
        }
        .configurationDisplayName("KOMO Energy")
        .description("Shows your current KOMO energy score.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    KomoWidget()
} timeline: {
    KomoEnergyEntry(date: .now, snapshot: .fallback)
}

#Preview(as: .systemMedium) {
    KomoWidget()
} timeline: {
    KomoEnergyEntry(date: .now, snapshot: .fallback)
}
