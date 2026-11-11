import Foundation

struct GDStudioMetadataService {
    private struct CachedLyrics: Codable {
        let original: String
        let translated: String?
    }

    private let session: URLSession
    private let endpoint = "https://music-api.gdstudio.xyz/api.php"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func artworkURL(for song: MusicSong, size: Int = 500) async throws -> URL? {
        guard let pictureID = song.pictureID, !pictureID.isEmpty else { return nil }
        let cacheKey = "artwork-url|\(song.source.rawValue)|\(pictureID)|\(size)"
        if let cached: URL = await MusicCache.shared.value(for: cacheKey) { return cached }
        let object = try await request([
            URLQueryItem(name: "types", value: "pic"),
            URLQueryItem(name: "source", value: sourceName(song.source)),
            URLQueryItem(name: "id", value: pictureID),
            URLQueryItem(name: "size", value: String(size))
        ])
        let result = extractURL(object, key: "url")
        if let result { await MusicCache.shared.insert(result, for: cacheKey, ttl: 7 * 24 * 60 * 60) }
        return result
    }

    func lyrics(for song: MusicSong) async throws -> (original: String, translated: String?)? {
        guard let lyricID = song.lyricID, !lyricID.isEmpty else { return nil }
        let cacheKey = "lyrics|\(song.source.rawValue)|\(lyricID)"
        if let cached: CachedLyrics = await MusicCache.shared.value(for: cacheKey) {
            return (cached.original, cached.translated)
        }
        let object = try await request([
            URLQueryItem(name: "types", value: "lyric"),
            URLQueryItem(name: "source", value: sourceName(song.source)),
            URLQueryItem(name: "id", value: lyricID)
        ])
        guard let dictionary = object as? [String: Any],
              let original = dictionary["lyric"] as? String,
              !original.isEmpty else { return nil }
        let translated = dictionary["tlyric"] as? String
        await MusicCache.shared.insert(CachedLyrics(original: original, translated: translated),
                                       for: cacheKey, ttl: 7 * 24 * 60 * 60)
        return (original, translated)
    }

    private func request(_ query: [URLQueryItem]) async throws -> Any {
        guard var components = URLComponents(string: endpoint) else {
            throw MusicSourceError.invalidResponse("GDStudio 接口地址无效")
        }
        components.queryItems = query
        guard let url = components.url else {
            throw MusicSourceError.invalidResponse("无法生成元数据请求")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("元数据 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func extractURL(_ object: Any, key: String) -> URL? {
        guard let dictionary = object as? [String: Any],
              let raw = dictionary[key] as? String,
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func sourceName(_ source: MusicSource) -> String {
        switch source {
        case .netease: "netease"
        case .qq: "tencent"
        case .kuwo: "kuwo"
        case .kugou: "kugou"
        case .migu: "migu"
        case .qishui: "netease"
        case .youtubeMusic, .youtube, .spotify: "netease"
        }
    }
}
