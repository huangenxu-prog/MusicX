import Foundation

/// A normalized playable resource returned by an external supplier library.
struct ResolvedMusicResource: Sendable {
    let url: URL
    let providerID: String
    let providerName: String
}

/// Supplier libraries implement this contract. The resource engine owns ordering,
/// fallback, diagnostics and provider health; suppliers own their HTTP/API details.
protocol MusicResourceProvider: Sendable {
    var identifier: String { get }
    var displayName: String { get }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource?
}


/// Search-capable external supplier. Search metadata is kept separate from stream
/// resolution so catalog providers can be added without coupling them to playback.
protocol MusicCatalogSearchProvider: Sendable {
    var identifier: String { get }
    var displayName: String { get }

    func search(keyword: String, source: MusicSource, page: Int, count: Int, albumOnly: Bool, useNativeNetEase: Bool) async throws -> [MusicSong]
    func searchPlaylists(keyword: String, count: Int) async throws -> [MusicPlaylist]
    func playlistTracks(keyword: String, count: Int) async throws -> [MusicSong]
    func playlistTracks(playlistID: String, count: Int) async throws -> [MusicSong]
    func playlistTracks(playlistID: String, source: MusicSource, count: Int) async throws -> [MusicSong]
    func toplist(_ chartName: String, count: Int) async throws -> [MusicSong]
}
