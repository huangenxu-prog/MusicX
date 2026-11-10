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
        var failures: [String] = []

        for backend in backends(for: song.source) {
            do {
                if let url = try await backend(song, quality), isPlayableURL(url) {
                    return url
                }
                failures.append("接口未返回有效播放地址")
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        throw MusicSourceError.noPlayableURL(
            source: song.source,
            details: failures.suffix(3).joined(separator: "；")
        )
    }

    private typealias Backend = (MusicSong, MusicQuality) async throws -> URL?

    private func backends(for source: MusicSource) -> [Backend] {
        switch source {
        case .netease:
            return [neteaseChksz, neteaseCenguigui, neteaseGDStudio]
        case .qq:
            return [qqGDStudio, qqChksz]
        case .kuwo:
            return [kuwoLerd, kuwoCenguigui]
        case .kugou, .migu, .qishui:
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
                    URLQueryItem(name: "source", value: "qq"),
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
        request.timeoutInterval = 10
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
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await session.data(for: request)
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
