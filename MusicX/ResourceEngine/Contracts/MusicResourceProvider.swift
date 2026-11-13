import Foundation

/// A normalized playable resource returned by an external supplier library.
struct ResolvedMusicResource {
    let url: URL
    let providerID: String
    let providerName: String
}

/// Supplier libraries implement this contract. The resource engine owns ordering,
/// fallback, diagnostics and provider health; suppliers own their HTTP/API details.
protocol MusicResourceProvider {
    var identifier: String { get }
    var displayName: String { get }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource?
}
