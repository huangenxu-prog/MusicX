import Foundation

private final class MusicSourcePerformance {
    static let shared = MusicSourcePerformance()

    private struct Attempt: Codable {
        let succeeded: Bool
        let durationMilliseconds: Int
        let timestamp: Date
    }

    private let lock = NSLock()
    private let storageKey = "musicx.source-performance.v1"
    private var attempts: [String: [Attempt]]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: [Attempt]].self, from: data) {
            attempts = saved
        } else {
            attempts = [:]
        }
    }

    func record(source: MusicSource, succeeded: Bool, duration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        let key = source.rawValue
        var recent = (attempts[key] ?? []).filter {
            $0.timestamp > Date().addingTimeInterval(-30 * 24 * 60 * 60)
        }
        recent.append(Attempt(
            succeeded: succeeded,
            durationMilliseconds: max(0, Int(duration * 1000)),
            timestamp: Date()
        ))
        attempts[key] = Array(recent.suffix(30))
        if let data = try? JSONEncoder().encode(attempts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func score(for source: MusicSource) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let recent = (attempts[source.rawValue] ?? []).filter {
            $0.timestamp > Date().addingTimeInterval(-30 * 24 * 60 * 60)
        }
        let baseline: Int
        switch source {
        case .qq: baseline = 10
        case .netease: baseline = 8
        case .kuwo: baseline = 6
        case .kugou: baseline = 4
        case .migu: baseline = 2
        case .qishui, .youtubeMusic, .youtube, .spotify: baseline = 0
        }
        guard !recent.isEmpty else { return baseline }
        let successRate = Double(recent.filter(\.succeeded).count) / Double(recent.count)
        let averageLatency = Double(recent.map(\.durationMilliseconds).reduce(0, +)) / Double(recent.count)
        return Int(successRate * 100 - min(averageLatency / 150, 30) + Double(baseline))
    }
}

/// Native Swift implementation of the URL-resolution paths found in the supplied
/// 洛雪音源3.js. Search is intentionally separate: the LX plugin contract receives
/// an already identified song and only resolves its playable URL.
struct LXMusicURLResolver: MusicURLResolving, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(song: MusicSong, quality: MusicQuality = .high) async throws -> URL {
        try await resolve(song: song, quality: quality, useCache: true)
    }

    private func resourceCacheKey(for song: MusicSong, quality: MusicQuality) -> String {
        "playback-resource|\(song.source.rawValue)|\(song.sourceID)|\(quality.rawValue)"
    }

    private func resolve(song: MusicSong, quality: MusicQuality, useCache: Bool) async throws -> URL {
        let cacheKey = resourceCacheKey(for: song, quality: quality)
        if useCache,
           let cached: ResolvedMusicResource = await MusicCache.shared.value(
                for: cacheKey, as: ResolvedMusicResource.self
           ) {
            MusicSourceDiagnostics.shared.record(
                event: "resolve", source: song.source.rawValue,
                provider: cached.providerID, duration: 0, result: "cache_hit"
            )
            return cached.url
        }

        let resource = try await MusicResourceEngine(session: session)
            .resolveResource(song: song, quality: quality)
        await MusicCache.shared.insert(resource, for: cacheKey, ttl: 5 * 60)
        return resource.url
    }

    /// Entry point used only by the MusicX legacy supplier adapter. It bypasses
    /// the public cache boundary and never calls the resource engine recursively.
    func resolveFromLegacyLibrary(song: MusicSong, quality: MusicQuality) async throws -> URL? {
        var nativeFailure: Error?
        do {
            if let nativeURL = try await resolveNative(song: song, quality: quality) {
                return nativeURL
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            nativeFailure = error
        }

        do {
            if let fallbackURL = try await resolveAlternativeSource(song: song, quality: quality) {
                return fallbackURL
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let nativeFailure {
                throw MusicSourceError.invalidResponse(
                    "原生音源失败：\(nativeFailure.localizedDescription)；跨平台回退失败：\(error.localizedDescription)"
                )
            }
            throw error
        }

        if let nativeFailure { throw nativeFailure }
        return nil
    }

    /// QQ native endpoints are now independent resource-engine providers.
    /// This entry point keeps only the cross-platform fallback inside the legacy adapter.
    func resolveCrossPlatformFallback(song: MusicSong, quality: MusicQuality) async throws -> URL? {
        try Task.checkCancellation()
        return try await resolveAlternativeSource(song: song, quality: quality)
    }

    /// Resolve only the source-native ID. IDs are never passed between providers.
    private struct BackendAttempt: Sendable {
        let name: String
        let url: URL?
        let duration: TimeInterval
        let error: String?
    }

    /// Query independent native URL backends concurrently. The first valid
    /// playable URL wins; slow or unavailable mirrors no longer delay playback.
    private func resolveNative(song: MusicSong, quality: MusicQuality) async throws -> URL? {
        let candidates = backends(for: song.source)
        guard !candidates.isEmpty else { return nil }

        let attempts = await withTaskGroup(
            of: BackendAttempt.self,
            returning: (BackendAttempt?, [String]).self
        ) { group in
            for backend in candidates {
                group.addTask {
                    let startedAt = Date()
                    do {
                        guard let url = try await resolveWithRetry(backend, song: song, quality: quality),
                              isPlayableURL(url) else {
                            return BackendAttempt(
                                name: backend.name, url: nil,
                                duration: Date().timeIntervalSince(startedAt), error: nil
                            )
                        }
                        return BackendAttempt(
                            name: backend.name, url: url,
                            duration: Date().timeIntervalSince(startedAt), error: nil
                        )
                    } catch {
                        if Task.isCancelled || error is CancellationError
                            || (error as? URLError)?.code == .cancelled {
                            return BackendAttempt(
                                name: backend.name, url: nil,
                                duration: Date().timeIntervalSince(startedAt), error: "cancelled"
                            )
                        }
                        return BackendAttempt(
                            name: backend.name, url: nil,
                            duration: Date().timeIntervalSince(startedAt),
                            error: error.localizedDescription
                        )
                    }
                }
            }

            var failures: [String] = []
            while let result = await group.next() {
                if result.error == "cancelled" { continue }
                if let url = result.url {
                    group.cancelAll()
                    return (result, failures)
                }
                if let error = result.error {
                    failures.append("\(result.name): \(error)")
                }
            }
            return (nil, failures)
        }

        try Task.checkCancellation()
        if let winner = attempts.0, let url = winner.url {
            MusicSourcePerformance.shared.record(
                source: song.source, succeeded: true, duration: winner.duration
            )
            MusicSourceDiagnostics.shared.record(
                event: "resolve", source: song.source.rawValue,
                provider: winner.name, duration: winner.duration,
                result: "url_returned"
            )
            return url
        }
        if !attempts.1.isEmpty {
            throw MusicSourceError.invalidResponse("原生解析接口异常：" + attempts.1.joined(separator: "；"))
        }
        return nil
    }

    /// Search other platforms after native resolution fails. A normalized title
    /// and artist match is sufficient; duration and album metadata are ignored.
    private func resolveAlternativeSource(song: MusicSong, quality: MusicQuality) async throws -> URL? {
        let service = GDStudioMusicSearchService(session: session)

        // Keep the three general-purpose catalogs on the critical path.
        // Migu's native search can take up to 12 seconds and its GDStudio
        // fallback can add another 12 seconds, so it must not block results
        // already returned by NetEase, QQ, or Kugou.
        async let netease = captureSearch { try await service.search(keyword: song.title, source: .netease, count: 12) }
        async let qq = captureSearch { try await service.search(keyword: song.title, source: .qq, count: 12) }
        async let kugou = captureSearch { try await service.search(keyword: song.title, source: .kugou, count: 12) }
        let primaryResults = await [netease, qq, kugou]
        try Task.checkCancellation()

        var searchFailures = primaryResults.compactMap { $0.1 }
        var candidateFailures: [String] = []
        var seen = Set<String>()

        func makeCandidates(from groups: [[MusicSong]]) -> [(MusicSong, Int)] {
            groups.flatMap { $0 }
                .filter { $0.source != song.source }
                .compactMap { candidate -> (MusicSong, Int)? in
                    let score = matchScore(original: song, candidate: candidate)
                    guard score > 0, seen.insert(candidate.id).inserted else { return nil }
                    return (candidate, score)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return sourceFallbackPriority(lhs.0.source) > sourceFallbackPriority(rhs.0.source)
                }
        }

        func resolveCandidates(_ candidates: [(MusicSong, Int)]) async throws -> URL? {
            for (candidate, score) in candidates {
                try Task.checkCancellation()
                do {
                    if let url = try await resolveNative(song: candidate, quality: quality) {
                        MusicSourceDiagnostics.shared.record(
                            event: "resolve-fallback", source: song.source.rawValue,
                            provider: candidate.source.rawValue, duration: 0,
                            result: "url_returned",
                            detail: "matched=\(candidate.title) · \(candidate.artist) · score=\(score)"
                        )
                        return url
                    }
                    MusicSourceDiagnostics.shared.record(
                        event: "resolve-fallback", source: song.source.rawValue,
                        provider: candidate.source.rawValue, duration: 0,
                        result: "candidate_unavailable",
                        detail: "matched=\(candidate.title) · score=\(score)"
                    )
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        throw CancellationError()
                    }
                    candidateFailures.append("\(candidate.source.displayName): \(error.localizedDescription)")
                    MusicSourceDiagnostics.shared.record(
                        event: "resolve-fallback", source: song.source.rawValue,
                        provider: candidate.source.rawValue, duration: 0,
                        result: "candidate_error",
                        detail: error.localizedDescription
                    )
                }
            }
            return nil
        }

        // Try matching results from NetEase, QQ, and Kugou immediately.
        if let url = try await resolveCandidates(makeCandidates(from: primaryResults.map { $0.0 })) {
            return url
        }

        // Migu remains available as a last-resort source, but its slow native
        // search and subsequent GDStudio fallback no longer delay faster sources.
        try Task.checkCancellation()
        let miguResult = await captureSearch {
            try await service.search(keyword: song.title, source: .migu, count: 12)
        }
        if let failure = miguResult.1 {
            searchFailures.append(failure)
        }
        if let url = try await resolveCandidates(makeCandidates(from: [miguResult.0])) {
            return url
        }

        if !candidateFailures.isEmpty {
            throw MusicSourceError.invalidResponse(
                "跨平台备用解析异常：" + candidateFailures.joined(separator: "；")
            )
        }
        if primaryResults.allSatisfy({ $0.0.isEmpty }) && miguResult.0.isEmpty && !searchFailures.isEmpty {
            throw MusicSourceError.invalidResponse(
                "跨平台搜索接口异常：" + searchFailures.joined(separator: "；")
            )
        }
        return nil
    }

    private func captureSearch(
        _ operation: () async throws -> [MusicSong]
    ) async -> ([MusicSong], String?) {
        do {
            return (try await operation(), nil)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return ([], "cancelled")
            }
            return ([], error.localizedDescription)
        }
    }

    private func matchScore(original: MusicSong, candidate: MusicSong) -> Int {
        AudioSourceTrackMatcher.matches(
            original: original,
            candidateTitle: candidate.title,
            candidateArtist: candidate.artist
        ) ? 100 : 0
    }

    private func sourceFallbackPriority(_ source: MusicSource) -> Int {
        MusicSourcePerformance.shared.score(for: source)
    }

    private func normalizedMatchText(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Continue with the next provider after AVPlayer rejects the previously
    /// resolved stream. The cached resource carries its provider identity, so a
    /// fresh lookup cannot return the same provider's failing URL again.
    func resolveFresh(song: MusicSong, quality: MusicQuality = .high) async throws -> URL {
        let cacheKey = resourceCacheKey(for: song, quality: quality)
        let previousResource: ResolvedMusicResource? = await MusicCache.shared.value(
            for: cacheKey, as: ResolvedMusicResource.self
        )
        await MusicCache.shared.removeValue(for: cacheKey)

        var excludedProviders = Set<String>()
        if let previousResource {
            excludedProviders.insert(previousResource.providerID)
        }
        let resource = try await MusicResourceEngine(session: session).resolveResource(
            song: song,
            quality: quality,
            excludingProviderIDs: excludedProviders
        )
        await MusicCache.shared.insert(resource, for: cacheKey, ttl: 5 * 60)
        MusicSourceDiagnostics.shared.record(
            event: "playback-provider-fallback",
            source: song.source.rawValue,
            provider: resource.providerID,
            duration: 0,
            result: "next_provider_selected",
            detail: previousResource.map { "previous_provider=\($0.providerID)" }
        )
        return resource.url
    }

    /// Retry one time only for transient transport failures. Provider-side errors and
    /// malformed responses immediately fall through to the next backend.
    private func resolveWithRetry(_ backend: Backend, song: MusicSong, quality: MusicQuality) async throws -> URL? {
        do {
            return try await backend.resolve(song, quality)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            guard isTransientNetworkError(error) else { throw error }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            return try await backend.resolve(song, quality)
        }
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost,
                 .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost:
                return true
            default:
                return false
            }
        }

        // Treat rate limiting and server-side failures as transient. Do not retry
        // ordinary 4xx responses, which generally indicate a permanent request issue.
        if case MusicSourceError.invalidResponse(let message) = error,
           message.hasPrefix("HTTP "),
           let status = Int(message.dropFirst(5)) {
            return status == 429 || (500...599).contains(status)
        }
        return false
    }

    private struct Backend: Sendable {
        let name: String
        let resolve: @Sendable (MusicSong, MusicQuality) async throws -> URL?
    }

    private func backends(for source: MusicSource) -> [Backend] {
        switch source {
        case .netease:
            return [
                Backend(name: "netease-chksz", resolve: neteaseChksz),
                Backend(name: "netease-cenguigui", resolve: neteaseCenguigui),
                Backend(name: "netease-gdstudio", resolve: neteaseGDStudio)
            ]
        case .qq:
            return [
                Backend(name: "qq-gdstudio", resolve: qqGDStudio),
                Backend(name: "qq-chksz", resolve: qqChksz)
            ]
        case .kugou, .migu:
            return [Backend(name: "\(source.rawValue)-gdstudio", resolve: gdstudioPlatform)]
        case .kuwo, .qishui, .youtubeMusic, .youtube, .spotify:
            return []
        }
    }

    // MARK: - NetEase

    private func neteaseChksz(_ song: MusicSong, _ quality: MusicQuality) async throws -> URL? {
        let level = quality.neteaseLevel
        let data = try await get(
            "https://api.chksz.top/api/163_music",
            query: [URLQueryItem(name: "id", value: song.sourceID),
                    URLQueryItem(name: "level", value: level)]
        )
        return extractURL(data, paths: [["data", "url"], ["url"]])
    }

    private func neteaseCenguigui(_ song: MusicSong, _ quality: MusicQuality) async throws -> URL? {
        let data = try await get(
            "https://api.cenguigui.cn/api/netease/music_v1.php",
            query: [URLQueryItem(name: "id", value: song.sourceID),
                    URLQueryItem(name: "type", value: "json"),
                    URLQueryItem(name: "level", value: quality.neteaseLevel)]
        )
        return extractURL(data, paths: [["data", "url"], ["url"]])
    }

    private func neteaseGDStudio(_ song: MusicSong, _ quality: MusicQuality) async throws -> URL? {
        let data = try await get(
            "https://music-api.gdstudio.xyz/api.php",
            query: [URLQueryItem(name: "types", value: "url"),
                    URLQueryItem(name: "source", value: "netease"),
                    URLQueryItem(name: "id", value: song.sourceID),
                    URLQueryItem(name: "br", value: quality.gdstudioBitrate)]
        )
        return extractURL(data, paths: [["url"], ["data", "url"]])
    }

    // MARK: - QQ Music

    private func qqGDStudio(_ song: MusicSong, _ quality: MusicQuality) async throws -> URL? {
        let data = try await get(
            "https://music-api.gdstudio.xyz/api.php",
            query: [URLQueryItem(name: "types", value: "url"),
                    URLQueryItem(name: "source", value: "tencent"),
                    URLQueryItem(name: "id", value: song.sourceID),
                    URLQueryItem(name: "br", value: quality.gdstudioBitrate)]
        )
        return extractURL(data, paths: [["url"], ["data", "url"]])
    }

    private func qqChksz(_ song: MusicSong, _ quality: MusicQuality) async throws -> URL? {
        let body: [String: Any] = [
            "source": "qq",
            "songmid": song.sourceID,
            "quality": quality.rawValue
        ]
        let data = try await post("https://api.chksz.top/api", body: body)
        return extractURL(data, paths: [["data", "url"], ["url"]])
    }

    private func gdstudioPlatform(_ song: MusicSong, _ quality: MusicQuality) async throws -> URL? {
        let platform: String
        switch song.source {
        case .kugou: platform = "kugou"
        case .migu: platform = "migu"
        default: return nil
        }
        let data = try await get(
            "https://music-api.gdstudio.xyz/api.php",
            query: [URLQueryItem(name: "types", value: "url"),
                    URLQueryItem(name: "source", value: platform),
                    URLQueryItem(name: "id", value: song.sourceID),
                    URLQueryItem(name: "br", value: quality.gdstudioBitrate)]
        )
        return extractURL(data, paths: [["url"], ["data", "url"]])
    }

    // MARK: - HTTP and response parsing

    private func get(_ endpoint: String, query: [URLQueryItem]) async throws -> Any {
        guard var components = URLComponents(string: endpoint) else {
            throw MusicSourceError.invalidResponse("无效接口地址")
        }
        components.queryItems = query
        guard let url = components.url else {
            throw MusicSourceError.invalidResponse("无法生成请求地址")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        return try await send(request)
    }

    private func post(_ endpoint: String, body: [String: Any]) async throws -> Any {
        guard let url = URL(string: endpoint) else {
            throw MusicSourceError.invalidResponse("无效接口地址")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Any {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MusicSourceError.invalidResponse("HTTP \(status)")
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MusicSourceError.invalidResponse("非 JSON 响应")
        }
    }

    private func extractURL(_ object: Any, paths: [[String]]) -> URL? {
        for path in paths {
            var value: Any = object
            var found = true
            for key in path {
                guard let dictionary = value as? [String: Any],
                      let next = dictionary[key] else {
                    found = false
                    break
                }
                value = next
            }
            if found, let string = value as? String,
               let url = URL(string: string),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return url
            }
        }
        return nil
    }

    private func isPlayableURL(_ url: URL) -> Bool {
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
