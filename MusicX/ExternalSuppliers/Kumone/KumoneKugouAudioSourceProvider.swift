import CryptoKit
import Foundation

/// Kumone-derived Kugou supplier. Search and stream resolution are kept inside
/// this adapter so the resource engine only sees a normalized playable resource.
struct KumoneKugouAudioSourceProvider: MusicResourceProvider {
    let identifier = "kumone-kugou"
    let displayName = "Kumone · 酷狗"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        try Task.checkCancellation()

        var searchComponents = URLComponents(string: "http://mobilecdn.kugou.com/api/v3/search/song")
        searchComponents?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "keyword", value: "\(song.title) \(song.artist)"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: "10")
        ]
        guard let searchURL = searchComponents?.url else {
            throw MusicSourceError.invalidResponse("酷狗搜索地址无效")
        }

        var searchRequest = URLRequest(url: searchURL)
        searchRequest.timeoutInterval = 10
        searchRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (searchData, searchResponse) = try await session.data(for: searchRequest)
        try Task.checkCancellation()
        guard let http = searchResponse as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse(
                "Kugou search HTTP \((searchResponse as? HTTPURLResponse)?.statusCode ?? -1)"
            )
        }

        guard let root = try JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let data = root["data"] as? [String: Any],
              let rows = data["info"] as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("酷狗搜索响应格式错误")
        }

        let candidates: [Candidate] = rows.prefix(10).compactMap { row in
            guard let hash = row["hash"] as? String, !hash.isEmpty,
                  let title = row["songname"] as? String,
                  let artist = row["singername"] as? String,
                  let duration = Self.integer(row["duration"]) else { return nil }

            let durationSeconds = TimeInterval(duration)
            let album = row["album_name"] as? String
            guard AudioSourceTrackMatcher.matches(
                original: song,
                candidateTitle: title,
                candidateArtist: artist,
                candidateDuration: durationSeconds,
                candidateAlbum: album,
                requireDuration: true
            ) else { return nil }

            let albumID = row["album_id"].map { String(describing: $0) } ?? "0"
            return Candidate(hash: hash, albumID: albumID, duration: durationSeconds)
        }
        .sorted {
            AudioSourceTrackMatcher.durationDifference(original: song, candidateDuration: $0.duration)
                < AudioSourceTrackMatcher.durationDifference(original: song, candidateDuration: $1.duration)
        }

        guard let candidate = candidates.first else { return nil }
        try Task.checkCancellation()

        let key = Insecure.MD5.hash(data: Data("\(candidate.hash)kgcloudv2".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        var streamComponents = URLComponents(string: "https://trackercdn.kugou.com/i/v2/")
        streamComponents?.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "hash", value: candidate.hash),
            URLQueryItem(name: "appid", value: "1005"),
            URLQueryItem(name: "pid", value: "2"),
            URLQueryItem(name: "cmd", value: "25"),
            URLQueryItem(name: "behavior", value: "play"),
            URLQueryItem(name: "album_id", value: candidate.albumID)
        ]
        guard let streamURL = streamComponents?.url else {
            throw MusicSourceError.invalidResponse("酷狗播放地址请求无效")
        }

        var streamRequest = URLRequest(url: streamURL)
        streamRequest.timeoutInterval = 10
        streamRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (streamData, streamResponse) = try await session.data(for: streamRequest)
        try Task.checkCancellation()
        guard let streamHTTP = streamResponse as? HTTPURLResponse,
              (200..<300).contains(streamHTTP.statusCode) else {
            throw MusicSourceError.invalidResponse(
                "Kugou stream HTTP \((streamResponse as? HTTPURLResponse)?.statusCode ?? -1)"
            )
        }

        guard let object = try JSONSerialization.jsonObject(with: streamData) as? [String: Any] else {
            throw MusicSourceError.invalidResponse("酷狗播放响应格式错误")
        }
        let rawURL = (object["url"] as? [String])?.first ?? object["url"] as? String
        guard let rawURL,
              let url = URL(string: rawURL),
              Self.isHTTPURL(url) else {
            throw MusicSourceError.invalidResponse("酷狗没有返回有效播放地址")
        }

        return ResolvedMusicResource(url: url, providerID: identifier, providerName: displayName)
    }

    private struct Candidate {
        let hash: String
        let albumID: String
        let duration: TimeInterval
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return false }
        return true
    }
}
