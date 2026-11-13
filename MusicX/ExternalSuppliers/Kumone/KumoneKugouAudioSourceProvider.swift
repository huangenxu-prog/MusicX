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

        var searchComponents = URLComponents(string: "https://mobilecdn.kugou.com/api/v3/search/song")
        searchComponents?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "keyword", value: "\(song.title) \(song.artist)"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: "20")
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

        let candidates: [Candidate] = rows.prefix(20).compactMap { row in
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

        // A search response can contain several exact metadata matches, while
        // some hashes may no longer have a licensed stream. Try a small ranked
        // set instead of abandoning Kugou after the first unavailable hash.
        for candidate in candidates.prefix(3) {
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
            guard let streamURL = streamComponents?.url else { continue }

            var streamRequest = URLRequest(url: streamURL)
            streamRequest.timeoutInterval = 10
            streamRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            let (streamData, streamResponse) = try await session.data(for: streamRequest)
            try Task.checkCancellation()
            guard let streamHTTP = streamResponse as? HTTPURLResponse else {
                continue
            }
            if (500..<600).contains(streamHTTP.statusCode) || streamHTTP.statusCode == 429 {
                throw MusicSourceError.invalidResponse("Kugou stream HTTP \\(streamHTTP.statusCode)")
            }
            guard (200..<300).contains(streamHTTP.statusCode) else { continue }

            guard let object = try? JSONSerialization.jsonObject(with: streamData) as? [String: Any] else {
                continue
            }
            let rawURLs: [String]
            if let values = object["url"] as? [String] {
                rawURLs = values
            } else if let value = object["url"] as? String {
                rawURLs = [value]
            } else {
                rawURLs = []
            }

            if let url = rawURLs
                .compactMap({ URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) })
                .first(where: Self.isHTTPURL) {
                return ResolvedMusicResource(url: url, providerID: identifier, providerName: displayName)
            }
        }

        return nil
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
