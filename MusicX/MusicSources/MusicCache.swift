import CryptoKit
import Foundation

/// Small disk-backed cache for reusable MusicX API results.
/// Entries are isolated by an actor, expire independently, and are pruned by size.
actor MusicCache {
    static let shared = MusicCache()

    private struct Entry: Codable {
        let expiresAt: Date
        let payload: Data
    }

    private let directory: URL
    private let maximumBytes: Int = 120 * 1024 * 1024

    private init() {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = root.appendingPathComponent("MusicXCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func value<Value: Decodable>(for key: String, as type: Value.Type = Value.self) -> Value? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        guard entry.expiresAt > Date() else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return try? JSONDecoder().decode(Value.self, from: entry.payload)
    }

    func insert<Value: Encodable>(_ value: Value, for key: String, ttl: TimeInterval) {
        guard ttl > 0, let payload = try? JSONEncoder().encode(value) else { return }
        let entry = Entry(expiresAt: Date().addingTimeInterval(ttl), payload: payload)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        let url = fileURL(for: key)
        do {
            try data.write(to: url, options: .atomic)
            pruneIfNeeded()
        } catch {
            // Cache failures must never affect search or playback.
        }
    }

    func removeValue(for key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    private func pruneIfNeeded() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var total = 0
        var candidates: [(url: URL, date: Date, size: Int)] = []
        for url in files {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = values?.fileSize ?? 0
            if let data = try? Data(contentsOf: url),
               let entry = try? JSONDecoder().decode(Entry.self, from: data),
               entry.expiresAt <= Date() {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            total += size
            candidates.append((url, values?.contentModificationDate ?? .distantPast, size))
        }
        guard total > maximumBytes else { return }
        for item in candidates.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: item.url)
            total -= item.size
            if total <= maximumBytes { break }
        }
    }
}
