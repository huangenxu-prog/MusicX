import Foundation
import CryptoKit
import CommonCrypto

/// Direct NetEase Cloud Music eAPI client. Native catalog and playback requests
/// are isolated from GDStudio and other third-party metadata services.
struct NetEaseNativeAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Catalog search

    func search(keyword: String, count: Int = 100, offset: Int = 0) async throws -> [MusicSong] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let limit = min(max(count, 1), 100)
        let normalizedOffset = max(0, offset)
        let cacheKey = "netease-native-search|\(query.lowercased())|\(limit)|\(normalizedOffset)"
        if let cached: [MusicSong] = await MusicCache.shared.value(for: cacheKey) {
            return cached
        }

        let data = try await requestEAPI(
            path: "/cloudsearch/pc",
            payload: [
                "s": query,
                "type": 1,
                "limit": limit,
                "offset": normalizedOffset,
                "total": true
            ]
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? Int ?? 200) == 200,
              let result = root["result"] as? [String: Any],
              let rows = result["songs"] as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("网易云搜索响应格式或业务状态异常")
        }

        let songs: [MusicSong] = rows.compactMap { row in
            guard let rawID = row["id"] else { return nil }
            let artists = (row["artists"] as? [[String: Any]]
                ?? row["ar"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
                .joined(separator: " / ")
            let album = row["album"] as? [String: Any]
                ?? row["al"] as? [String: Any] ?? [:]
            let rawDuration = row["duration"] ?? row["dt"]
            let duration: TimeInterval? = {
                if let value = rawDuration as? Double {
                    return value > 1_000 ? value / 1_000 : value
                }
                if let value = rawDuration as? Int {
                    return value > 1_000 ? Double(value) / 1_000 : Double(value)
                }
                return nil
            }()

            return MusicSong(
                source: .netease,
                sourceID: String(describing: rawID),
                title: row["name"] as? String ?? "未知歌曲",
                artist: artists.isEmpty ? "未知歌手" : artists,
                album: album["name"] as? String,
                artworkURL: (album["picUrl"] as? String).flatMap(URL.init(string:)),
                duration: duration,
                hash: nil,
                albumID: album["id"].map { String(describing: $0) },
                pictureID: nil,
                lyricID: String(describing: rawID)
            )
        }

        guard !songs.isEmpty else {
            throw MusicSourceError.invalidResponse("网易云没有返回匹配歌曲")
        }
        await MusicCache.shared.insert(songs, for: cacheKey, ttl: 5 * 60)
        MusicSourceDiagnostics.shared.record(
            event: "search",
            source: MusicSource.netease.rawValue,
            provider: "netease-eapi-cloudsearch",
            duration: 0,
            result: "success",
            detail: "count=\(songs.count)"
        )
        return songs
    }

    // MARK: - Native playback URL

    /// Resolves a NetEase song ID through the native player URL endpoint.
    /// A nil result means the API answered successfully but did not provide a
    /// complete playable URL (for example, a VIP/trial-only response).
    func playbackURL(songID: String, quality: MusicQuality) async throws -> URL? {
        guard let id = Int(songID), id > 0 else {
            throw MusicSourceError.invalidResponse("网易云歌曲 ID 无效")
        }

        let data = try await requestEAPI(
            path: "/song/enhance/player/url/v1",
            payload: [
                "ids": "[\(id)]",
                "level": quality.neteaseLevel,
                "encodeType": "flac"
            ]
        )

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? Int ?? 200) == 200,
              let rows = root["data"] as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("网易云播放地址响应格式异常")
        }
        guard let item = rows.first else { return nil }

        if let code = item["code"] as? Int, code != 200 {
            return nil
        }
        // Do not mistake a preview/trial URL for a complete song.
        if let trial = item["freeTrialInfo"], !(trial is NSNull) {
            return nil
        }
        guard let rawURL = item["url"] as? String,
              let components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              let url = components.url else {
            return nil
        }
        return url
    }

    // MARK: - Native album search

    func searchAlbums(keyword: String, count: Int = 30, offset: Int = 0) async throws -> [MusicSong] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let limit = min(max(count, 1), 100)
        let normalizedOffset = max(0, offset)
        let cacheKey = "netease-native-album-search|\(query.lowercased())|\(limit)|\(normalizedOffset)"
        if let cached: [MusicSong] = await MusicCache.shared.value(for: cacheKey) {
            return cached
        }

        let data = try await requestEAPI(
            path: "/cloudsearch/pc",
            payload: [
                "s": query,
                "type": 10,
                "limit": limit,
                "offset": normalizedOffset,
                "total": true
            ]
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? Int ?? 200) == 200,
              let result = root["result"] as? [String: Any],
              let rows = result["albums"] as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("网易云专辑搜索响应格式或业务状态异常")
        }

        let albums: [MusicSong] = rows.compactMap { row in
            guard let rawID = row["id"] else { return nil }
            let artists = (row["artists"] as? [[String: Any]]
                ?? row["artist"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
                .joined(separator: " / ")
            let name = row["name"] as? String ?? "未知专辑"
            let artwork = (row["picUrl"] as? String ?? row["blurPicUrl"] as? String)
                .flatMap(URL.init(string:))
            return MusicSong(
                source: .netease,
                sourceID: String(describing: rawID),
                title: name,
                artist: artists.isEmpty ? "未知歌手" : artists,
                album: name,
                artworkURL: artwork,
                duration: nil,
                hash: nil,
                albumID: String(describing: rawID),
                pictureID: row["picId"].map { String(describing: $0) },
                lyricID: nil
            )
        }

        guard !albums.isEmpty else {
            throw MusicSourceError.invalidResponse("网易云没有返回匹配专辑")
        }
        await MusicCache.shared.insert(albums, for: cacheKey, ttl: 5 * 60)
        return albums
    }

    // MARK: - Native lyrics

    func lyrics(songID: String) async throws -> (original: String, translated: String?)? {
        guard let id = Int(songID), id > 0 else {
            throw MusicSourceError.invalidResponse("网易云歌词 ID 无效")
        }

        let versioned = try await requestEAPI(
            path: "/song/lyric/v1",
            payload: [
                "id": id,
                "cp": false,
                "lv": 0,
                "kv": 0,
                "tv": 0,
                "rv": 0,
                "yv": 0,
                "ytv": 0,
                "yrv": 0
            ]
        )
        if let parsed = Self.parseLyrics(versioned) {
            return parsed
        }

        try Task.checkCancellation()
        let classic = try await requestEAPI(
            path: "/song/lyric",
            payload: [
                "id": id,
                "lv": -1,
                "kv": -1,
                "tv": -1,
                "rv": -1
            ]
        )
        return Self.parseLyrics(classic)
    }

    private static func parseLyrics(_ data: Data) -> (original: String, translated: String?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let lrc = root["lrc"] as? [String: Any]
        let original = (lrc?["lyric"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let original, !original.isEmpty else { return nil }
        let tlyric = root["tlyric"] as? [String: Any]
        let translated = (tlyric?["lyric"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (original, translated?.isEmpty == false ? translated : nil)
    }

    // MARK: - Native charts

    func toplist(_ chartName: String, count: Int = 50) async throws -> [MusicSong] {
        let normalizedChart = ["热歌榜", "新歌榜", "飙升榜"].contains(chartName) ? chartName : "热歌榜"
        let limit = min(max(count, 1), 100)
        let cacheKey = "netease-native-chart|\(normalizedChart)|\(limit)"
        if let cached = await MusicCatalogStore.shared.snapshot(for: cacheKey, as: [MusicSong].self) {
            if cached.needsRefresh {
                Task { _ = try? await self.refreshToplist(normalizedChart, count: limit, cacheKey: cacheKey) }
            }
            return cached.value
        }
        return try await refreshToplist(normalizedChart, count: limit, cacheKey: cacheKey)
    }

    private func refreshToplist(
        _ chartName: String,
        count: Int,
        cacheKey: String
    ) async throws -> [MusicSong] {
        let playlistID: Int
        switch chartName {
        case "新歌榜": playlistID = 3779629
        case "飙升榜": playlistID = 19723756
        default: playlistID = 3778678
        }

        let data = try await requestEAPI(
            path: "/v6/playlist/detail",
            payload: ["id": playlistID, "n": 100_000, "s": 8]
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? Int ?? 200) == 200,
              let playlist = root["playlist"] as? [String: Any],
              let rows = playlist["tracks"] as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("网易云榜单详情响应格式异常")
        }

        let songs: [MusicSong] = rows.prefix(count).compactMap { row in
            guard let rawID = row["id"] else { return nil }
            let artists = (row["ar"] as? [[String: Any]]
                ?? row["artists"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
                .joined(separator: " / ")
            let album = row["al"] as? [String: Any]
                ?? row["album"] as? [String: Any] ?? [:]
            let rawDuration = row["dt"] ?? row["duration"]
            let duration: TimeInterval? = {
                if let value = rawDuration as? Double {
                    return value > 1_000 ? value / 1_000 : value
                }
                if let value = rawDuration as? Int {
                    return value > 1_000 ? Double(value) / 1_000 : Double(value)
                }
                return nil
            }()
            return MusicSong(
                source: .netease,
                sourceID: String(describing: rawID),
                title: row["name"] as? String ?? "未知歌曲",
                artist: artists.isEmpty ? "未知歌手" : artists,
                album: album["name"] as? String,
                artworkURL: (album["picUrl"] as? String).flatMap(URL.init(string:)),
                duration: duration,
                hash: nil,
                albumID: album["id"].map { String(describing: $0) },
                pictureID: (album["pic_str"] ?? album["pic"]).map { String(describing: $0) },
                lyricID: String(describing: rawID)
            )
        }

        guard !songs.isEmpty else {
            throw MusicSourceError.invalidResponse("网易云榜单没有可用歌曲")
        }
        let refreshInterval: TimeInterval = chartName == "热歌榜" ? 3 * 24 * 60 * 60 : 24 * 60 * 60
        await MusicCatalogStore.shared.save(songs, for: cacheKey, refreshAfter: refreshInterval)
        return songs
    }

    // MARK: - eAPI transport

    private func requestEAPI(path: String, payload: [String: Any]) async throws -> Data {
        try Task.checkCancellation()
        let now = Date().timeIntervalSince1970
        var body = payload
        body["header"] = [
            "osver": "iOS \(Self.iOSVersion)",
            "deviceId": Self.deviceID,
            "os": "pc",
            "appver": "3.1.17.204416",
            "versioncode": "140",
            "mobilename": "",
            "buildver": String(Int(now)),
            "resolution": "1920x1080",
            "channel": "netease",
            "requestId": String(
                format: "%lld_%04d",
                Int64(now * 1_000),
                Int(now * 1_000_000) % 1_000
            ),
            "__csrf": ""
        ]
        body["e_r"] = false

        let json = try JSONSerialization.data(withJSONObject: body)
        let apiPath = "/api" + path
        let text = String(decoding: json, as: UTF8.self)
        let digestInput = "nobody\(apiPath)use\(text)md5forencrypt"
        let digest = Insecure.MD5.hash(data: Data(digestInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let plaintext = Data(
            "\(apiPath)-36cd479b6b5-\(text)-36cd479b6b5-\(digest)".utf8
        )
        let key = Data("e82ckenh8dichen8".utf8)
        var encrypted = Data(count: plaintext.count + kCCBlockSizeAES128)
        var written = 0
        let status = encrypted.withUnsafeMutableBytes { output in
            plaintext.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        input.baseAddress,
                        plaintext.count,
                        output.baseAddress,
                        output.count,
                        &written
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw MusicSourceError.invalidResponse("网易云 EAPI 加密失败：\(status)")
        }
        let params = encrypted.prefix(written)
            .map { String(format: "%02X", $0) }
            .joined()

        let endpoints = [
            "https://interface.music.163.com/eapi\(path)",
            "https://music.163.com/eapi\(path)"
        ]
        var lastError: Error?
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.httpBody = Data("params=\(params)".utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(
                "NeteaseMusic 9.0.90/5038 (iPhone; iOS \(Self.iOSVersion); zh_CN)",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")

            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    lastError = MusicSourceError.invalidResponse(
                        "网易云 EAPI HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                    )
                    continue
                }
                return data
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
            }
        }

        throw lastError ?? MusicSourceError.invalidResponse("网易云 EAPI 接口暂时不可用")
    }

    private static let iOSVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }()

    private static let deviceID: String = {
        let key = "musicx.netease.device-id"
        if let stored = UserDefaults.standard.string(forKey: key),
           stored.count == 52,
           stored.allSatisfy(\.isHexDigit) {
            return stored
        }
        let characters = Array("0123456789ABCDEF")
        let generated = String((0..<52).map { _ in characters.randomElement()! })
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }()
}
