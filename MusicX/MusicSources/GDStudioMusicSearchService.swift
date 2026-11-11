import Foundation

struct GDStudioMusicSearchService {
    private let session: URLSession
    private let baseURL = "https://music-api.gdstudio.xyz/api.php"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(keyword: String, source: MusicSource, page: Int = 1, count: Int = 20, albumOnly: Bool = false) async throws -> [MusicSong] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let cacheKey = "search|\\(source.rawValue)|\\(query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))|\\(page)|\\(count)|\\(albumOnly)"
        if let cached: [MusicSong] = await MusicCache.shared.value(for: cacheKey) {
            return cached
        }
        let startedAt = Date()
        var diagnosticResult = "failed"
        var diagnosticCount = 0
        defer {
            MusicSourceDiagnostics.shared.record(
                event: "search", source: source.rawValue, provider: "gdstudio-search",
                duration: Date().timeIntervalSince(startedAt), result: diagnosticResult,
                detail: "count=\(diagnosticCount)"
            )
        }
        guard var components = URLComponents(string: baseURL) else {
            throw MusicSourceError.invalidResponse("搜索接口地址无效")
        }
        components.queryItems = [
            URLQueryItem(name: "types", value: "search"),
            URLQueryItem(name: "source", value: gdSource(source) + (albumOnly ? "_album" : "")),
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "pages", value: String(page))
        ]
        guard let url = components.url else {
            throw MusicSourceError.invalidResponse("无法生成搜索请求")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("搜索 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("搜索结果不是歌曲列表")
        }
        let songs: [MusicSong] = rows.compactMap { (row: [String: Any]) -> MusicSong? in
            guard let id = row["id"] else { return nil }
            let artist: String
            if let names = row["artist"] as? [String] { artist = names.joined(separator: " / ") }
            else if let name = row["artist"] as? String { artist = name }
            else { artist = "未知歌手" }
            let album = row["album"] as? String
            return MusicSong(
                source: source,
                sourceID: String(describing: id),
                title: row["name"] as? String ?? "未知歌曲",
                artist: artist,
                album: album,
                artworkURL: nil,
                duration: nil,
                hash: row["hash"] as? String,
                albumID: row["album_id"].map { String(describing: $0) },
                pictureID: row["pic_id"].map { String(describing: $0) },
                lyricID: row["lyric_id"].map { String(describing: $0) }
            )
        }
        diagnosticCount = songs.count
        diagnosticResult = "success"
        await MusicCache.shared.insert(songs, for: cacheKey, ttl: 5 * 60)
        return songs
    }

    
    /// Searches for a real NetEase playlist, then loads its tracks by playlist ID.
    func playlistTracks(keyword: String, count: Int = 50) async throws -> [MusicSong] {
        var searchComponents = URLComponents(string: "https://music.163.com/api/search/get/web")
        searchComponents?.queryItems = [
            URLQueryItem(name: "s", value: keyword),
            URLQueryItem(name: "type", value: "1000"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "offset", value: "0")
        ]
        guard let searchURL = searchComponents?.url else {
            throw MusicSourceError.invalidResponse("无法生成歌单搜索请求")
        }
        var searchRequest = URLRequest(url: searchURL)
        searchRequest.timeoutInterval = 12
        searchRequest.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        searchRequest.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        let (searchData, searchResponse) = try await session.data(for: searchRequest)
        guard let searchHTTP = searchResponse as? HTTPURLResponse, (200..<300).contains(searchHTTP.statusCode) else {
            throw MusicSourceError.invalidResponse("网易云歌单搜索 HTTP \((searchResponse as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let searchRoot = try JSONSerialization.jsonObject(with: searchData) as? [String: Any]
        let searchResult = searchRoot?["result"] as? [String: Any]
        guard let playlists = searchResult?["playlists"] as? [[String: Any]],
              !playlists.isEmpty else {
            throw MusicSourceError.invalidResponse("没有找到匹配的真实歌单")
        }
        let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchedPlaylist = playlists.first { row in
            let name = row["name"] as? String ?? ""
            return name.localizedCaseInsensitiveCompare(normalizedKeyword) == .orderedSame
        } ?? playlists.first { row in
            let name = row["name"] as? String ?? ""
            return name.localizedCaseInsensitiveContains(normalizedKeyword)
        } ?? playlists.first
        guard let playlistID = matchedPlaylist?["id"] else {
            throw MusicSourceError.invalidResponse("歌单搜索结果缺少有效 ID")
        }
        var detailComponents = URLComponents(string: "https://music.163.com/api/playlist/detail")
        detailComponents?.queryItems = [URLQueryItem(name: "id", value: String(describing: playlistID))]
        guard let detailURL = detailComponents?.url else {
            throw MusicSourceError.invalidResponse("无法生成歌单详情请求")
        }
        var detailRequest = URLRequest(url: detailURL)
        detailRequest.timeoutInterval = 12
        detailRequest.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        detailRequest.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        let (detailData, detailResponse) = try await session.data(for: detailRequest)
        guard let detailHTTP = detailResponse as? HTTPURLResponse, (200..<300).contains(detailHTTP.statusCode) else {
            throw MusicSourceError.invalidResponse("网易云歌单详情 HTTP \((detailResponse as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let detailRoot = try JSONSerialization.jsonObject(with: detailData) as? [String: Any]
        let detailResult = detailRoot?["result"] as? [String: Any] ?? detailRoot?["playlist"] as? [String: Any]
        guard let rows = detailResult?["tracks"] as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("网易云没有返回歌单曲目")
        }
        return rows.prefix(count).compactMap { row in
            guard let id = row["id"] else { return nil }
            let artists = (row["ar"] as? [[String: Any]] ?? row["artists"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }.joined(separator: " / ")
            let albumInfo = row["al"] as? [String: Any] ?? row["album"] as? [String: Any] ?? [:]
            let albumName = albumInfo["name"] as? String
            let artwork = (albumInfo["picUrl"] as? String).flatMap(URL.init(string:))
            let duration = (row["dt"] as? Double).map { $0 / 1000 }
                ?? (row["duration"] as? Double).map { $0 / 1000 }
            return MusicSong(
                source: .netease, sourceID: String(describing: id),
                title: row["name"] as? String ?? "未知歌曲",
                artist: artists.isEmpty ? "未知歌手" : artists,
                album: albumName, artworkURL: artwork, duration: duration,
                hash: nil, albumID: albumInfo["id"].map { String(describing: $0) },
                pictureID: nil, lyricID: String(describing: id)
            )
        }
    }

    /// Reads the public NetEase playlist endpoints used for its live charts.
    /// Returned track IDs remain NetEase IDs and are resolved for playback by GD Studio.
    func toplist(_ chartName: String, count: Int = 50) async throws -> [MusicSong] {
        let playlistID: String
        switch chartName {
        case "新歌榜": playlistID = "3779629"
        case "飙升榜": playlistID = "19723756"
        default: playlistID = "3778678"
        }
        var components = URLComponents(string: "https://music.163.com/api/playlist/detail")
        components?.queryItems = [URLQueryItem(name: "id", value: playlistID)]
        guard let url = components?.url else {
            throw MusicSourceError.invalidResponse("无法生成网易云榜单请求")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("网易云榜单 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = root?["result"] as? [String: Any] ?? root?["playlist"] as? [String: Any]
        guard let rows = result?["tracks"] as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("网易云没有返回榜单曲目")
        }
        return rows.prefix(count).compactMap { row in
            guard let id = row["id"] else { return nil }
            let artists = (row["ar"] as? [[String: Any]] ?? row["artists"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }.joined(separator: " / ")
            let albumInfo = row["al"] as? [String: Any] ?? row["album"] as? [String: Any] ?? [:]
            let albumName = albumInfo["name"] as? String
            let artwork = (albumInfo["picUrl"] as? String).flatMap(URL.init(string:))
            let duration = (row["dt"] as? Double).map { $0 / 1000 }
                ?? (row["duration"] as? Double).map { $0 / 1000 }
            return MusicSong(
                source: .netease,
                sourceID: String(describing: id),
                title: row["name"] as? String ?? "未知歌曲",
                artist: artists.isEmpty ? "未知歌手" : artists,
                album: albumName,
                artworkURL: artwork,
                duration: duration,
                hash: nil,
                albumID: albumInfo["id"].map { String(describing: $0) },
                pictureID: (albumInfo["pic_str"] ?? albumInfo["pic"]).map { String(describing: $0) },
                lyricID: String(describing: id)
            )
        }
    }

    private func gdSource(_ source: MusicSource) -> String {
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
