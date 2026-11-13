import Foundation

/// Dedicated QQ native URL providers. Keeping the endpoints separate makes
/// provider health, latency and failure diagnostics independently measurable.
private enum QQNativeAudioTransport {
    static func request(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        session: URLSession
    ) async throws -> Any {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw MusicSourceError.invalidResponse("QQ 原生解析返回了非 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("HTTP \(http.statusCode)")
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MusicSourceError.invalidResponse("QQ 原生解析响应不是有效 JSON")
        }
    }

    static func extractURL(_ object: Any) -> URL? {
        let dictionaries: [[String: Any]]
        if let root = object as? [String: Any] {
            dictionaries = [root, root["data"] as? [String: Any] ?? [:]]
        } else {
            dictionaries = []
        }
        for dictionary in dictionaries {
            for key in ["url", "play_url", "playUrl"] {
                guard let raw = dictionary[key] as? String,
                      let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme),
                      let host = url.host, !host.isEmpty else { continue }
                return url
            }
        }
        return nil
    }
}

/// QQ Music GDStudio endpoint (source=tencent).
struct QQGDStudioAudioProvider: MusicResourceProvider {
    let identifier = "qq-gdstudio"
    let displayName = "QQ · GDStudio"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        guard song.source == .qq, !song.sourceID.isEmpty else { return nil }
        var components = URLComponents(string: "https://music-api.gdstudio.xyz/api.php")
        components?.queryItems = [
            URLQueryItem(name: "types", value: "url"),
            URLQueryItem(name: "source", value: "tencent"),
            URLQueryItem(name: "id", value: song.sourceID),
            URLQueryItem(name: "br", value: quality.gdstudioBitrate)
        ]
        guard let url = components?.url else {
            throw MusicSourceError.invalidResponse("QQ GDStudio 请求地址无效")
        }
        let object = try await QQNativeAudioTransport.request(url: url, session: session)
        guard let streamURL = QQNativeAudioTransport.extractURL(object) else {
            throw MusicSourceError.invalidResponse("QQ GDStudio 未返回有效播放地址")
        }
        return ResolvedMusicResource(
            url: streamURL,
            providerID: identifier,
            providerName: displayName
        )
    }
}

/// QQ Music Chksz endpoint (POST source=qq).
struct QQChkszAudioProvider: MusicResourceProvider {
    let identifier = "qq-chksz"
    let displayName = "QQ · Chksz"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        guard song.source == .qq, !song.sourceID.isEmpty else { return nil }
        let body: [String: Any] = [
            "source": "qq",
            "songmid": song.sourceID,
            "quality": quality.rawValue
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        guard let url = URL(string: "https://api.chksz.top/api") else {
            throw MusicSourceError.invalidResponse("QQ Chksz 请求地址无效")
        }
        let object = try await QQNativeAudioTransport.request(
            url: url,
            method: "POST",
            body: data,
            session: session
        )
        guard let streamURL = QQNativeAudioTransport.extractURL(object) else {
            throw MusicSourceError.invalidResponse("QQ Chksz 未返回有效播放地址")
        }
        return ResolvedMusicResource(
            url: streamURL,
            providerID: identifier,
            providerName: displayName
        )
    }
}
