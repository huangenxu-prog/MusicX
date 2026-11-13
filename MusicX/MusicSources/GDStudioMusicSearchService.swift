import Foundation

struct GDStudioMusicSearchService {
    private let session: URLSession
    private let baseURLs = ["https://music-api.gdstudio.xyz/api.php"]

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
        let queryItems = [
            URLQueryItem(name: "types", value: "search"),
            URLQueryItem(name: "source", value: gdSource(source) + (albumOnly ? "_album" : "")),
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "pages", value: String(page))
        ]
        var responseData: Data?
        var lastRequestError: Error?
        for endpoint in baseURLs {
            guard var endpointComponents = URLComponents(string: endpoint) else { continue }
            endpointComponents.queryItems = queryItems
            guard let endpointURL = endpointComponents.url else { continue }
            var endpointRequest = URLRequest(url: endpointURL)
            endpointRequest.timeoutInterval = 12
            endpointRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            endpointRequest.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
            endpointRequest.setValue("https://music.gdstudio.xyz/", forHTTPHeaderField: "Referer")
            do {
                let (data, response) = try await session.data(for: endpointRequest)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    lastRequestError = MusicSourceError.invalidResponse("搜索 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    continue
                }
                responseData = data
                break
            } catch {
                lastRequestError = error
            }
        }
        guard let data = responseData else {
            throw lastRequestError ?? MusicSourceError.invalidResponse("所有搜索接口均不可用")
        }
        let payload = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        if let array = payload as? [[String: Any]] {
            rows = array
        } else if let root = payload as? [String: Any] {
            rows = (root["data"] as? [[String: Any]])
                ?? (root["result"] as? [[String: Any]])
                ?? ((root["result"] as? [String: Any])?["songs"] as? [[String: Any]])
                ?? ((root["data"] as? [String: Any])?["songs"] as? [[String: Any]])
                ?? ((root["data"] as? [String: Any])?["list"] as? [[String: Any]])
                ?? []
            if rows.isEmpty {
                throw MusicSourceError.invalidResponse("搜索接口返回了非歌曲数据：\(root.keys.sorted().joined(separator: ","))")
            }
        } else {
            throw MusicSourceError.invalidResponse("搜索结果格式无法识别")
        }
        let songs: [MusicSong] = rows.compactMap { (row: [String: Any]) -> MusicSong? in
            guard let id = row["id"] else { return nil }
            let artist: String
            if let names = row["artist"] as? [String] {
                artist = names.joined(separator: " / ")
            } else if let objects = row["artist"] as? [[String: Any]] {
                artist = objects.compactMap { ($0["name"] as? String) ?? ($0["title"] as? String) }.joined(separator: " / ")
            } else if let name = row["artist"] as? String {
                artist = name
            } else if let artistObject = row["artist"] as? [String: Any] {
                artist = (artistObject["name"] as? String) ?? (artistObject["title"] as? String) ?? ""
            } else if let singer = row["singer"] as? [[String: Any]] {
                artist = singer.compactMap { ($0["name"] as? String) ?? ($0["title"] as? String) }.joined(separator: " / ")
            } else if let singer = row["singer"] as? String {
                artist = singer
            } else {
                artist = "未知歌手"
            }
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
        let songlist = body?["songlist"]
        let container = songlist as? [String: Any]
        let rows = container?["list"] as? [[String: Any]]
            ?? songlist as? [[String: Any]]
            ?? (body?["list"] as? [[String: Any]])
            ?? []
        let playlists: [MusicPlaylist] = rows.compactMap { row -> MusicPlaylist? in
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
        guard !playlists.isEmpty else {
            throw MusicSourceError.invalidResponse("QQ音乐没有返回可用歌单")
        }
        await MusicCatalogStore.shared.save(playlists, for: cacheKey, refreshAfter: 7 * 24 * 60 * 60)
        return playlists
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
            throw MusicSourceError.invalidResponse("歌单编号无效")
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
        var seenIDs = Set<String>()
        var seenRecordings = Set<String>()
        let uniqueSongs = songs.filter { song in
            guard seenIDs.insert(song.id).inserted else { return false }
            let title = song.title.lowercased().filter { $0.isLetter || $0.isNumber }
            let artist = song.artist.lowercased().filter { $0.isLetter || $0.isNumber }
            let versionText = "\(song.title) \(song.album ?? "")".lowercased()
            let markers = ["live", "remix", "cover", "dj", "伴奏", "纯音乐", "现场", "翻唱", "acoustic"]
            let version = markers.filter { versionText.contains($0) }.sorted().joined(separator: ",")
            let duration = song.duration.map { String(Int($0.rounded())) } ?? "unknown"
            let key = "\(title)|\(artist)|\(version)|\(duration)"
            return seenRecordings.insert(key).inserted
        }
        guard !uniqueSongs.isEmpty else { throw MusicSourceError.invalidResponse("该歌单暂时没有可用歌曲") }
        let result = Array(uniqueSongs.prefix(count))
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
            "req_0": [
                "module": module,
                "method": method,
                "param": parameters
            ],
            "comm": [
                "format": "json",
                "ct": 24,
                "cv": 0,
                "uin": "0",
                "platform": "yqq.json"
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("QQ 接口 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let service = root["req_0"] as? [String: Any] else {
            throw MusicSourceError.invalidResponse("QQ 接口缺少 req_0 响应节点")
        }
        let topCode = root["code"] as? Int ?? 0
        let moduleCode = service["code"] as? Int ?? 0
        guard topCode == 0, moduleCode == 0,
              let result = service["data"] as? [String: Any] else {
            throw MusicSourceError.invalidResponse("QQ 服务返回错误 top=\(topCode), module=\(moduleCode)")
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
        let endpoints = [
            "https://music.163.com/api/v6/playlist/detail",
            "https://interface.music.163.com/api/v6/playlist/detail"
        ]
        var lastError: Error?
        for endpoint in endpoints {
            guard var components = URLComponents(string: endpoint) else { continue }
            components.queryItems = [URLQueryItem(name: "id", value: playlistID)]
            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    lastError = MusicSourceError.invalidResponse("网易云榜单 HTTP \\((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    continue
                }
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let result = root?["result"] as? [String: Any] ?? root?["playlist"] as? [String: Any]
                guard let rows = result?["tracks"] as? [[String: Any]] else {
                    lastError = MusicSourceError.invalidResponse("网易云没有返回榜单曲目")
                    continue
                }
                let songs: [MusicSong] = rows.prefix(count).compactMap { row -> MusicSong? in
                    guard let id = row["id"] else { return nil }
                    let artists = (row["ar"] as? [[String: Any]] ?? row["artists"] as? [[String: Any]] ?? [])
                        .compactMap { $0["name"] as? String }.joined(separator: " / ")
                    let albumInfo = row["al"] as? [String: Any] ?? row["album"] as? [String: Any] ?? [:]
                    let albumName = albumInfo["name"] as? String
                    let artwork = (albumInfo["picUrl"] as? String).flatMap(URL.init(string:))
                    let duration = (row["dt"] as? Double).map { $0 / 1000 }
                        ?? (row["duration"] as? Double).map { $0 / 1000 }
                    return MusicSong(source: .netease, sourceID: String(describing: id),
                        title: row["name"] as? String ?? "未知歌曲",
                        artist: artists.isEmpty ? "未知歌手" : artists, album: albumName,
                        artworkURL: artwork, duration: duration, hash: nil,
                        albumID: albumInfo["id"].map { String(describing: $0) },
                        pictureID: (albumInfo["pic_str"] ?? albumInfo["pic"]).map { String(describing: $0) },
                        lyricID: String(describing: id))
                }
                guard !songs.isEmpty else {
                    lastError = MusicSourceError.invalidResponse("网易云榜单没有可用歌曲")
                    continue
                }
                let refreshInterval: TimeInterval = chartName == "热歌榜" ? 3 * 24 * 60 * 60 : 24 * 60 * 60
                await MusicCatalogStore.shared.save(songs, for: cacheKey, refreshAfter: refreshInterval)
                return songs
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MusicSourceError.invalidResponse("网易云榜单接口暂时不可用")
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
