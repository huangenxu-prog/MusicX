import Foundation

/// The complete pre-existing MusicX source system is retained as one independent
/// external supplier library. Its GDStudio, Chksz, Lerd and native-source routes
/// remain encapsulated behind this adapter.
///
/// Kumone's pyncmd implementation calls the same GDStudio URL endpoint already
/// present in the legacy library. It is therefore represented by that existing
/// route rather than registered twice and issuing duplicate network requests.
struct MusicXLegacySupplierLibrary: MusicResourceProvider, MusicCatalogSearchProvider {
    let identifier = "musicx-legacy-library"
    let displayName = "MusicX 原有音源库"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(keyword: String, source: MusicSource, page: Int, count: Int, albumOnly: Bool) async throws -> [MusicSong] {
        let service = GDStudioMusicSearchService(session: session)
        if source == .netease && !albumOnly && page == 1 {
            return try await service.searchNetEase(keyword: keyword, count: count)
        }
        return try await service.search(
            keyword: keyword,
            source: source,
            page: page,
            count: count,
            albumOnly: albumOnly
        )
    }

    func searchPlaylists(keyword: String, count: Int) async throws -> [MusicPlaylist] {
        try await GDStudioMusicSearchService(session: session).searchPlaylists(keyword: keyword, count: count)
    }

    func playlistTracks(keyword: String, count: Int) async throws -> [MusicSong] {
        try await GDStudioMusicSearchService(session: session).playlistTracks(keyword: keyword, count: count)
    }

    func playlistTracks(playlistID: String, count: Int) async throws -> [MusicSong] {
        try await GDStudioMusicSearchService(session: session).playlistTracks(playlistID: playlistID, count: count)
    }

    func toplist(_ chartName: String, count: Int) async throws -> [MusicSong] {
        try await GDStudioMusicSearchService(session: session).toplist(chartName, count: count)
    }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        let resolver = LXMusicURLResolver(session: session)
        guard let url = try await resolver.resolveFromLegacyLibrary(song: song, quality: quality) else {
            return nil
        }
        return ResolvedMusicResource(
            url: url,
            providerID: identifier,
            providerName: displayName
        )
    }
}
