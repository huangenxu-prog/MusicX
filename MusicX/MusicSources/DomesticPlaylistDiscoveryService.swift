import Foundation

/// Direct-to-platform collection discovery for Kugou, Kuwo, and Migu.
/// This service only normalizes catalog metadata; playback remains the
/// responsibility of the Resource Engine.
struct DomesticPlaylistDiscoveryService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func featuredPlaylists(count: Int = 30) async throws -> [MusicPlaylist] {
        let limit = min(max(count, 1), 60)
        async let kugou = recommendedKugou(count: limit)
        async let kuwo = recommendedKuwo(count: limit)
        async let migu = categoryFeaturedMigu(count: min(limit, 18))
        let groups = await [try? kugou, try? kuwo, try? migu]
        try Task.checkCancellation()
        let results = groups.compactMap { $0 }.flatMap { $0 }
        guard !results.isEmpty else {
            throw MusicSourceError.invalidResponse("酷狗、酷我和咪咕暂时均未返回可用歌单")
        }
        return results
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
        guard let url = URL(string: "https://m.kugou.com/plist/index&json=true") else {
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
        let categories = ["华语", "欧美", "摇滚", "影视", "轻音乐", "治愈"]
        let perCategory = max(2, Int(ceil(Double(count) / Double(categories.count))))
        var collected: [MusicPlaylist] = []
        for category in categories {
            try Task.checkCancellation()
            var components = URLComponents(string: "https://pd.musicapp.migu.cn/MIGUM2.0/v1.0/content/search_all.do")
            components?.queryItems = [
                URLQueryItem(name: "ua", value: "Android_migu"),
                URLQueryItem(name: "version", value: "5.0.1"),
                URLQueryItem(name: "text", value: category),
                URLQueryItem(name: "pageNo", value: "1"),
                URLQueryItem(name: "pageSize", value: String(perCategory)),
                URLQueryItem(name: "searchSwitch", value: #"{"song":0,"album":0,"singer":0,"tagSong":0,"mvSong":0,"songlist":1,"bestShow":1}"#)
            ]
            guard let url = components?.url else { continue }
            let root: [String: Any]
            do {
                root = try await getJSON(url, referer: "https://music.migu.cn/")
            } catch {
                if Task.isCancelled { throw CancellationError() }
                continue
            }
            let resultData = root["songListResultData"] as? [String: Any]
            let rows = resultData?["result"] as? [[String: Any]] ?? []
            let items: [MusicPlaylist] = rows.compactMap { row in
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
            collected.append(contentsOf: items)
        }
        var seen = Set<String>()
        let unique = collected.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else {
            throw MusicSourceError.invalidResponse("咪咕分类歌单接口没有返回有效内容")
        }
        await MusicCatalogStore.shared.save(unique, for: cacheKey, refreshAfter: 12 * 60 * 60)
        return Array(unique.prefix(count))
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
