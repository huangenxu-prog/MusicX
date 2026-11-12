import Foundation

enum MusicSource: String, Codable, CaseIterable, Identifiable {
    case netease = "wy"
    case qq = "tx"
    case kuwo = "kw"
    case kugou = "kg"
    case migu = "mg"
    case qishui = "qs"
    case youtubeMusic = "ytm"
    case youtube = "yt"
    case spotify = "sp"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .netease: "网易云音乐"
        case .qq: "QQ音乐"
        case .kuwo: "酷我音乐"
        case .kugou: "酷狗音乐"
        case .migu: "咪咕音乐"
        case .qishui: "汽水音乐"
        case .youtubeMusic: "YouTube Music"
        case .youtube: "YouTube"
        case .spotify: "Spotify"
        }
    }
}

enum MusicQuality: String, CaseIterable, Identifiable {
    case standard = "128k"
    case high = "320k"
    case lossless = "flac"
    case hires = "flac24bit"

    var id: String { rawValue }

    var neteaseLevel: String {
        switch self {
        case .standard: "standard"
        case .high: "exhigh"
        case .lossless: "lossless"
        case .hires: "hires"
        }
    }

    var gdstudioBitrate: String {
        switch self {
        case .standard: "128"
        case .high: "320"
        case .lossless: "740"
        case .hires: "999"
        }
    }
}

/// A playlist returned by a provider. Playlist IDs are provider-specific.
struct MusicPlaylist: Identifiable, Codable, Hashable {
    let source: MusicSource
    let sourceID: String
    let name: String
    let creator: String?
    let description: String?
    let artworkURL: URL?
    let trackCount: Int?

    var id: String { "\(source.rawValue):playlist:\(sourceID)" }
}

/// IDs are source-specific. Never pass a QQ mid to a NetEase resolver.
struct MusicSong: Identifiable, Codable, Hashable {
    var id: String { "\(source.rawValue):\(sourceID)" }

    let source: MusicSource
    let sourceID: String
    var title: String
    var artist: String
    var album: String?
    var artworkURL: URL?
    var duration: TimeInterval?
    var hash: String?
    var albumID: String?
    var pictureID: String?
    var lyricID: String?
}

enum MusicSourceError: LocalizedError {
    case unsupportedSource(MusicSource)
    case invalidResponse(String)
    case noPlayableURL(source: MusicSource, details: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSource(let source):
            return "暂不支持 \(source.displayName) 的播放解析"
        case .invalidResponse(let message):
            return "音源返回数据格式错误：\(message)"
        case .noPlayableURL(let source, let details):
            return "\(source.displayName) 暂时无法获取播放地址。\(details)"
        }
    }
}

protocol MusicURLResolving {
    func resolve(song: MusicSong, quality: MusicQuality) async throws -> URL
}
