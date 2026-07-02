import Foundation

struct WidgetEnergySnapshot: Codable, Equatable {
    static let appGroupIdentifier = "group.com.komo4.companion"
    private static let fileName = "komo-widget-energy-snapshot.json"

    var percent: Int
    var word: String
    var rechargedBy: String
    var usedBy: String
    var updatedAt: Date

    static let fallback = WidgetEnergySnapshot(
        percent: 0,
        word: "Open Komo",
        rechargedBy: "sync energy",
        usedBy: "",
        updatedAt: .distantPast
    )

    var clampedPercent: Int {
        min(100, max(0, percent))
    }

    var hasPublishedData: Bool {
        updatedAt > .distantPast
    }

    static func load() -> WidgetEnergySnapshot {
        guard let fileURL else {
            print("WidgetEnergySnapshot: App Group container unavailable for \(appGroupIdentifier)")
            return fallback
        }
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(WidgetEnergySnapshot.self, from: data) else {
            return fallback
        }
        return snapshot
    }

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
