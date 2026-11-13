import Foundation

/// Kumone-derived Kuwo supplier. It searches the first five candidates, applies
/// title/artist/duration/version matching, then converts the matched RID to a stream.
struct KumoneKuwoAudioSourceProvider: MusicResourceProvider {
    let identifier = "kumone-kuwo"
    let displayName = "Kumone · 酷我"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        try Task.checkCancellation()

        var searchComponents = URLComponents(string: "https://search.kuwo.cn/r.s")
        searchComponents?.queryItems = [
            URLQueryItem(name: "correct", value: "1"),
            URLQueryItem(name: "vipver", value: "1"),
            URLQueryItem(name: "stype", value: "comprehensive"),
            URLQueryItem(name: "encoding", value: "utf8"),
            URLQueryItem(name: "rformat", value: "json"),
            URLQueryItem(name: "mobi", value: "1"),
            URLQueryItem(name: "show_copyright_off", value: "1"),
            URLQueryItem(name: "searchapi", value: "6"),
            URLQueryItem(name: "all", value: "\(song.title) \(song.artist)")
        ]
        guard let searchURL = searchComponents?.url else {
            throw MusicSourceError.invalidResponse("酷我搜索地址无效")
        }

        var searchRequest = URLRequest(url: searchURL)
        searchRequest.timeoutInterval = 10
        searchRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (searchData, searchResponse) = try await session.data(for: searchRequest)
        try Task.checkCancellation()
        guard let http = searchResponse as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse(
                "Kuwo search HTTP \((searchResponse as? HTTPURLResponse)?.statusCode ?? -1)"
            )
        }

        guard let root = try JSONSerialization.jsonObject(with: searchData) as? [String: Any] else {
            throw MusicSourceError.invalidResponse("酷我搜索响应格式错误")
        }
        let content = root["content"] as? [[String: Any]] ?? []
        let musicPage = content
            .compactMap { $0["musicpage"] as? [String: Any] }
            .first { $0["abslist"] is [[String: Any]] }
            ?? (root["musicpage"] as? [String: Any])
        guard let rows = musicPage?["abslist"] as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("酷我搜索响应中没有歌曲列表")
        }

        let candidates: [Candidate] = rows.prefix(5).compactMap { row in
            guard let musicRID = row["MUSICRID"] as? String,
                  let rid = musicRID.split(separator: "_").last.map(String.init),
                  let title = row["SONGNAME"] as? String,
                  let artist = row["ARTIST"] as? String,
                  let rawDuration = row["DURATION"],
                  let duration = Self.durationSeconds(rawDuration) else { return nil }

            let album = row["ALBUM"] as? String ?? row["ALBUMNAME"] as? String
            guard AudioSourceTrackMatcher.matches(
                original: song,
                candidateTitle: title,
                candidateArtist: artist,
                candidateDuration: duration,
                candidateAlbum: album,
                requireDuration: true
            ) else { return nil }

            return Candidate(rid: rid, duration: duration)
        }
        .sorted {
            AudioSourceTrackMatcher.durationDifference(original: song, candidateDuration: $0.duration)
                < AudioSourceTrackMatcher.durationDifference(original: song, candidateDuration: $1.duration)
        }

        guard let candidate = candidates.first else { return nil }
        try Task.checkCancellation()

        var convertComponents = URLComponents(string: "https://antiserver.kuwo.cn/anti.s")
        convertComponents?.queryItems = [
            URLQueryItem(name: "type", value: "convert_url"),
            URLQueryItem(name: "format", value: "mp3"),
            URLQueryItem(name: "response", value: "url"),
            URLQueryItem(name: "rid", value: "MUSIC_\(candidate.rid)")
        ]
        guard let convertURL = convertComponents?.url else {
            throw MusicSourceError.invalidResponse("酷我播放地址请求无效")
        }

        var convertRequest = URLRequest(url: convertURL)
        convertRequest.timeoutInterval = 10
        convertRequest.setValue("okhttp/3.10.0", forHTTPHeaderField: "User-Agent")
        let (streamData, streamResponse) = try await session.data(for: convertRequest)
        try Task.checkCancellation()
        guard let streamHTTP = streamResponse as? HTTPURLResponse,
              (200..<300).contains(streamHTTP.statusCode) else {
            throw MusicSourceError.invalidResponse(
                "Kuwo stream HTTP \((streamResponse as? HTTPURLResponse)?.statusCode ?? -1)"
            )
        }

        guard let responseText = String(data: streamData, encoding: .utf8),
              let rawURL = responseText
                .components(separatedBy: .whitespacesAndNewlines)
                .first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") })?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>")),
              var url = URL(string: rawURL) else {
            throw MusicSourceError.invalidResponse("酷我没有返回有效播放地址")
        }
        // Kuwo's resolver may return an HTTP CDN URL. Upgrade it to HTTPS
        // before handing it to URLSession/AVPlayer so ATS does not block it.
        if url.scheme?.lowercased() == "http",
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let secureURL = components.url { url = secureURL }
        }
        guard url.scheme?.lowercased() == "https", Self.isHTTPURL(url) else {
            throw MusicSourceError.invalidResponse("酷我没有返回可通过 ATS 的 HTTPS 播放地址")
        }

        return ResolvedMusicResource(url: url, providerID: identifier, providerName: displayName)
    }

    private struct Candidate {
        let rid: String
        let duration: TimeInterval
    }

    private static func durationSeconds(_ value: Any) -> TimeInterval? {
        if let number = value as? Int { return TimeInterval(number) }
        if let number = value as? Double { return number }
        guard let string = value as? String else { return nil }
        if let number = Double(string) { return number }
        let pieces = string.split(separator: ":").compactMap { Double($0) }
        guard !pieces.isEmpty else { return nil }
        return pieces.reversed().enumerated().reduce(0) { total, part in
            total + part.element * pow(60, Double(part.offset))
        }
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return false }
        return true
    }
}
