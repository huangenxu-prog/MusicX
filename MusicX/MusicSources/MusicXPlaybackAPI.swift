import Foundation

/// Optional VPS-assisted playback resolution. The local resolver remains the primary
/// path; this client is used only when the VPS base URL is configured with HTTPS.
struct MusicXPlaybackAPI {
    struct Resolution: Decodable {
        let url: URL?
        let resolvedSource: String?
        let trackID: String?
        let trackMID: String?
        let fallback: Bool?

        private enum CodingKeys: String, CodingKey {
            case url
            case resolvedSource = "resolved_source"
            case source
            case trackID = "track_id"
            case id
            case trackMID = "track_mid"
            case mid
            case fallback
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            url = try values.decodeIfPresent(URL.self, forKey: .url)
            resolvedSource = try values.decodeIfPresent(String.self, forKey: .resolvedSource)
                ?? values.decodeIfPresent(String.self, forKey: .source)
            func stringValue(_ keys: [CodingKeys]) -> String? {
                for key in keys {
                    if let value = try? values.decode(String.self, forKey: key) { return value }
                    if let value = try? values.decode(Int.self, forKey: key) { return String(value) }
                }
                return nil
            }
            trackID = stringValue([.trackID, .id])
            trackMID = stringValue([.trackMID, .mid])
            fallback = try values.decodeIfPresent(Bool.self, forKey: .fallback)
        }
    }

    enum APIError: LocalizedError {
        case notConfigured
        case invalidBaseURL
        case invalidResponse
        case noPlayableURL

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "MusicX VPS 尚未配置 HTTPS 地址"
            case .invalidBaseURL: return "MusicX VPS 地址无效，必须使用 HTTPS"
            case .invalidResponse: return "MusicX VPS 返回数据格式错误"
            case .noPlayableURL: return "MusicX VPS 未返回可播放地址"
            }
        }
    }

    private struct SongPayload: Encodable {
        let title: String
        let artists: [String]
        let sources: [String: [String: String]]

        init(song: MusicSong) {
            title = song.title
            artists = song.artist
                .split(whereSeparator: { $0 == "/" || $0 == "、" || $0 == "," || $0 == "，" })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            switch song.source {
            case .netease:
                sources = ["netease": ["id": song.sourceID]]
            case .qq:
                sources = ["qq": ["mid": song.sourceID]]
            default:
                sources = [:]
            }
        }
    }

    private struct ResolveRequest: Encodable {
        let title: String
        let artists: [String]
        let sources: [String: [String: String]]

        init(song: MusicSong) {
            let payload = SongPayload(song: song)
            title = payload.title
            artists = payload.artists
            sources = payload.sources
        }
    }

    private struct RefreshRequest: Encodable {
        let failedSource: String
        let failedTrackID: String?
        let failedTrackMID: String?
        let song: SongPayload

        enum CodingKeys: String, CodingKey {
            case failedSource = "failed_source"
            case failedTrackID = "failed_track_id"
            case failedTrackMID = "failed_track_mid"
            case song
        }

        init(song: MusicSong, failedSource: String, failedTrackID: String?, failedTrackMID: String?) {
            self.failedSource = failedSource
            self.failedTrackID = failedTrackID
            self.failedTrackMID = failedTrackMID
            self.song = SongPayload(song: song)
        }
    }

    private struct ReportFailureRequest: Encodable {
        let source: String
        let trackID: String?
        let trackMID: String?

        enum CodingKeys: String, CodingKey {
            case source
            case trackID = "track_id"
            case trackMID = "track_mid"
        }
    }

    private struct ResolutionEnvelope: Decodable {
        let success: Bool?
        let result: Resolution?
        let data: Resolution?
    }

    private struct ReportFailureResponse: Decodable {
        let success: Bool
        let cacheInvalidated: Bool
        let source: String
        let trackID: String

        enum CodingKeys: String, CodingKey {
            case success
            case cacheInvalidated = "cache_invalidated"
            case source
            case trackID = "track_id"
        }
    }

    private let session: URLSession
    private let baseURL: URL?

    init(session: URLSession = .shared) {
        self.session = session
        if let raw = Bundle.main.object(forInfoDictionaryKey: "MusicXAPIBaseURL") as? String,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme?.lowercased() == "https",
           url.host != nil {
            baseURL = url
        } else {
            baseURL = nil
        }
    }

    var isConfigured: Bool { baseURL != nil }

    func resolve(song: MusicSong) async throws -> Resolution {
        let request = try makeRequest(path: "/api/v2/playback/resolve", body: ResolveRequest(song: song))
        let data = try await sendData(request)
        let result: Resolution
        if let envelope = try? JSONDecoder().decode(ResolutionEnvelope.self, from: data),
           envelope.result != nil || envelope.data != nil {
            guard envelope.success != false,
                  let nested = envelope.result ?? envelope.data else {
                throw APIError.noPlayableURL
            }
            result = nested
        } else {
            result = try decode(Resolution.self, from: data)
        }
        guard result.url != nil else { throw APIError.noPlayableURL }
        return result
    }

    func reportFailure(source: String, trackID: String? = nil, trackMID: String? = nil) async throws {
        let request = try makeRequest(
            path: "/api/v2/playback/report-failure",
            body: ReportFailureRequest(source: source, trackID: trackID, trackMID: trackMID)
        )
        let response: ReportFailureResponse = try await send(request)
        guard response.success else { throw APIError.invalidResponse }
    }

    func refresh(song: MusicSong, failedSource: String, failedTrackID: String? = nil,
                 failedTrackMID: String? = nil) async throws -> Resolution {
        let request = try makeRequest(
            path: "/api/v2/playback/refresh",
            body: RefreshRequest(
                song: song,
                failedSource: failedSource,
                failedTrackID: failedTrackID,
                failedTrackMID: failedTrackMID
            )
        )
        let data = try await sendData(request)
        let response = try decode(ResolutionEnvelope.self, from: data)
        guard response.success != false,
              let result = response.result ?? response.data,
              result.url != nil else {
            throw APIError.noPlayableURL
        }
        return result
    }

    private func makeRequest<Body: Encodable>(path: String, body: Body) throws -> URLRequest {
        guard let baseURL else {
            throw APIError.notConfigured
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.scheme?.lowercased() == "https" else {
            throw APIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await sendData(request)
        return try decode(Response.self, from: data)
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        return data
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }
}
