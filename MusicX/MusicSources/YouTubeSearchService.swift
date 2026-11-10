import Foundation

/// YouTube WEB InnerTube search adapter. Returns video metadata only.
/// This is an undocumented endpoint and may change without notice.
struct YouTubeSearchService {
    private let session: URLSession
    private let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/search")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(keyword: String, limit: Int = 20) async throws -> [MusicSong] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20261110.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "query": query
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startedAt = Date()
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw MusicSourceError.invalidResponse(
                    "YouTube HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                )
            }
            let object = try JSONSerialization.jsonObject(with: data)
            let results = Array(Self.extractSongs(from: object).prefix(max(1, limit)))
            MusicSourceDiagnostics.shared.record(
                event: "search", source: MusicSource.youtube.rawValue,
                provider: "innertube-web",
                duration: Date().timeIntervalSince(startedAt),
                result: results.isEmpty ? "empty" : "success",
                detail: "count=\(results.count)"
            )
            return results
        } catch {
            MusicSourceDiagnostics.shared.record(
                event: "search", source: MusicSource.youtube.rawValue,
                provider: "innertube-web",
                duration: Date().timeIntervalSince(startedAt),
                result: "failed", detail: error.localizedDescription
            )
            throw error
        }
    }

    private static func extractSongs(from object: Any) -> [MusicSong] {
        var renderers: [[String: Any]] = []
        collectVideoRenderers(in: object, into: &renderers)
        var seen = Set<String>()

        return renderers.compactMap { renderer in
            guard let videoID = renderer["videoId"] as? String,
                  !videoID.isEmpty, seen.insert(videoID).inserted,
                  let title = textValue(renderer["title"]), !title.isEmpty else { return nil }

            let owner = textValue(renderer["ownerText"])
                ?? textValue(renderer["longBylineText"])
                ?? "YouTube"
            let duration = textValue(renderer["lengthText"]).flatMap(seconds(from:))
            let thumbnail = thumbnailURL(in: renderer)

            return MusicSong(
                source: .youtube,
                sourceID: videoID,
                title: title,
                artist: owner,
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

    private static func collectVideoRenderers(in value: Any, into result: inout [[String: Any]]) {
        if let dictionary = value as? [String: Any] {
            if let renderer = dictionary["videoRenderer"] as? [String: Any] {
                result.append(renderer)
            }
            for child in dictionary.values {
                collectVideoRenderers(in: child, into: &result)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectVideoRenderers(in: child, into: &result)
            }
        }
    }

    private static func textValue(_ value: Any?) -> String? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let simple = dictionary["simpleText"] as? String { return simple }
        if let runs = dictionary["runs"] as? [[String: Any]] {
            let result = runs.compactMap { $0["text"] as? String }.joined()
            return result.isEmpty ? nil : result
        }
        return nil
    }

    private static func seconds(from raw: String) -> TimeInterval? {
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reversed().enumerated().reduce(0.0) { total, part in
            total + Double(part.element) * pow(60.0, Double(part.offset))
        }
    }

    private static func thumbnailURL(in renderer: [String: Any]) -> URL? {
        guard let thumbnail = renderer["thumbnail"] as? [String: Any],
              let entries = thumbnail["thumbnails"] as? [[String: Any]] else { return nil }
        for entry in entries.reversed() {
            if let raw = entry["url"] as? String, let url = URL(string: raw),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return url
            }
        }
        return nil
    }
}
