import Foundation

struct WidgetEnergySnapshot: Codable, Equatable {
    static let appGroupIdentifier = "group.com.komo4.companion"
    private static let fileName = "komo-widget-energy-snapshot.json"

    var percent: Int
    var word: String
    var rechargedBy: String
    var usedBy: String
    var insightText: String
    var insightSuggestion: String
    var updatedAt: Date

    static let fallback = WidgetEnergySnapshot(
        percent: 72,
        word: "Steady",
        rechargedBy: "resting hr",
        usedBy: "",
        insightText: "your focus usually improves after a short walk.",
        insightSuggestion: "take a 7-minute walk without your phone.",
        updatedAt: .distantPast
    )

    var clampedPercent: Int {
        min(100, max(0, percent))
    }

    var hasPublishedData: Bool {
        updatedAt > .distantPast
    }

    var energyHeadline: String {
        String(format: String(localized: "%@ energy"), word.lowercased())
    }

    var widgetSubtitle: String {
        if !insightText.isEmpty {
            return insightText
        }
        if !insightSuggestion.isEmpty {
            return insightSuggestion
        }
        return hasPublishedData
            ? String(localized: "Komo is ready for your next check-in.")
            : String(localized: "Open Komo to sync your energy and insights.")
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

    private enum CodingKeys: String, CodingKey {
        case percent, word, rechargedBy, usedBy, insightText, insightSuggestion, updatedAt
    }

    init(
        percent: Int,
        word: String,
        rechargedBy: String,
        usedBy: String,
        insightText: String = "",
        insightSuggestion: String = "",
        updatedAt: Date
    ) {
        self.percent = percent
        self.word = word
        self.rechargedBy = rechargedBy
        self.usedBy = usedBy
        self.insightText = insightText
        self.insightSuggestion = insightSuggestion
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        percent = try container.decode(Int.self, forKey: .percent)
        word = try container.decode(String.self, forKey: .word)
        rechargedBy = try container.decode(String.self, forKey: .rechargedBy)
        usedBy = try container.decode(String.self, forKey: .usedBy)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        insightText = try container.decodeIfPresent(String.self, forKey: .insightText) ?? ""
        insightSuggestion = try container.decodeIfPresent(String.self, forKey: .insightSuggestion) ?? ""
    }
}
