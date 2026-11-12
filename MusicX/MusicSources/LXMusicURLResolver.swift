import Foundation

/// Native Swift implementation of the URL-resolution paths found in the supplied
/// 洛雪音源3.js. Search is intentionally separate: the LX plugin contract receives
/// an already identified song and only resolves its playable URL.
struct LXMusicURLResolver: MusicURLResolving {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(song: MusicSong, quality: MusicQuality = .high) async throws -> URL {
        let cacheKey = "playback-url|\(song.source.rawValue)|\(song.sourceID)|\(quality.rawValue)"
        if let cached: URL = await MusicCache.shared.value(for: cacheKey) {
            MusicSourceDiagnostics.shared.record(event: "resolve", source: song.source.rawValue,
                                                  provider: "disk-cache", duration: 0, result: "cache_hit")
            return cached
        }
        var failures: [String] = []

        for backend in backends(for: song.source) {
            try Task.checkCancellation()
            let startedAt = Date()
            do {
                if let url = try await resolveWithRetry(backend, song: song, quality: quality), isPlayableURL(url) {
                    try Task.checkCancellation()
                    MusicSourceDiagnostics.shared.record(
                        event: "resolve", source: song.source.rawValue,
                        provider: backend.name, duration: Date().timeIntervalSince(startedAt),
                        result: "url_returned"
                    )
                    await MusicCache.shared.insert(url, for: cacheKey, ttl: 5 * 60)
                    return url
                }
                failures.append("接口未返回有效播放地址")
                MusicSourceDiagnostics.shared.record(
                    event: "resolve", source: song.source.rawValue,
                    provider: backend.name, duration: Date().timeIntervalSince(startedAt),
                    result: "empty_url"
                )
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    MusicSourceDiagnostics.shared.record(
                        event: "resolve", source: song.source.rawValue,
                        provider: backend.name, duration: Date().timeIntervalSince(startedAt),
                        result: "cancelled"
                    )
                    throw CancellationError()
                }
                failures.append(error.localizedDescription)
                MusicSourceDiagnostics.shared.record(
                    event: "resolve", source: song.source.rawValue,
                    provider: backend.name, duration: Date().timeIntervalSince(startedAt),
                    result: "failed", detail: error.localizedDescription
                )
            }
        }

        if song.source == .qq {
            if let fallbackURL = try await resolveQQSongThroughNetEase(song, quality: quality) {
                return fallbackURL
            }
        }

        throw MusicSourceError.noPlayableURL(
            source: song.source,
            details: failures.suffix(3).joined(separator: "；")
        )
    }

    /// QQ playlist metadata stays QQ-native. Only when QQ playback URL providers fail,
    /// search NetEase by title and artist and use a strictly matched NetEase track ID.
    private func resolveQQSongThroughNetEase(_ song: MusicSong, quality: MusicQuality) async throws -> URL? {
        let searchService = GDStudioMusicSearchService(session: session)
        let candidates = try await searchService.search(
            keyword: song.title,
            source: .netease,
            page: 1,
            count: 12
        )
        let wantedTitle = normalizedMatchText(song.title)
        let wantedArtists = Set(song.artist.split(separator: "/").map {
            normalizedMatchText(String($0))
        }.filter { !$0.isEmpty })

        guard let matchedSong = candidates.first(where: { candidate in
            guard normalizedMatchText(candidate.title) == wantedTitle else { return false }
            let candidateArtists = candidate.artist.split(separator: "/").map {
                normalizedMatchText(String($0))
            }.filter { !$0.isEmpty }
            return candidateArtists.contains { candidateArtist in
                wantedArtists.contains { wantedArtist in
                    candidateArtist == wantedArtist
                        || candidateArtist.contains(wantedArtist)
                        || wantedArtist.contains(candidateArtist)
                }
            }
        }) else {
            MusicSourceDiagnostics.shared.record(
                event: "resolve-fallback", source: song.source.rawValue,
                provider: "netease-search", duration: 0, result: "no_exact_match",
                detail: "title=\(song.title)"
            )
            return nil
        }

        for backend in backends(for: .netease) {
            try Task.checkCancellation()
            let startedAt = Date()
            do {
                if let url = try await resolveWithRetry(backend, song: matchedSong, quality: quality),
                   isPlayableURL(url) {
                    MusicSourceDiagnostics.shared.record(
                        event: "resolve-fallback", source: song.source.rawValue,
                        provider: backend.name, duration: Date().timeIntervalSince(startedAt),
                        result: "url_returned", detail: "matched=\(matchedSong.title) · \(matchedSong.artist)"
                    )
                    return url
                }
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                MusicSourceDiagnostics.shared.record(
                    event: "resolve-fallback", source: song.source.rawValue,
                    provider: backend.name, duration: Date().timeIntervalSince(startedAt),
                    result: "failed", detail: error.localizedDescription
                )
            }
        }
        return nil
    }

    private func normalizedMatchText(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Force a fresh provider lookup after AVPlayer rejects a previously resolved URL.
    func resolveFresh(song: MusicSong, quality: MusicQuality = .high) async throws -> URL {
        let cacheKey = "playback-url|\(song.source.rawValue)|\(song.sourceID)|\(quality.rawValue)"
        await MusicCache.shared.removeValue(for: cacheKey)
        return try await resolve(song: song, quality: quality)
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

    private struct Backend {
        let name: String
        let resolve: (MusicSong, MusicQuality) async throws -> URL?
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
        case .kuwo:
            return [
                Backend(name: "kuwo-gdstudio", resolve: kuwoGDStudio),
                Backend(name: "kuwo-lerd", resolve: kuwoLerd),
                Backend(name: "kuwo-cenguigui", resolve: kuwoCenguigui)
            ]
        case .kugou, .migu:
            return [Backend(name: "\(source.rawValue)-gdstudio", resolve: gdstudioPlatform)]
        case .qishui, .youtubeMusic, .youtube, .spotify:
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

    private func kuwoGDStudio(_ song: MusicSong, _ quality: MusicQuality) async throws -> URL? {
        let data = try await get(
            "https://music-api.gdstudio.xyz/api.php",
            query: [URLQueryItem(name: "types", value: "url"),
                    URLQueryItem(name: "source", value: "kuwo"),
                    URLQueryItem(name: "id", value: song.sourceID),
                    URLQueryItem(name: "br", value: quality.gdstudioBitrate)]
        )
        return extractURL(data, paths: [["url"], ["data", "url"]])
    }

    // MARK: - Kuwo

    private func kuwoLerd(_ song: MusicSong, _ quality: MusicQuality) async throws -> URL? {
        let data = try await post(
            "https://api.music.lerd.dpdns.org/kw",
            body: ["musicInfo": ["songmid": song.sourceID], "type": quality.rawValue]
        )
        return extractURL(data, paths: [["data", "url"], ["url"]])
    }

    private func kuwoCenguigui(_ song: MusicSong, _ quality: MusicQuality) async throws -> URL? {
        let level: String
        switch quality {
        case .standard: level = "128k"
        case .high: level = "320k"
        case .lossless, .hires: level = "flac"
        }
        let data = try await get(
            "https://api.cenguigui.cn/api/kuwo/music_v1.php",
            query: [URLQueryItem(name: "id", value: song.sourceID),
                    URLQueryItem(name: "type", value: "song"),
                    URLQueryItem(name: "format", value: "json"),
                    URLQueryItem(name: "level", value: level)]
        )
        return extractURL(data, paths: [["data", "url"], ["url"]])
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
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}
