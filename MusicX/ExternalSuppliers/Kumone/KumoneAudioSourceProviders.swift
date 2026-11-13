import CryptoKit
import Foundation

// Adapted from missuo/kumone:
// Sources/Kumone/Core/Player/UnblockService.swift
// Sources/Kumone/Core/Player/KuwoAudioSourceProvider.swift
// Copyright and license: see THIRD_PARTY_NOTICES.md and LICENSES/Kumone-LGPL-3.0.txt.
// Upstream: https://github.com/missuo/kumone

/// Isolated transport for the Kumone-derived fallback providers.
/// Matches Kumone's 10-second request/resource timeout and cookie-free session.
private enum KumoneAudioSourceTransport {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()

    static func data(from url: URL, userAgent: String = "Mozilla/5.0") async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw MusicSourceError.invalidResponse("Kumone 音源返回了非 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("Kumone 音源 HTTP \(http.statusCode)")
        }
        return data
    }

    static func httpURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

/// Kumone pyncmd adapter. The upstream pyncmd path accepts the original
/// NetEase song ID; other catalog IDs must never be sent to this endpoint.
struct KumonePyncmdAudioSourceProvider: MusicResourceProvider {
    let identifier = "kumone-pyncmd"
    let displayName = "Kumone · pyncmd"

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        guard song.source == .netease,
              let songID = Int64(song.sourceID), songID > 0 else {
            return nil
        }
        try Task.checkCancellation()

        var components = URLComponents(string: "https://music-api.gdstudio.xyz/api.php")
        components?.queryItems = [
            URLQueryItem(name: "types", value: "url"),
            URLQueryItem(name: "source", value: "netease"),
            URLQueryItem(name: "id", value: String(songID)),
            URLQueryItem(name: "br", value: quality.gdstudioBitrate)
        ]
        guard let url = components?.url else {
            throw MusicSourceError.invalidResponse("pyncmd 请求地址无效")
        }

        let data = try await KumoneAudioSourceTransport.data(from: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusicSourceError.invalidResponse("pyncmd 响应格式错误")
        }
        let bitrate = (object["br"] as? Int)
            ?? (object["br"] as? String).flatMap(Int.init)
            ?? (object["br"] as? NSNumber)?.intValue
        guard let bitrate, bitrate > 0 else {
            throw MusicSourceError.invalidResponse("pyncmd 未返回有效码率")
        }
        guard let rawURL = object["url"] as? String,
              let streamURL = KumoneAudioSourceTransport.httpURL(
                rawURL.replacingOccurrences(of: "http://", with: "https://")
              ) else {
            throw MusicSourceError.invalidResponse("pyncmd 未返回有效播放地址")
        }

        return ResolvedMusicResource(
            url: streamURL,
            providerID: identifier,
            providerName: displayName
        )
    }
}

/// Kumone's native Kuwo search -> strict metadata match -> stream URL flow.
struct KumoneKuwoAudioSourceProvider: MusicResourceProvider {
    let identifier = "kumone-kuwo"
    let displayName = "Kumone · 酷我"

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        try Task.checkCancellation()
        let keyword = "\(song.title) \(song.artist)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return nil }

        var searchComponents = URLComponents(string: "https://search.kuwo.cn/r.s")
        searchComponents?.queryItems = [
            URLQueryItem(name: "correct", value: "1"),
            URLQueryItem(name: "vipver", value: "1"),
            URLQueryItem(name: "stype", value: "comprehensive"),
            URLQueryItem(name: "encoding", value: "utf8"),
            URLQueryItem(name: "rformat", value: "json"),
            URLQueryItem(name: "mobi", value: "1"),
            URLQueryItem(name: "show_copyright_off", value: "1"),
            URLQueryItem(name: "searchapi", value: "6"),
            URLQueryItem(name: "all", value: keyword)
        ]
        guard let searchURL = searchComponents?.url else {
            throw MusicSourceError.invalidResponse("酷我搜索地址无效")
        }

        let data = try await KumoneAudioSourceTransport.data(from: searchURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]],
              content.count >= 2,
              let musicPage = content[1]["musicpage"] as? [String: Any],
              let rows = musicPage["abslist"] as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("酷我搜索响应格式错误")
        }

        struct Candidate {
            let rid: String
        }
        let candidates: [Candidate] = rows.prefix(5).compactMap { item in
            guard let musicRID = item["MUSICRID"] as? String,
                  let rid = musicRID.components(separatedBy: "_").last,
                  !rid.isEmpty,
                  let title = item["SONGNAME"] as? String,
                  let artist = item["ARTIST"] as? String else {
                return nil
            }
            let durationValue = item["DURATION"]
            let durationSeconds = (durationValue as? String).flatMap(Int.init)
                ?? (durationValue as? Int)
                ?? (durationValue as? NSNumber)?.intValue
                ?? 0
            guard AudioSourceTrackMatcher.matches(
                original: song,
                candidateTitle: title,
                candidateArtist: artist,
                candidateDuration: durationSeconds > 0 ? TimeInterval(durationSeconds) : nil,
                candidateAlbum: item["ALBUM"] as? String
            ) else {
                return nil
            }
            return Candidate(rid: rid)
        }

        guard let candidate = candidates.first else { return nil }
        var convertComponents = URLComponents(string: "https://antiserver.kuwo.cn/anti.s")
        convertComponents?.queryItems = [
            URLQueryItem(name: "type", value: "convert_url"),
            URLQueryItem(name: "format", value: "mp3"),
            URLQueryItem(name: "response", value: "url"),
            URLQueryItem(name: "rid", value: "MUSIC_\(candidate.rid)")
        ]
        guard let convertURL = convertComponents?.url else {
            throw MusicSourceError.invalidResponse("酷我播放地址请求无效")
        }

        let body = try await KumoneAudioSourceTransport.data(
            from: convertURL,
            userAgent: "okhttp/3.10.0"
        )
        guard let responseText = String(data: body, encoding: .utf8),
              let range = responseText.range(
                of: #"https?://[^\\s$"]+"#,
                options: .regularExpression
              ),
              let streamURL = KumoneAudioSourceTransport.httpURL(String(responseText[range])) else {
            throw MusicSourceError.invalidResponse("酷我没有返回有效播放地址")
        }

        return ResolvedMusicResource(
            url: streamURL,
            providerID: identifier,
            providerName: displayName
        )
    }
}
