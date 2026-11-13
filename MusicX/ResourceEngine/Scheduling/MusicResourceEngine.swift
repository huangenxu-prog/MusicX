import Foundation

private final class ResourceProviderPerformance {
    static let shared = ResourceProviderPerformance()

    private struct Attempt: Codable {
        let succeeded: Bool
        let durationMilliseconds: Int
        let timestamp: Date
    }

    private let lock = NSLock()
    private let storageKey = "musicx.resource-provider-performance.v1"
    private var attempts: [String: [Attempt]]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: [Attempt]].self, from: data) {
            attempts = saved
        } else {
            attempts = [:]
        }
    }

    func record(identifier: String, succeeded: Bool, duration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        var recent = (attempts[identifier] ?? []).filter { $0.timestamp > cutoff }
        recent.append(Attempt(
            succeeded: succeeded,
            durationMilliseconds: max(0, Int(duration * 1_000)),
            timestamp: Date()
        ))
        attempts[identifier] = Array(recent.suffix(30))
        if let data = try? JSONEncoder().encode(attempts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func score(identifier: String, baseline: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let recent = (attempts[identifier] ?? []).filter { $0.timestamp > cutoff }
        guard !recent.isEmpty else { return baseline }

        let successRate = Double(recent.filter(\.succeeded).count) / Double(recent.count)
        let averageLatency = Double(recent.map(\.durationMilliseconds).reduce(0, +)) / Double(recent.count)
        return Int(successRate * 100 - min(averageLatency / 150, 30) + Double(baseline))
    }
}

/// The middle layer between the player-facing resolver and external supplier libraries.
/// It intentionally does not own playback URL caching; MusicCache remains in the
/// existing LXMusicURLResolver compatibility boundary.
struct MusicResourceEngine {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> URL {
        let providers: [(any MusicResourceProvider, Int)] = [
            (MusicXLegacySupplierLibrary(session: session), 30),
            (KumoneKugouAudioSourceProvider(session: session), 20),
            (KumoneKuwoAudioSourceProvider(session: session), 10)
        ]

        let ordered = providers.sorted {
            let lhs = ResourceProviderPerformance.shared.score(
                identifier: $0.0.identifier,
                baseline: $0.1
            )
            let rhs = ResourceProviderPerformance.shared.score(
                identifier: $1.0.identifier,
                baseline: $1.1
            )
            return lhs == rhs ? $0.1 > $1.1 : lhs > rhs
        }

        var failures: [String] = []
        for (provider, _) in ordered {
            try Task.checkCancellation()
            let startedAt = Date()
            do {
                guard let resource = try await provider.resolve(song: song, quality: quality) else {
                    let elapsed = Date().timeIntervalSince(startedAt)
                    ResourceProviderPerformance.shared.record(
                        identifier: provider.identifier,
                        succeeded: false,
                        duration: elapsed
                    )
                    MusicSourceDiagnostics.shared.record(
                        event: "resource-provider",
                        source: song.source.rawValue,
                        provider: provider.identifier,
                        duration: elapsed,
                        result: "no_match"
                    )
                    failures.append("\(provider.displayName)：没有匹配资源")
                    continue
                }

                try Task.checkCancellation()
                guard Self.isValidStreamURL(resource.url) else {
                    throw MusicSourceError.invalidResponse("供应商返回了无效播放地址")
                }

                let elapsed = Date().timeIntervalSince(startedAt)
                ResourceProviderPerformance.shared.record(
                    identifier: provider.identifier,
                    succeeded: true,
                    duration: elapsed
                )
                MusicSourceDiagnostics.shared.record(
                    event: "resource-provider",
                    source: song.source.rawValue,
                    provider: resource.providerID,
                    duration: elapsed,
                    result: "url_returned"
                )
                return resource.url
            } catch {
                if Task.isCancelled || error is CancellationError
                    || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }

                let elapsed = Date().timeIntervalSince(startedAt)
                ResourceProviderPerformance.shared.record(
                    identifier: provider.identifier,
                    succeeded: false,
                    duration: elapsed
                )
                MusicSourceDiagnostics.shared.record(
                    event: "resource-provider",
                    source: song.source.rawValue,
                    provider: provider.identifier,
                    duration: elapsed,
                    result: "failed",
                    detail: error.localizedDescription
                )
                failures.append("\(provider.displayName)：\(error.localizedDescription)")
            }
        }

        throw MusicSourceError.noPlayableURL(
            source: song.source,
            details: failures.isEmpty
                ? "所有供应商均未返回可用播放地址"
                : failures.joined(separator: "；")
        )
    }

    private static func isValidStreamURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              components.user == nil,
              components.password == nil,
              !url.absoluteString.contains(where: { $0.isWhitespace }) else {
            return false
        }
        return true
    }
}
