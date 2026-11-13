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

/// Per-provider circuit breaker. A no-match response is healthy: it means the
/// supplier answered successfully but did not have this track.
private final class ResourceProviderCircuitBreaker {
    static let shared = ResourceProviderCircuitBreaker()

    private struct State {
        var consecutiveFailures = 0
        var openedUntil: Date?
        var halfOpenProbeInFlight = false
    }

    private let lock = NSLock()
    private var states: [String: State] = [:]
    private let failureThreshold = 3
    private let cooldown: TimeInterval = 60

    private init() {}

    func shouldAttempt(_ identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard var state = states[identifier] else { return true }
        guard let openedUntil = state.openedUntil else { return true }
        guard Date() >= openedUntil else { return false }
        guard !state.halfOpenProbeInFlight else { return false }

        state.halfOpenProbeInFlight = true
        states[identifier] = state
        return true
    }

    func recordHealthy(_ identifier: String) {
        lock.lock()
        states[identifier] = State()
        lock.unlock()
    }

    func recordFailure(_ identifier: String) {
        lock.lock()
        defer { lock.unlock() }

        var state = states[identifier] ?? State()
        if state.openedUntil != nil && state.halfOpenProbeInFlight {
            state.consecutiveFailures = failureThreshold
        } else {
            state.consecutiveFailures += 1
        }
        state.halfOpenProbeInFlight = false
        if state.consecutiveFailures >= failureThreshold {
            state.openedUntil = Date().addingTimeInterval(cooldown)
        }
        states[identifier] = state
    }

    /// A single song's URL may be expired, region-blocked, or unavailable even
    /// while the provider itself is healthy. Release a half-open probe slot
    /// without counting that resource-specific failure against the provider.
    func recordResourceFailure(_ identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var state = states[identifier], state.halfOpenProbeInFlight else { return }
        state.halfOpenProbeInFlight = false
        states[identifier] = state
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
        let resource = try await resolveResource(song: song, quality: quality)
        return resource.url
    }

    /// Resolve a resource while excluding providers whose last returned stream
    /// was rejected by AVPlayer for this same track.
    func resolveResource(
        song: MusicSong,
        quality: MusicQuality,
        excludingProviderIDs: Set<String> = []
    ) async throws -> ResolvedMusicResource {
        // Temporary source policy: NetEase only.
        // 1) Official NetEase playback URL (free/original resource).
        // 2) Kumone pyncmd for tracks whose official URL is unavailable (e.g. VIP).
        // 3) Strictly matched Kugou, then Kuwo fallback.
        // All other catalogs and the legacy cross-platform resolver are disabled.
        guard song.source == .netease else {
            throw MusicSourceError.unsupportedSource(song.source)
        }

        let providers: [(provider: any MusicResourceProvider, tier: Int, baseline: Int)] = [
            (NetEaseNativeAudioProvider(session: session), 0, 1_000),
            (KumonePyncmdAudioSourceProvider(), 1, 100),
            (KumoneKugouAudioSourceProvider(session: session), 2, 80),
            (KumoneKuwoAudioSourceProvider(), 3, 70)
        ]

        var failures: [String] = []
        for entry in providers {
            let provider = entry.provider
            try Task.checkCancellation()

            if excludingProviderIDs.contains(provider.identifier) {
                MusicSourceDiagnostics.shared.record(
                    event: "resource-provider",
                    source: song.source.rawValue,
                    provider: provider.identifier,
                    duration: 0,
                    result: "skipped_after_playback_failure",
                    detail: "AVPlayer rejected the previous stream from this provider"
                )
                failures.append("\(provider.displayName)：上一次播放失败，已跳过")
                continue
            }

            guard ResourceProviderCircuitBreaker.shared.shouldAttempt(provider.identifier) else {
                MusicSourceDiagnostics.shared.record(
                    event: "resource-provider",
                    source: song.source.rawValue,
                    provider: provider.identifier,
                    duration: 0,
                    result: "circuit_open",
                    detail: "供应商连续失败，冷却中"
                )
                failures.append("\(provider.displayName)：暂时冷却")
                continue
            }

            let startedAt = Date()
            do {
                guard let resource = try await provider.resolve(song: song, quality: quality) else {
                    let elapsed = Date().timeIntervalSince(startedAt)
                    ResourceProviderCircuitBreaker.shared.recordHealthy(provider.identifier)
                    MusicSourceDiagnostics.shared.record(
                        event: "resource-provider",
                        source: song.source.rawValue,
                        provider: provider.identifier,
                        duration: elapsed,
                        result: "no_match"
                    )
                    failures.append("\(provider.displayName)：没有可用资源")
                    continue
                }

                try Task.checkCancellation()
                guard Self.isValidStreamURL(resource.url) else {
                    throw MusicSourceError.invalidResponse("供应商返回了无效播放地址")
                }

                let elapsed = Date().timeIntervalSince(startedAt)
                ResourceProviderCircuitBreaker.shared.recordHealthy(provider.identifier)
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
                    result: "url_returned_direct"
                )
                return resource
            } catch {
                if Task.isCancelled || error is CancellationError
                    || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }

                let elapsed = Date().timeIntervalSince(startedAt)
                let providerLevelFailure = Self.shouldTripCircuitBreaker(for: error)
                if providerLevelFailure {
                    ResourceProviderCircuitBreaker.shared.recordFailure(provider.identifier)
                    ResourceProviderPerformance.shared.record(
                        identifier: provider.identifier,
                        succeeded: false,
                        duration: elapsed
                    )
                } else {
                    ResourceProviderCircuitBreaker.shared.recordResourceFailure(provider.identifier)
                }
                MusicSourceDiagnostics.shared.record(
                    event: "resource-provider",
                    source: song.source.rawValue,
                    provider: provider.identifier,
                    duration: elapsed,
                    result: providerLevelFailure ? "failed" : "resource_unavailable",
                    detail: error.localizedDescription
                )
                failures.append("\(provider.displayName)：\(error.localizedDescription)")
            }
        }

        throw MusicSourceError.noPlayableURL(
            source: song.source,
            details: failures.isEmpty
                ? "网易云原始地址及 pyncmd、酷狗、酷我均未返回可用地址"
                : failures.joined(separator: "；")
        )
    }

    /// HTTP 4xx responses from a stream URL are usually song-, region-, or
    /// entitlement-specific. They should trigger fallback for this track, but
    /// must not disable the whole provider for unrelated tracks.
    private static func shouldTripCircuitBreaker(for error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return false
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .networkConnectionLost, .notConnectedToInternet, .secureConnectionFailed,
                 .cannotLoadFromNetwork:
                return true
            default:
                break
            }
        }

        let message = error.localizedDescription.lowercased()
        if let marker = message.range(of: "http ") {
            let statusText = message[marker.upperBound...].prefix(3)
            if let status = Int(statusText), (400..<500).contains(status), status != 429 {
                return false
            }
        }
        if message.contains("播放地址返回了 html/json")
            || message.contains("播放地址返回了非音频内容")
            || message.contains("播放流响应为空") {
            return false
        }
        return true
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
