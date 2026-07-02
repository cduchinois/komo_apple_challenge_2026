import Foundation
import SwiftData

@Model
final class AppStateRecord {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date

    init(key: String = "primary", payload: Data, updatedAt: Date = Date()) {
        self.key = key
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class EnergyCheckInRecord {
    var id: UUID
    var createdAt: Date
    var percent: Int
    var word: String
    var rechargedBy: String
    var usedBy: String
    var headlineInsight: String
    var energyType: String?
    var energyNow: String?
    var restoresPayload: Data
    var drainsPayload: Data

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        percent: Int,
        word: String,
        rechargedBy: String,
        usedBy: String,
        headlineInsight: String,
        energyType: String?,
        energyNow: String?,
        restores: [String],
        drains: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.percent = percent
        self.word = word
        self.rechargedBy = rechargedBy
        self.usedBy = usedBy
        self.headlineInsight = headlineInsight
        self.energyType = energyType
        self.energyNow = energyNow
        self.restoresPayload = (try? JSONEncoder().encode(restores)) ?? Data()
        self.drainsPayload = (try? JSONEncoder().encode(drains)) ?? Data()
    }
}

@MainActor
enum KomoSwiftDataStore {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: AppStateRecord.self, EnergyCheckInRecord.self)
        } catch {
            fatalError("Could not create SwiftData container: \(error.localizedDescription)")
        }
    }()

    static var context: ModelContext {
        shared.mainContext
    }
}
