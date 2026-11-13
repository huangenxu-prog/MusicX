import Foundation

/// Direct-to-platform collection discovery for Kugou, Kuwo, and Migu.
/// This service only normalizes catalog metadata; playback remains the
/// responsibility of the Resource Engine.
struct DomesticPlaylistDiscoveryService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchPlaylists(keyword: String, count: Int) async throws -> [MusicPlaylist] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, count > 0 else { return [] }
        let limit = min(max(count, 1), 50)
        let cacheKey = "domestic-playlist-search|\(query.lowercased())|\(limit)"
        if let cached = await MusicCatalogStore.shared.snapshot(for: cacheKey, as: [MusicPlaylist].self) {
            if cached.needsRefresh {
                Task { _ = try? await self.refreshPlaylistSearch(keyword: query, count: limit, cacheKey: cacheKey) }
            }
            return cached.value
        }
        return try await refreshPlaylistSearch(keyword: query, count: limit, cacheKey: cacheKey)
    }

    private func refreshPlaylistSearch(keyword: String, count: Int, cacheKey: String) async throws -> [MusicPlaylist] {
        async let kugou = try? searchKugouPlaylists(keyword: keyword, count: count)
        async let kuwo = try? searchKuwoPlaylists(keyword: keyword, count: count)
        async let migu = try? searchMiguPlaylists(keyword: keyword, count: count)
        let groups = await [kugou, kuwo, migu]
        try Task.checkCancellation()
        let sources: [MusicSource] = [.kugou, .kuwo, .migu]
        for (index, result) in groups.enumerated() where result == nil {
            MusicSourceDiagnostics.shared.record(
                event: "playlist-search",
                source: sources[index].rawValue,
                provider: "\(sources[index].rawValue)-playlist-search",
                duration: 0,
                result: "failed",
                detail: "关键词歌单搜索接口不可用"
            )
        }
        let results = groups.compactMap { $0 }.flatMap { $0 }
        guard !results.isEmpty else {
            throw MusicSourceError.invalidResponse("酷狗、酷我和咪咕均未返回匹配歌单")
        }
        await MusicCatalogStore.shared.save(results, for: cacheKey, refreshAfter: 24 * 60 * 60)
        return Array(results.prefix(count))
    }

    private func searchKugouPlaylists(keyword: String, count: Int) async throws -> [MusicPlaylist] {
        var components = URLComponents(string: "https://mobilecdn.kugou.com/api/v3/search/special")
        components?.queryItems = [
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "platform", value: "WebFilter"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: String(min(count, 30))),
            URLQueryItem(name: "filter", value: "0")
        ]
        guard let url = components?.url else { throw MusicSourceError.invalidResponse("酷狗歌单搜索地址无效") }
        let root = try await getJSON(url, referer: "https://www.kugou.com/")
        let data = root["data"] as? [String: Any]
        let rows = data?["info"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let rawID = row["specialid"], let name = row["specialname"] as? String, !name.isEmpty else { return nil }
            let cover = (row["imgurl"] as? String)?.replacingOccurrences(of: "{size}", with: "480")
            return MusicPlaylist(
                source: .kugou,
                sourceID: String(describing: rawID),
                name: name,
                creator: (row["nickname"] as? String) ?? (row["username"] as? String),
                description: row["intro"] as? String,
                artworkURL: cover.flatMap(URL.init(string:)),
                trackCount: integer(row["songcount"]),
                provenance: .searchResult
            )
        }
    }

    private func searchKuwoPlaylists(keyword: String, count: Int) async throws -> [MusicPlaylist] {
        var components = URLComponents(string: "https://search.kuwo.cn/r.s")
        components?.queryItems = [
            URLQueryItem(name: "all", value: keyword),
            URLQueryItem(name: "ft", value: "playlist"),
            URLQueryItem(name: "itemset", value: "web_2013"),
            URLQueryItem(name: "client", value: "kt"),
            URLQueryItem(name: "pcmp4", value: "1"),
            URLQueryItem(name: "geo", value: "c"),
            URLQueryItem(name: "vipver", value: "1"),
            URLQueryItem(name: "pn", value: "0"),
            URLQueryItem(name: "rn", value: String(min(count, 30))),
            URLQueryItem(name: "rformat", value: "json"),
            URLQueryItem(name: "encoding", value: "utf8")
        ]
        guard let url = components?.url else { throw MusicSourceError.invalidResponse("酷我歌单搜索地址无效") }
        let root = try await getJSON(url, referer: "https://www.kuwo.cn/")
        let rows = root["abslist"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let rawID = row["playlistid"] as? String, !rawID.isEmpty,
                  let name = row["name"] as? String, !name.isEmpty else { return nil }
            let rawCover = row["pic"] as? String
            let cover = rawCover.map { value -> String in
                let normalized = value.replacingOccurrences(of: "_150.", with: "_700.")
                return normalized.hasPrefix("http") ? normalized : "https://" + normalized
            }
            return MusicPlaylist(
                source: .kuwo,
                sourceID: rawID,
                name: name,
                creator: row["nickname"] as? String,
                description: row["intro"] as? String,
                artworkURL: cover.flatMap(URL.init(string:)),
                trackCount: integer(row["songnum"]),
                provenance: .searchResult
            )
        }
    }

    private func searchMiguPlaylists(keyword: String, count: Int) async throws -> [MusicPlaylist] {
        var components = URLComponents(string: "https://pd.musicapp.migu.cn/MIGUM2.0/v1.0/content/search_all.do")
        components?.queryItems = [
            URLQueryItem(name: "ua", value: "Android_migu"),
            URLQueryItem(name: "version", value: "5.0.1"),
            URLQueryItem(name: "text", value: keyword),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "pageSize", value: String(min(count, 30))),
            URLQueryItem(name: "searchSwitch", value: #"{"song":0,"album":0,"singer":0,"tagSong":0,"mvSong":0,"songlist":1,"bestShow":1}"#)
        ]
        guard let url = components?.url else { throw MusicSourceError.invalidResponse("咪咕歌单搜索地址无效") }
        let root = try await getJSON(url, referer: "https://music.migu.cn/")
        let resultData = root["songListResultData"] as? [String: Any]
        let rows = resultData?["result"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let rawID = row["id"] as? String, !rawID.isEmpty,
                  let name = row["name"] as? String, !name.isEmpty else { return nil }
            let artwork = (row["musicListPicUrl"] as? String)
                ?? ((row["imgItems"] as? [[String: Any]])?.compactMap { $0["img"] as? String }.first)
            return MusicPlaylist(
                source: .migu,
                sourceID: rawID,
                name: name,
                creator: (row["userName"] as? String) ?? (row["ownerName"] as? String),
                description: row["description"] as? String,
                artworkURL: artwork.flatMap(URL.init(string:)),
                trackCount: integer(row["musicNum"]),
                provenance: .searchResult
            )
        }
    }

    func featuredPlaylists(count: Int = 30) async throws -> [MusicPlaylist] {
        let limit = min(max(count, 1), 60)
        async let kugou = recommendedKugou(count: limit)
        async let kuwo = recommendedKuwo(count: limit)
        async let migu = categoryFeaturedMigu(count: min(limit, 18))
        let groups = await [try? kugou, try? kuwo, try? migu]
        try Task.checkCancellation()
        let sources: [MusicSource] = [.kugou, .kuwo, .migu]
        for (index, result) in groups.enumerated() where result == nil {
            MusicSourceDiagnostics.shared.record(
                event: "playlist-discovery",
                source: sources[index].rawValue,
                provider: "\(sources[index].rawValue)-playlist-feed",
                duration: 0,
                result: "failed",
                detail: "平台推荐/分类歌单接口未返回有效结果"
            )
        }
        let results = groups.compactMap { $0 }.flatMap { $0 }
        guard !results.isEmpty else {
            throw MusicSourceError.invalidResponse("酷狗、酷我和咪咕暂时均未返回可用歌单")
        }
        return results
    }

    func playlistTracks(playlistID: String, source: MusicSource, count: Int) async throws -> [MusicSong] {
        let id = playlistID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, count > 0 else {
            throw MusicSourceError.invalidResponse("歌单编号或曲目数量无效")
        }
        let cacheKey = "domestic-playlist-tracks|\(source.rawValue)|\(id)|\(count)"
        if let cached: [MusicSong] = await MusicCache.shared.value(for: cacheKey) {
            return cached
        }
        let tracks: [MusicSong]
        switch source {
        case .kugou:
            tracks = try await kugouPlaylistTracks(id: id, count: count)
        case .kuwo:
            tracks = try await kuwoPlaylistTracks(id: id, count: count)
        case .migu:
            tracks = try await miguPlaylistTracks(id: id, count: count)
        default:
            throw MusicSourceError.unsupportedSource(source)
        }
        await MusicCache.shared.insert(tracks, for: cacheKey, ttl: 10 * 60)
        return tracks
    }

    private func kugouPlaylistTracks(id: String, count: Int) async throws -> [MusicSong] {
        var components = URLComponents(string: "https://mobilecdn.kugou.com/api/v3/special/song")
        components?.queryItems = [
            URLQueryItem(name: "specialid", value: id),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: String(min(count, 300))),
            URLQueryItem(name: "version", value: "9108"),
            URLQueryItem(name: "area_code", value: "1")
        ]
        guard let url = components?.url else { throw MusicSourceError.invalidResponse("酷狗歌单详情地址无效") }
        let root = try await getJSON(url, referer: "https://www.kugou.com/")
        let data = root["data"] as? [String: Any]
        let rows = data?["info"] as? [[String: Any]] ?? []
        let songs: [MusicSong] = rows.compactMap { row in
            let hash = (row["hash"] as? String)
                ?? (row["SQFileHash"] as? String)
                ?? (row["HQFileHash"] as? String)
                ?? ""
            guard !hash.isEmpty else { return nil }
            let fileName = row["filename"] as? String ?? ""
            let parsed = fileName.components(separatedBy: " - ")
            let artist = (row["singername"] as? String)
                ?? (parsed.count > 1 ? parsed[0] : "未知歌手")
            let title = (row["songname"] as? String)
                ?? (parsed.count > 1 ? parsed.dropFirst().joined(separator: " - ") : fileName)
            let trans = row["trans_param"] as? [String: Any]
            let cover = trans?["union_cover"] as? String
            return MusicSong(
                source: .kugou,
                sourceID: hash,
                title: title.isEmpty ? "未知歌曲" : title,
                artist: artist.isEmpty ? "未知歌手" : artist,
                album: row["album_name"] as? String,
                artworkURL: cover.flatMap { URL(string: $0.replacingOccurrences(of: "{size}", with: "480")) },
                duration: (row["duration"] as? Double) ?? (row["duration"] as? Int).map(Double.init),
                hash: hash,
                albumID: row["AlbumID"] as? String,
                pictureID: nil,
                lyricID: hash
            )
        }
        guard !songs.isEmpty else { throw MusicSourceError.invalidResponse("酷狗歌单没有返回有效歌曲") }
        return Array(songs.prefix(count))
    }

    private func kuwoPlaylistTracks(id: String, count: Int) async throws -> [MusicSong] {
        var components = URLComponents(string: "https://nplserver.kuwo.cn/pl.svc")
        components?.queryItems = [
            URLQueryItem(name: "op", value: "getlistinfo"),
            URLQueryItem(name: "pid", value: id),
            URLQueryItem(name: "pn", value: "0"),
            URLQueryItem(name: "rn", value: String(min(count, 100))),
            URLQueryItem(name: "encode", value: "utf8"),
            URLQueryItem(name: "keyset", value: "pl2012"),
            URLQueryItem(name: "identity", value: "kuwo"),
            URLQueryItem(name: "pcmp4", value: "1"),
            URLQueryItem(name: "vipver", value: "1"),
            URLQueryItem(name: "newver", value: "1")
        ]
        guard let url = components?.url else { throw MusicSourceError.invalidResponse("酷我歌单详情地址无效") }
        let root = try await getJSON(url, referer: "https://www.kuwo.cn/")
        let rows = root["musicList"] as? [[String: Any]] ?? []
        let songs: [MusicSong] = rows.compactMap { row in
            guard let rawID = row["id"] else { return nil }
            let title = (row["name"] as? String) ?? (row["songName"] as? String) ?? ""
            guard !title.isEmpty else { return nil }
            let artist = (row["artist"] as? String) ?? (row["artistName"] as? String) ?? "未知歌手"
            let duration: TimeInterval? = {
                if let value = row["duration"] as? Double { return value }
                if let value = row["duration"] as? String, let parsed = Double(value) { return parsed }
                return nil
            }()
            let artwork = (row["albumPic"] as? String).map { $0.hasPrefix("http") ? $0 : "https://" + $0 }
            return MusicSong(
                source: .kuwo,
                sourceID: String(describing: rawID),
                title: title,
                artist: artist,
                album: row["album"] as? String,
                artworkURL: artwork.flatMap(URL.init(string:)),
                duration: duration,
                hash: nil,
                albumID: nil,
                pictureID: nil,
                lyricID: String(describing: rawID)
            )
        }
        guard !songs.isEmpty else { throw MusicSourceError.invalidResponse("酷我歌单没有返回有效歌曲") }
        return Array(songs.prefix(count))
    }

    private func miguPlaylistTracks(id: String, count: Int) async throws -> [MusicSong] {
        var components = URLComponents(string: "https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0")
        components?.queryItems = [
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "pageSize", value: String(min(count, 100))),
            URLQueryItem(name: "playlistId", value: id)
        ]
        guard let url = components?.url else { throw MusicSourceError.invalidResponse("咪咕歌单详情地址无效") }
        let root = try await getJSON(url, referer: "https://music.migu.cn/")
        if let code = root["code"] as? String, !code.isEmpty, code != "000000" {
            throw MusicSourceError.invalidResponse("咪咕歌单详情业务状态异常：\(code)")
        }
        let data = root["data"] as? [String: Any]
        let rows = data?["songList"] as? [[String: Any]] ?? []
        let songs: [MusicSong] = rows.compactMap { row in
            let contentID = (row["contentId"] as? String)
                ?? (row["copyrightId"] as? String)
                ?? (row["songId"] as? String)
                ?? (row["id"] as? String)
            guard let contentID, !contentID.isEmpty else { return nil }
            // Keep the platform's canonical content ID intact. The shared
            // GDStudio Migu resolver accepts the raw content ID; appending
            // quality/resource fields would turn it into an invalid song ID.
            let sourceID = contentID
            let title = (row["name"] as? String) ?? (row["songName"] as? String) ?? ""
            guard !title.isEmpty else { return nil }
            let artists = (row["singers"] as? [[String: Any]]
                ?? row["artists"] as? [[String: Any]]
                ?? row["singerList"] as? [[String: Any]]
                ?? [])
                .compactMap { $0["name"] as? String }
            let artist = artists.isEmpty ? ((row["singer"] as? String) ?? "未知歌手") : artists.joined(separator: " / ")
            let albums = row["albums"] as? [[String: Any]] ?? []
            let album = (albums.first?["name"] as? String) ?? (row["album"] as? String)
            let images = row["imgItems"] as? [[String: Any]] ?? []
            let artwork = images.compactMap { $0["img"] as? String }.first
            let duration = (row["duration"] as? Double) ?? (row["duration"] as? Int).map(Double.init)
            return MusicSong(
                source: .migu,
                sourceID: sourceID,
                title: title,
                artist: artist,
                album: album,
                artworkURL: artwork.flatMap(URL.init(string:)),
                duration: duration,
                hash: nil,
                albumID: row["albumId"] as? String,
                pictureID: nil,
                lyricID: contentID,
                copyrightID: (row["copyrightId"] as? String)
                    ?? (row["copyrightId"] as? NSNumber)?.stringValue
            )
        }
        guard !songs.isEmpty else { throw MusicSourceError.invalidResponse("咪咕歌单没有返回有效歌曲") }
        return Array(songs.prefix(count))
    }

    private func recommendedKugou(count: Int) async throws -> [MusicPlaylist] {
        let cacheKey = "kugou-platform-recommended-playlists|\(count)"
        if let cached = await MusicCatalogStore.shared.snapshot(for: cacheKey, as: [MusicPlaylist].self) {
            if cached.needsRefresh {
                Task { _ = try? await self.refreshKugou(count: count, cacheKey: cacheKey) }
            }
            return cached.value
        }
        return try await refreshKugou(count: count, cacheKey: cacheKey)
    }

    private func refreshKugou(count: Int, cacheKey: String) async throws -> [MusicPlaylist] {
        guard let url = URL(string: "https://m.kugou.com/plist/index?json=true&page=1") else {
            throw MusicSourceError.invalidResponse("酷狗推荐接口地址无效")
        }
        let root = try await getJSON(url, referer: "https://www.kugou.com/")
        let plist = root["plist"] as? [String: Any]
        let list = plist?["list"] as? [String: Any]
        let rows = list?["info"] as? [[String: Any]] ?? []
        let playlists: [MusicPlaylist] = rows.compactMap { row in
            guard let rawID = row["specialid"], let name = row["specialname"] as? String, !name.isEmpty else { return nil }
            let rawCover = row["imgurl"] as? String
            let cover = rawCover?.replacingOccurrences(of: "{size}", with: "480")
            return MusicPlaylist(
                source: .kugou,
                sourceID: String(describing: rawID),
                name: name,
                creator: (row["username"] as? String) ?? (row["nickname"] as? String),
                description: row["intro"] as? String,
                artworkURL: cover.flatMap(URL.init(string:)),
                trackCount: integer(row["songcount"]),
                provenance: .platformRecommended
            )
        }
        guard !playlists.isEmpty else {
            throw MusicSourceError.invalidResponse("酷狗推荐接口没有返回有效歌单")
        }
        await MusicCatalogStore.shared.save(playlists, for: cacheKey, refreshAfter: 6 * 60 * 60)
        return Array(playlists.prefix(count))
    }

    private func recommendedKuwo(count: Int) async throws -> [MusicPlaylist] {
        let cacheKey = "kuwo-platform-recommended-playlists|\(count)"
        if let cached = await MusicCatalogStore.shared.snapshot(for: cacheKey, as: [MusicPlaylist].self) {
            if cached.needsRefresh {
                Task { _ = try? await self.refreshKuwo(count: count, cacheKey: cacheKey) }
            }
            return cached.value
        }
        return try await refreshKuwo(count: count, cacheKey: cacheKey)
    }

    private func refreshKuwo(count: Int, cacheKey: String) async throws -> [MusicPlaylist] {
        var components = URLComponents(string: "https://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList")
        components?.queryItems = [
            URLQueryItem(name: "pn", value: "0"),
            URLQueryItem(name: "rn", value: String(count)),
            URLQueryItem(name: "order", value: "hot")
        ]
        guard let url = components?.url else {
            throw MusicSourceError.invalidResponse("酷我推荐接口地址无效")
        }
        let root = try await getJSON(url, referer: "https://www.kuwo.cn/")
        guard integer(root["code"]) == 200 else {
            throw MusicSourceError.invalidResponse("酷我推荐接口业务状态异常")
        }
        let data = root["data"] as? [String: Any]
        let rows = data?["data"] as? [[String: Any]] ?? []
        let playlists: [MusicPlaylist] = rows.compactMap { row in
            guard let rawID = row["id"], let name = row["name"] as? String, !name.isEmpty else { return nil }
            let rawCover = row["img"] as? String
            let cover = rawCover.map { $0.hasPrefix("http") ? $0 : "https://" + $0 }
            let trackCount = integer(row["songnum"]) ?? integer(row["total"]) ?? integer(row["count"])
            return MusicPlaylist(
                source: .kuwo,
                sourceID: String(describing: rawID),
                name: name,
                creator: row["uname"] as? String,
                description: row["desc"] as? String,
                artworkURL: cover.flatMap(URL.init(string:)),
                trackCount: trackCount,
                provenance: .platformRecommended
            )
        }
        guard !playlists.isEmpty else {
            throw MusicSourceError.invalidResponse("酷我推荐接口没有返回有效歌单")
        }
        await MusicCatalogStore.shared.save(playlists, for: cacheKey, refreshAfter: 6 * 60 * 60)
        return Array(playlists.prefix(count))
    }

    /// Migu does not expose the same public hot-recommend playlist feed as the
    /// other platforms in the currently verified adapter set. Use its category
    /// search endpoint and label the result as category content, never editorial.
    private func categoryFeaturedMigu(count: Int) async throws -> [MusicPlaylist] {
        let cacheKey = "migu-category-featured-playlists|\(count)"
        if let cached = await MusicCatalogStore.shared.snapshot(for: cacheKey, as: [MusicPlaylist].self) {
            if cached.needsRefresh {
                Task { _ = try? await self.refreshMigu(count: count, cacheKey: cacheKey) }
            }
            return cached.value
        }
        return try await refreshMigu(count: count, cacheKey: cacheKey)
    }

    private func refreshMigu(count: Int, cacheKey: String) async throws -> [MusicPlaylist] {
        let perCategory = max(2, Int(ceil(Double(count) / 4.0)))
        async let chinese = try? miguCategoryPlaylists("华语", count: perCategory)
        async let western = try? miguCategoryPlaylists("欧美", count: perCategory)
        async let soundtrack = try? miguCategoryPlaylists("影视", count: perCategory)
        async let light = try? miguCategoryPlaylists("轻音乐", count: perCategory)
        let groups = await [chinese, western, soundtrack, light]
        try Task.checkCancellation()
        let collected = groups.compactMap { $0 }.flatMap { $0 }
        var seen = Set<String>()
        let unique = collected.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else {
            throw MusicSourceError.invalidResponse("咪咕分类歌单接口没有返回有效内容")
        }
        await MusicCatalogStore.shared.save(unique, for: cacheKey, refreshAfter: 12 * 60 * 60)
        return Array(unique.prefix(count))
    }

    private func miguCategoryPlaylists(_ category: String, count: Int) async throws -> [MusicPlaylist] {
        var components = URLComponents(string: "https://pd.musicapp.migu.cn/MIGUM2.0/v1.0/content/search_all.do")
        components?.queryItems = [
            URLQueryItem(name: "ua", value: "Android_migu"),
            URLQueryItem(name: "version", value: "5.0.1"),
            URLQueryItem(name: "text", value: category),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "pageSize", value: String(count)),
            URLQueryItem(name: "searchSwitch", value: #"{"song":0,"album":0,"singer":0,"tagSong":0,"mvSong":0,"songlist":1,"bestShow":1}"#)
        ]
        guard let url = components?.url else {
            throw MusicSourceError.invalidResponse("咪咕分类歌单接口地址无效")
        }
        let root = try await getJSON(url, referer: "https://music.migu.cn/")
        let resultData = root["songListResultData"] as? [String: Any]
        let rows = resultData?["result"] as? [[String: Any]] ?? []
        let playlists: [MusicPlaylist] = rows.compactMap { row in
            guard let rawID = row["id"] as? String, !rawID.isEmpty,
                  let name = row["name"] as? String, !name.isEmpty else { return nil }
            let artwork = (row["musicListPicUrl"] as? String)
                ?? ((row["imgItems"] as? [[String: Any]])?.compactMap { $0["img"] as? String }.first)
            return MusicPlaylist(
                source: .migu,
                sourceID: rawID,
                name: name,
                creator: (row["userName"] as? String) ?? (row["ownerName"] as? String),
                description: category,
                artworkURL: artwork.flatMap(URL.init(string:)),
                trackCount: integer(row["musicNum"]),
                provenance: .categoryFeatured
            )
        }
        return playlists
    }

    private func getJSON(_ url: URL, referer: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 14
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("歌单接口 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusicSourceError.invalidResponse("歌单接口返回非 JSON 对象")
        }
        return root
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        if let value = value as? Double { return Int(value) }
        return nil
    }
}
