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
        let cacheKey = "search|\(source.rawValue)|\(query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))|\(page)|\(count)|\(albumOnly)"
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
            let rawDuration = row["interval"] ?? row["duration"] ?? row["dt"]
            let parsedDuration: TimeInterval? = {
                guard let rawDuration else { return nil }
                if let value = rawDuration as? Double {
                    return value > 1_000 ? value / 1_000 : value
                }
                if let value = rawDuration as? Int {
                    return value > 1_000 ? Double(value) / 1_000 : Double(value)
                }
                return nil
            }()
            return MusicSong(
                source: source,
                sourceID: String(describing: id),
                title: row["name"] as? String ?? "未知歌曲",
                artist: artist,
                album: album,
                artworkURL: nil,
                duration: parsedDuration,
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

    
    /// Searches QQ Music's real playlist index and returns provider-native playlist metadata.
    func searchPlaylists(keyword: String, count: Int = 10) async throws -> [MusicPlaylist] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let cacheKey = "catalog-playlists|\(query.lowercased())|\(count)"
        if let cached = await MusicCatalogStore.shared.snapshot(for: cacheKey, as: [MusicPlaylist].self) {
            if cached.needsRefresh {
                Task { _ = try? await self.refreshPlaylistSearch(keyword: query, count: count, cacheKey: cacheKey) }
            }
            return cached.value
        }
        return try await refreshPlaylistSearch(keyword: query, count: count, cacheKey: cacheKey)
    }

    private func refreshPlaylistSearch(keyword query: String, count: Int, cacheKey: String) async throws -> [MusicPlaylist] {
        let data = try await requestQQMusicU(
            module: "music.search.SearchCgiService",
            method: "DoSearchForQQMusicDesktop",
            parameters: [
                "query": query,
                "num_per_page": min(max(count, 1), 30),
                "page_num": 1,
                "search_type": 3
            ]
        )
        let body = data["body"] as? [String: Any]
        let container = body?["songlist"] as? [String: Any]
        let rows = container?["list"] as? [[String: Any]] ?? []
        let playlists = rows.compactMap { row in
            guard let rawID = row["dissid"] ?? row["id"] ?? row["tid"] ?? row["dirid"] else {
                return nil
            }
            let name = (row["dissname"] as? String)
                ?? (row["name"] as? String)
                ?? (row["title"] as? String)
                ?? ""
            guard !name.isEmpty else { return nil }
            let rawArtwork = (row["imgurl"] as? String)
                ?? (row["picurl"] as? String)
                ?? (row["cover"] as? String)
                ?? (row["cover_url"] as? String)
            let creatorValue = row["creator"]
            let creator = (creatorValue as? String)
                ?? ((creatorValue as? [String: Any])?["name"] as? String)
            let description = (row["introduction"] as? String)
                ?? (row["desc"] as? String)
            let trackCount = (row["songnum"] as? Int)
                ?? (row["song_count"] as? Int)
            return MusicPlaylist(
                source: .qq,
                sourceID: String(describing: rawID),
                name: name,
                creator: creator,
                description: description,
                artworkURL: rawArtwork.flatMap(URL.init(string:)),
                trackCount: trackCount
            )
        }
    }

    /// Resolves a legacy editorial keyword to a QQ playlist, then loads by its native ID.
    /// This keeps existing string-based routes working while avoiding a second fuzzy
    /// search in the track-loading path.
    func playlistTracks(keyword: String, count: Int = 50) async throws -> [MusicSong] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let cacheKey = "qq-playlist-keyword|\(query.lowercased())|\(count)"
        if let cached: [MusicSong] = await MusicCache.shared.value(for: cacheKey) {
            return cached
        }
        let playlists = try await searchPlaylists(keyword: query, count: 20)
        let normalizedQuery = query.filter { !$0.isWhitespace }.lowercased()
        let ranked = playlists.map { playlist -> (MusicPlaylist, Int) in
            let name = playlist.name.filter { !$0.isWhitespace }.lowercased()
            let score = name == normalizedQuery ? 100
                : (name.contains(normalizedQuery) ? 80
                : (normalizedQuery.contains(name) && !name.isEmpty ? 60 : 0))
            return (playlist, score)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        guard let selected = ranked.first?.0 else {
            throw MusicSourceError.invalidResponse("没有找到与“\(query)”匹配的 QQ 音乐歌单")
        }
        let tracks = try await playlistTracks(playlistID: selected.sourceID, count: count)
        await MusicCache.shared.insert(tracks, for: cacheKey, ttl: 10 * 60)
        return tracks
    }

    /// Loads tracks directly from a previously resolved QQ Music playlist ID.
    func playlistTracks(playlistID: String, count: Int = 50) async throws -> [MusicSong] {
        let normalizedID = playlistID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let numericPlaylistID = Int(normalizedID), numericPlaylistID > 0, count > 0 else {
            throw MusicSourceError.invalidResponse("QQ音乐歌单 ID 无效")
        }
        let cacheKey = "qq-playlist-tracks|\(normalizedID)|\(count)"
        if let cached: [MusicSong] = await MusicCache.shared.value(for: cacheKey) { return cached }
        var songs: [MusicSong] = []
        var begin = 0
        let pageSize = 30
        var hasMore = true
        while songs.count < count && hasMore {
            try Task.checkCancellation()
            let remaining = count - songs.count
            let detailData = try await requestQQMusicU(module: "music.srfDissInfo.aiDissInfo",
                method: "uniform_get_Dissinfo",
                parameters: ["disstid": numericPlaylistID, "song_begin": begin, "song_num": min(pageSize, remaining)])
            let rows = detailData["songlist"] as? [[String: Any]] ?? []
            let pageSongs = rows.compactMap { row -> MusicSong? in
                guard let rawID = row["mid"] as? String, !rawID.isEmpty else { return nil }
                let artists = (row["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " / ")
                let albumInfo = row["album"] as? [String: Any] ?? [:]
                let albumName = albumInfo["name"] as? String
                let albumMID = albumInfo["mid"] as? String
                let artworkURL = albumMID.flatMap { URL(string: "https://y.gtimg.cn/music/photo_new/T002R300x300M000\($0).jpg?max_age=2592000") }
                let duration = (row["interval"] as? Double) ?? (row["interval"] as? Int).map(Double.init)
                return MusicSong(source: .qq, sourceID: rawID, title: row["name"] as? String ?? "未知歌曲",
                    artist: artists.isEmpty ? "未知歌手" : artists, album: albumName, artworkURL: artworkURL,
                    duration: duration, hash: nil, albumID: albumMID, pictureID: albumMID, lyricID: rawID)
            }
            songs.append(contentsOf: pageSongs)
            let moreFlag = detailData["hasmore"]
            hasMore = (moreFlag as? Bool) ?? ((moreFlag as? Int) == 1)
            if rows.isEmpty { hasMore = false }
            begin += rows.count
        }
        guard !songs.isEmpty else { throw MusicSourceError.invalidResponse("QQ音乐歌单存在，但没有返回可用曲目") }
        let result = Array(songs.prefix(count))
        await MusicCache.shared.insert(result, for: cacheKey, ttl: 10 * 60)
        return result
    }

    private func requestQQMusicU(
        module: String,
        method: String,
        parameters: [String: Any]
    ) async throws -> [String: Any] {
        guard let url = URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg") else {
            throw MusicSourceError.invalidResponse("QQ音乐接口地址无效")
        }
        let payload: [String: Any] = [
            module: [
                "module": module,
                "method": method,
                "param": parameters
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("QQ音乐接口 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let service = root[module] as? [String: Any] else {
            throw MusicSourceError.invalidResponse("QQ音乐接口返回结构异常")
        }
        let code = service["code"] as? Int ?? 0
        guard code == 0, let result = service["data"] as? [String: Any] else {
            throw MusicSourceError.invalidResponse("QQ音乐服务返回错误 code=\(code)")
        }
        return result
    }

    /// Reads the public NetEase playlist endpoints used for its live charts.
    /// Returned track IDs remain NetEase IDs and are resolved for playback by GD Studio.
    func toplist(_ chartName: String, count: Int = 50) async throws -> [MusicSong] {
        let normalizedChart = ["热歌榜", "新歌榜", "飙升榜"].contains(chartName) ? chartName : "热歌榜"
        let cacheKey = "catalog-chart|\(normalizedChart)|\(count)"
        if let cached = await MusicCatalogStore.shared.snapshot(for: cacheKey, as: [MusicSong].self) {
            if cached.needsRefresh {
                Task { _ = try? await self.refreshToplist(normalizedChart, count: count, cacheKey: cacheKey) }
            }
            return cached.value
        }
        return try await refreshToplist(normalizedChart, count: count, cacheKey: cacheKey)
    }

    private func refreshToplist(_ chartName: String, count: Int, cacheKey: String) async throws -> [MusicSong] {
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
        let songs = rows.prefix(count).compactMap { row in
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
