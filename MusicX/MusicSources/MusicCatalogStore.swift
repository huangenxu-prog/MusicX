import Foundation
import CryptoKit

/// Durable snapshots for discovery content. Expiration schedules refreshes;
/// it never invalidates the last known-good catalog data.
actor MusicCatalogStore {
    static let shared = MusicCatalogStore()

    struct Snapshot<Value: Codable>: Codable {
        let value: Value
        let updatedAt: Date
        let refreshAfter: Date

        var needsRefresh: Bool { Date() >= refreshAfter }
    }

    private struct StoredEnvelope: Codable {
        let updatedAt: Date
        let refreshAfter: Date
        let payload: Data
    }

    private let directory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("MusicXCatalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
    }

    func snapshot<Value: Codable>(for key: String, as type: Value.Type = Value.self) -> Snapshot<Value>? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let envelope = try? JSONDecoder().decode(StoredEnvelope.self, from: data),
              let value = try? JSONDecoder().decode(Value.self, from: envelope.payload) else {
            return nil
        }
        return Snapshot(value: value, updatedAt: envelope.updatedAt, refreshAfter: envelope.refreshAfter)
    }

    func save<Value: Codable>(_ value: Value, for key: String, refreshAfter interval: TimeInterval) {
        guard interval > 0, let payload = try? JSONEncoder().encode(value) else { return }
        let envelope = StoredEnvelope(
            updatedAt: Date(),
            refreshAfter: Date().addingTimeInterval(interval),
            payload: payload
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            // Snapshot persistence must not interrupt discovery or playback.
        }
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("snapshot")
    }
}
