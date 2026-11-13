import Foundation

/// Native Migu playback URL provider. Migu's H5 listen-url endpoint may return
/// a lightweight obfuscated JSON payload; decode it before falling back to the
/// platform's direct listenSong URL. The legacy resolver remains a later fallback.
struct MiguNativeAudioProvider: MusicResourceProvider {
    let identifier = "migu-native-listen-url-v2"
    let displayName = "咪咕原生音源"

    private let session: URLSession
    private static let magic: [UInt8] = [0xAB, 0xCD, 0x01]
    private static let decodeKey = Array("Jk8qzuePiJ1qE3mDYhLQ3T73DtDoAhLP".utf8)

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        guard song.source == .migu else { return nil }
        let contentID = song.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contentID.isEmpty else { return nil }

        let tone: String
        let resourceType: String
        switch quality {
        case .standard:
            tone = "PQ"
            resourceType = "2"
        case .high:
            tone = "HQ"
            resourceType = "2"
        case .lossless, .hires:
            tone = "SQ"
            resourceType = "E"
        }

        var components = URLComponents(string: "https://c.musicapp.migu.cn/strategy/listen-url/h5/v2.4")
        components?.queryItems = [
            URLQueryItem(name: "contentId", value: contentID),
            URLQueryItem(name: "copyrightId", value: song.copyrightID ?? "0"),
            URLQueryItem(name: "resourceType", value: resourceType),
            URLQueryItem(name: "netType", value: "01"),
            URLQueryItem(name: "toneFlag", value: tone),
            URLQueryItem(name: "scene", value: ""),
            URLQueryItem(name: "lowerQualityContentId", value: contentID)
        ]
        guard let url = components?.url else {
            throw MusicSourceError.invalidResponse("咪咕播放地址请求参数无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "signature")
        request.setValue("h5page", forHTTPHeaderField: "birth")
        request.setValue("Android_migu", forHTTPHeaderField: "ua")
        request.setValue("6.8.8", forHTTPHeaderField: "version")
        request.setValue("014021I", forHTTPHeaderField: "channel")
        request.setValue("014021I", forHTTPHeaderField: "subchannel")
        request.setValue("https://h5.nf.migu.cn", forHTTPHeaderField: "Origin")
        request.setValue("https://h5.nf.migu.cn/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("咪咕播放接口 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        let payload = try decodePayload(data, signature: http.value(forHTTPHeaderField: "signature"))
        let root = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        guard let root else {
            throw MusicSourceError.invalidResponse("咪咕播放接口返回非 JSON 对象")
        }
        if let code = root["code"] {
            let value = String(describing: code)
            if !value.isEmpty && value != "000000" && value != "0" {
                // A valid API response with no licensed rendition is a
                // track-level miss, not a provider outage. Let the engine fall back.
                return try await fallback(song: song, after: quality)
            }
        }

        let body = root["data"] as? [String: Any] ?? root
        let rawURL = (body["url"] as? String)
            ?? (body["playUrl"] as? String)
            ?? (body["listenUrl"] as? String)
            ?? directListenSongURL(
                contentID: contentID,
                copyrightID: song.copyrightID ?? "0",
                tone: tone,
                resourceType: resourceType
            )
        guard let rawURL, let streamURL = URL(string: rawURL),
              let scheme = streamURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              streamURL.host?.isEmpty == false else {
            return try await fallback(song: song, after: quality)
        }

        return ResolvedMusicResource(
            url: streamURL,
            providerID: identifier,
            providerName: displayName
        )
    }

    private func fallback(song: MusicSong, after quality: MusicQuality) async throws -> ResolvedMusicResource? {
        switch quality {
        case .lossless, .hires:
            return try await resolve(song: song, quality: .high)
        case .high:
            return try await resolve(song: song, quality: .standard)
        case .standard:
            return nil
        }
    }

    private func decodePayload(_ data: Data, signature: String?) throws -> Data {
        let bytes = Array(data)
        let hasMagic = bytes.count >= 3 && Array(bytes.prefix(3)) == Self.magic
        guard signature == "1" || hasMagic else { return data }
        guard bytes.count > 4, !Self.decodeKey.isEmpty else {
            throw MusicSourceError.invalidResponse("咪咕加密响应长度异常")
        }

        let seed = Int(bytes[3])
        let decoded = bytes.dropFirst(4).enumerated().map { index, byte in
            UInt8((Int(byte) + seed - Int(Self.decodeKey[index % Self.decodeKey.count]) + 256) & 0xFF)
        }
        return Data(decoded)
    }

    private func directListenSongURL(
        contentID: String,
        copyrightID: String,
        tone: String,
        resourceType: String
    ) -> String? {
        var components = URLComponents(string: "https://app.pd.nf.migu.cn/MIGUM3.0/v1.0/content/sub/listenSong.do")
        components?.queryItems = [
            URLQueryItem(name: "channel", value: "mx"),
            URLQueryItem(name: "copyrightId", value: copyrightID),
            URLQueryItem(name: "contentId", value: contentID),
            URLQueryItem(name: "toneFlag", value: tone),
            URLQueryItem(name: "resourceType", value: resourceType),
            URLQueryItem(name: "userId", value: "15548614588710179085069"),
            URLQueryItem(name: "netType", value: "00")
        ]
        return components?.url?.absoluteString
    }
}
