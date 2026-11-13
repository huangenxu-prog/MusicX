import Foundation

/// Native Migu playback URL provider. It uses the platform content ID and
/// copyright ID retained by catalog adapters; the legacy resolver remains fallback.
struct MiguNativeAudioProvider: MusicResourceProvider {
    let identifier = "migu-native-listen-song"
    let displayName = "咪咕原生音源"

    private let session: URLSession

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

        var components = URLComponents(string: "https://app.pd.nf.migu.cn/MIGUM2.0/v1.0/content/sub/listenSong.do")
        components?.queryItems = [
            URLQueryItem(name: "toneFlag", value: tone),
            URLQueryItem(name: "netType", value: "00"),
            URLQueryItem(name: "userId", value: "15548614588710179085069"),
            URLQueryItem(name: "ua", value: "Android_migu"),
            URLQueryItem(name: "version", value: "5.1"),
            URLQueryItem(name: "copyrightId", value: song.copyrightID ?? "0"),
            URLQueryItem(name: "contentId", value: contentID),
            URLQueryItem(name: "resourceType", value: resourceType),
            URLQueryItem(name: "channel", value: "0")
        ]
        guard let url = components?.url else {
            throw MusicSourceError.invalidResponse("咪咕播放地址请求参数无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("https://music.migu.cn/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("咪咕播放接口 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusicSourceError.invalidResponse("咪咕播放接口返回非 JSON 对象")
        }
        if let code = root["code"] as? String, !code.isEmpty, code != "000000" {
            throw MusicSourceError.invalidResponse("咪咕播放业务状态异常：\(code)")
        }
        let payload = root["data"] as? [String: Any] ?? root
        let rawURL = (payload["url"] as? String)
            ?? (payload["playUrl"] as? String)
            ?? (payload["listenUrl"] as? String)
        guard let rawURL, let streamURL = URL(string: rawURL),
              let scheme = streamURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              streamURL.host?.isEmpty == false else {
            return nil
        }

        return ResolvedMusicResource(
            url: streamURL,
            providerID: identifier,
            providerName: displayName
        )
    }
}
