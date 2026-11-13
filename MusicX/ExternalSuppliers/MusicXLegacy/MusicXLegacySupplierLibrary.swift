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

    func search(keyword: String, source: MusicSource, count: Int) async throws -> [MusicSong] {
        let service = GDStudioMusicSearchService(session: session)
        if source == .netease {
            return try await service.searchNetEase(keyword: keyword, count: count)
        }
        return try await service.search(keyword: keyword, source: source, count: count)
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
