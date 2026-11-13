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
