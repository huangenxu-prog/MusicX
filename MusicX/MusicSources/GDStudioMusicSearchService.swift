import Foundation

struct GDStudioMusicSearchService {
    private let session: URLSession
    private let baseURL = "https://music-api.gdstudio.xyz/api.php"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(keyword: String, source: MusicSource, page: Int = 1, count: Int = 5) async throws -> [MusicSong] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let startedAt = Date()
        var diagnosticResult = "failed"
        var diagnosticCount = 0
        defer {
            MusicSourceDiagnostics.shared.record(
                event: "search", source: source.rawValue, provider: "gdstudio-search",
                duration: Date().timeIntervalSince(startedAt), result: diagnosticResult,
                detail: "count=\(diagnosticCount)"
            )
        }
        guard var components = URLComponents(string: baseURL) else {
            throw MusicSourceError.invalidResponse("搜索接口地址无效")
        }
        components.queryItems = [
            URLQueryItem(name: "types", value: "search"),
            URLQueryItem(name: "source", value: gdSource(source)),
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "pages", value: String(page))
        ]
        guard let url = components.url else {
            throw MusicSourceError.invalidResponse("无法生成搜索请求")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse("搜索 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MusicSourceError.invalidResponse("搜索结果不是歌曲列表")
        }
        let songs: [MusicSong] = rows.compactMap { (row: [String: Any]) -> MusicSong? in
            guard let id = row["id"] else { return nil }
            let artist: String
            if let names = row["artist"] as? [String] { artist = names.joined(separator: " / ") }
            else if let name = row["artist"] as? String { artist = name }
            else { artist = "未知歌手" }
            let album = row["album"] as? String
            return MusicSong(
                source: source,
                sourceID: String(describing: id),
                title: row["name"] as? String ?? "未知歌曲",
                artist: artist,
                album: album,
                artworkURL: nil,
                duration: nil,
                hash: row["hash"] as? String,
                albumID: row["album_id"].map { String(describing: $0) },
                pictureID: row["pic_id"].map { String(describing: $0) },
                lyricID: row["lyric_id"].map { String(describing: $0) }
            )
        }
        diagnosticCount = songs.count
        diagnosticResult = "success"
        return songs
    }

    private func gdSource(_ source: MusicSource) -> String {
        switch source {
        case .netease: "netease"
        case .qq: "tencent"
        case .kuwo: "kuwo"
        case .kugou: "kugou"
        case .migu: "migu"
        case .qishui: "netease"
        }
    }
}
