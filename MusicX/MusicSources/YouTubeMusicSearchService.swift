import Foundation

/// Search adapter for YouTube Music's WEB_REMIX InnerTube client.
///
/// This adapter intentionally returns metadata only. A search result is not
/// considered playable until a separately validated stream resolver supplies
/// a media URL. InnerTube is an undocumented interface and may change.
struct YouTubeMusicSearchService {
    private let session: URLSession
    private let endpoint = URL(string: "https://music.youtube.com/youtubei/v1/search")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(keyword: String, limit: Int = 20) async throws -> [MusicSong] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20261020.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "query": query,
            "params": "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startedAt = Date()
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw MusicSourceError.invalidResponse(
                    "YouTube Music HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                )
            }
            let object = try JSONSerialization.jsonObject(with: data)
            let songs = Self.extractSongs(from: object).prefix(max(1, limit))
            let result = Array(songs)
            MusicSourceDiagnostics.shared.record(
                event: "search", source: MusicSource.youtubeMusic.rawValue,
                provider: "innertube-web-remix",
                duration: Date().timeIntervalSince(startedAt),
                result: result.isEmpty ? "empty" : "success",
                detail: "count=\(result.count)"
            )
            return result
        } catch {
            MusicSourceDiagnostics.shared.record(
                event: "search", source: MusicSource.youtubeMusic.rawValue,
                provider: "innertube-web-remix",
                duration: Date().timeIntervalSince(startedAt),
                result: "failed", detail: error.localizedDescription
            )
            throw error
        }
    }

    private static func extractSongs(from object: Any) -> [MusicSong] {
        var renderers: [[String: Any]] = []
        collectRenderers(in: object, into: &renderers)
        var seen = Set<String>()

        return renderers.compactMap { renderer in
            guard let endpoint = renderer["navigationEndpoint"] as? [String: Any],
                  let watch = endpoint["watchEndpoint"] as? [String: Any],
                  let videoID = watch["videoId"] as? String,
                  !videoID.isEmpty,
                  seen.insert(videoID).inserted else { return nil }

            let flex = renderer["flexColumns"] as? [[String: Any]] ?? []
            let texts = flex.compactMap { column -> String? in
                let renderer = column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
                return textValue(renderer?["text"])
            }
            guard let title = texts.first, !title.isEmpty else { return nil }

            let subtitle = texts.dropFirst().joined(separator: " ")
            let artist = extractArtist(from: subtitle)
            let thumbnail = thumbnailURL(in: renderer)
            let duration = durationSeconds(in: renderer)

            return MusicSong(
                source: .youtubeMusic,
                sourceID: videoID,
                title: title,
                artist: artist,
                album: nil,
                artworkURL: thumbnail,
                duration: duration,
                hash: nil,
                albumID: nil,
                pictureID: nil,
                lyricID: nil
            )
        }
    }

    private static func collectRenderers(in value: Any, into result: inout [[String: Any]]) {
        if let dictionary = value as? [String: Any] {
            if let renderer = dictionary["musicResponsiveListItemRenderer"] as? [String: Any] {
                result.append(renderer)
            }
            for child in dictionary.values {
                collectRenderers(in: child, into: &result)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectRenderers(in: child, into: &result)
            }
        }
    }

    private static func textValue(_ value: Any?) -> String? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let simple = dictionary["simpleText"] as? String { return simple }
        if let runs = dictionary["runs"] as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func extractArtist(from subtitle: String) -> String {
        let parts = subtitle.components(separatedBy: " • ")
        if parts.count > 1 { return parts[1] }
        return parts.first ?? "YouTube Music"
    }

    private static func thumbnailURL(in renderer: [String: Any]) -> URL? {
        guard let thumbnail = renderer["thumbnail"] as? [String: Any],
              let details = thumbnail["musicThumbnailRenderer"] as? [String: Any],
              let thumbnails = details["thumbnail"] as? [String: Any],
              let entries = thumbnails["thumbnails"] as? [[String: Any]] else { return nil }
        for entry in entries.reversed() {
            if let raw = entry["url"] as? String, let url = URL(string: raw),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return url
            }
        }
        return nil
    }

    private static func durationSeconds(in renderer: [String: Any]) -> TimeInterval? {
        let columns = renderer["fixedColumns"] as? [[String: Any]] ?? []
        for column in columns {
            let item = column["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any]
            guard let raw = textValue(item?["text"]) else { continue }
            let pieces = raw.split(separator: ":").compactMap { Int($0) }
            guard !pieces.isEmpty else { continue }
            return pieces.reversed().enumerated().reduce(0.0) { total, part in
                total + Double(part.element) * pow(60.0, Double(part.offset))
            }
        }
        return nil
    }
}
