import Foundation
import CryptoKit
import CommonCrypto

/// Direct NetEase Cloud Music API client. This is deliberately separate from
/// GDStudio so native NetEase catalog requests do not depend on a third-party
/// metadata service. The client currently exposes the search endpoint used by
/// MusicX; additional native endpoints can be added here as needed.
struct NetEaseNativeAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Native NetEase eAPI search, following Kumone's cloudsearch request contract.
    func searchNetEase(keyword: String, count: Int = 100, offset: Int = 0) async throws -> [MusicSong] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let limit = min(max(count, 1), 100)
        let cacheKey = "netease-native-search|\(query.lowercased())|\(limit)|\(max(0, offset))"
        if let cached: [MusicSong] = await MusicCache.shared.value(for: cacheKey) { return cached }
        let now = Date().timeIntervalSince1970
        let deviceID = Self.netEaseDeviceID
        let header: [String: Any] = [
            "osver": "iOS 27.0.1", "deviceId": deviceID, "os": "pc",
            "appver": "3.1.17.204416", "versioncode": "140", "mobilename": "",
            "buildver": String(Int(now)), "resolution": "1920x1080", "channel": "netease",
            "requestId": String(format: "%lld_%04d", Int64(now * 1000), Int(now * 1_000_000) % 1000),
            "__csrf": ""
        ]
        let payload: [String: Any] = ["s": query, "type": 1, "limit": limit, "offset": max(0, offset), "total": true, "header": header, "e_r": false]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let apiPath = "/api/cloudsearch/pc"
        let text = String(decoding: json, as: UTF8.self)
        let message = "nobody\(apiPath)use\(text)md5forencrypt"
        let digest = Insecure.MD5.hash(data: Data(message.utf8)).map { String(format: "%02x", $0) }.joined()
        let plain = Data("\(apiPath)-36cd479b6b5-\(text)-36cd479b6b5-\(digest)".utf8)
        let key = Data("e82ckenh8dichen8".utf8)
        var encrypted = Data(count: plain.count + kCCBlockSizeAES128)
        var written = 0
        let status = encrypted.withUnsafeMutableBytes { out in
            plain.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyBytes.baseAddress, key.count, nil, input.baseAddress, plain.count,
                        out.baseAddress, out.count, &written)
                }
            }
        }
        guard status == kCCSuccess else { throw MusicSourceError.invalidResponse("网易云搜索请求加密失败：\(status)") }
        let params = encrypted.prefix(written).map { String(format: "%02X", $0) }.joined()
        let endpoints = ["https://interface.music.163.com/eapi/cloudsearch/pc", "https://music.163.com/eapi/cloudsearch/pc"]
        var lastError: Error?
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.httpBody = Data("params=\(params)".utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)", forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    lastError = MusicSourceError.invalidResponse("网易云搜索 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    continue
                }
                guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (root["code"] as? Int ?? 200) == 200,
                      let result = root["result"] as? [String: Any],
                      let rows = result["songs"] as? [[String: Any]] else {
                    lastError = MusicSourceError.invalidResponse("网易云搜索响应格式或业务状态异常")
                    continue
                }
                let songs: [MusicSong] = rows.compactMap { row in
                    guard let rawID = row["id"] else { return nil }
                    let artists = (row["artists"] as? [[String: Any]] ?? row["ar"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " / ")
                    let album = row["album"] as? [String: Any] ?? row["al"] as? [String: Any] ?? [:]
                    let rawDuration = row["duration"] ?? row["dt"]
                    let duration: TimeInterval? = {
                        if let value = rawDuration as? Double { return value > 1000 ? value / 1000 : value }
                        if let value = rawDuration as? Int { return value > 1000 ? Double(value) / 1000 : Double(value) }
                        return nil
                    }()
                    return MusicSong(source: .netease, sourceID: String(describing: rawID), title: row["name"] as? String ?? "未知歌曲", artist: artists.isEmpty ? "未知歌手" : artists, album: album["name"] as? String, artworkURL: (album["picUrl"] as? String).flatMap(URL.init(string:)), duration: duration, hash: nil, albumID: album["id"].map { String(describing: $0) }, pictureID: nil, lyricID: String(describing: rawID))
                }
                guard !songs.isEmpty else { lastError = MusicSourceError.invalidResponse("网易云没有返回匹配歌曲"); continue }
                await MusicCache.shared.insert(songs, for: cacheKey, ttl: 5 * 60)
                MusicSourceDiagnostics.shared.record(event: "search", source: MusicSource.netease.rawValue, provider: "netease-eapi-cloudsearch", duration: 0, result: "success", detail: "count=\(songs.count)")
                return songs
            } catch { lastError = error }
        }
        MusicSourceDiagnostics.shared.record(event: "search", source: MusicSource.netease.rawValue, provider: "netease-eapi-cloudsearch", duration: 0, result: "failed", detail: lastError?.localizedDescription ?? "unknown")
        throw lastError ?? MusicSourceError.invalidResponse("网易云搜索暂时不可用")
    }

    private static let netEaseDeviceID: String = {
        let key = "musicx.netease.device-id"
        if let stored = UserDefaults.standard.string(forKey: key), stored.count == 52 { return stored }
        let chars = Array("0123456789ABCDEF")
        let generated = String((0..<52).map { _ in chars.randomElement()! })
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }()
}
