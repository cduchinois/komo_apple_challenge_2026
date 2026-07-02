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
    static let shared: ModelContainer = makeContainer()

    static var context: ModelContext {
        shared.mainContext
    }

    private static let schema = Schema([AppStateRecord.self, EnergyCheckInRecord.self])

    /// Builds the persistent container. The store is pinned to the app's OWN
    /// sandbox Application Support directory (never the App Group container),
    /// and that directory is created first. This avoids the CoreData error 512
    /// "Sandbox access file-write-create denied" that occurs when the store URL
    /// points at an App Group Application Support folder that doesn't exist.
    /// If the on-disk store still can't be opened, we fall back to an in-memory
    /// container so the app keeps running instead of crashing.
    private static func makeContainer() -> ModelContainer {
        if let diskContainer = try? diskBackedContainer() {
            return diskContainer
        }

        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            print("⚠️ KomoSwiftDataStore: falling back to in-memory store.")
            return try ModelContainer(for: schema, configurations: [memoryConfig])
        } catch {
            fatalError("Could not create SwiftData container: \(error.localizedDescription)")
        }
    }

    private static func diskBackedContainer() throws -> ModelContainer {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        // Ensure the directory exists (it is not always created on first launch).
        if !fileManager.fileExists(atPath: appSupport.path) {
            try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }

        let storeURL = appSupport.appendingPathComponent("Komo.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
