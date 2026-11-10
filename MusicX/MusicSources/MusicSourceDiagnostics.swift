import Foundation

/// Records source-search and URL-resolution outcomes without exposing full stream URLs,
/// query strings, credentials, or device identifiers.
final class MusicSourceDiagnostics {
    static let shared = MusicSourceDiagnostics()

    private let lock = NSLock()
    private let maximumFileSize = 1_000_000
    private let formatter = ISO8601DateFormatter()

    var fileURL: URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("MusicX-Source-Diagnostics.jsonl")
    }

    private init() {}

    func record(
        event: String,
        source: String,
        provider: String,
        duration: TimeInterval,
        result: String,
        detail: String? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        let url = fileURL
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue >= maximumFileSize {
            try? fileManager.removeItem(at: url)
        }

        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }

        let safeDetail = (detail ?? "")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\r", with: " ")
            .prefix(240)

        let entry: [String: Any] = [
            "time": formatter.string(from: Date()),
            "event": event,
            "source": source,
            "provider": provider,
            "duration_ms": max(0, Int(duration * 1000)),
            "result": result,
            "detail": String(safeDetail)
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
            try handle.close()
        } catch {
            try? handle.close()
        }
    }
}
