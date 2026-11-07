import Foundation
import os

nonisolated struct CatStats: Codable, Equatable, Sendable {
    var pets = 0
    var meals = 0
    var drinks = 0
    var playSessions = 0
    var naps = 0
    var adoptedOn = Date()
}

/// Everything about Whiskumi that must survive a relaunch (preferences live in `AppSettings`).
nonisolated struct CatSaveData: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = CatSaveData.currentVersion
    var needs = CatNeeds()
    var personality = CatPersonality.newborn()
    var stats = CatStats()
    var savedAt = Date()
}

/// Reads and writes `CatSaveData` as JSON in Application Support. Writes are atomic,
/// and a corrupt file is moved aside instead of silently discarding the cat.
nonisolated final class PersistenceManager: Sendable {
    let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Whiskumi", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Whiskumi", isDirectory: true)
        fileURL = base.appendingPathComponent("Whiskumi.json")
    }

    func load() -> CatSaveData? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CatSaveData.self, from: data)
        } catch {
            Log.persistence.error("Could not read save file: \(error.localizedDescription, privacy: .public)")
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return nil
        }
    }

    func save(_ save: CatSaveData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(save)
        try data.write(to: fileURL, options: .atomic)
    }
}
