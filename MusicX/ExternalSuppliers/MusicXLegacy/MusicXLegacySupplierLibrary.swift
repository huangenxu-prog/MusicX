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

    func search(keyword: String, source: MusicSource, page: Int, count: Int, albumOnly: Bool, useNativeNetEase: Bool) async throws -> [MusicSong] {
        let service = GDStudioMusicSearchService(session: session)
        if useNativeNetEase && source == .netease {
            do {
                let native = NetEaseNativeAPIClient(session: session)
                if albumOnly {
                    return try await native.searchAlbums(
                        keyword: keyword,
                        count: count,
                        offset: max(0, page - 1) * count
                    )
                }
                return try await native.search(
                    keyword: keyword,
                    count: count,
                    offset: max(0, page - 1) * count
                )
            } catch {
                if Task.isCancelled || error is CancellationError
                    || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                MusicSourceDiagnostics.shared.record(
                    event: "search-fallback",
                    source: source.rawValue,
                    provider: "netease-native-eapi",
                    duration: 0,
                    result: "fallback_to_gdstudio",
                    detail: error.localizedDescription
                )
            }
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
        async let qqResults: [MusicPlaylist]? = try? await GDStudioMusicSearchService(session: session)
            .searchPlaylists(keyword: keyword, count: count)
        async let neteaseResults: [MusicPlaylist]? = try? await NetEaseNativeAPIClient(session: session)
            .searchPlaylists(keyword: keyword, count: count)
        let groups = await [qqResults ?? [], neteaseResults ?? []]
        try Task.checkCancellation()

        var seen = Set<String>()
        let merged = groups.flatMap { $0 }.filter { seen.insert($0.id).inserted }
        guard !merged.isEmpty else {
            throw MusicSourceError.invalidResponse("网易云和 QQ 音乐均未返回可用歌单")
        }
        return merged
    }

    func playlistTracks(keyword: String, count: Int) async throws -> [MusicSong] {
        try await GDStudioMusicSearchService(session: session).playlistTracks(keyword: keyword, count: count)
    }

    func playlistTracks(playlistID: String, count: Int) async throws -> [MusicSong] {
        try await GDStudioMusicSearchService(session: session).playlistTracks(playlistID: playlistID, count: count)
    }

    func playlistTracks(playlistID: String, source: MusicSource, count: Int) async throws -> [MusicSong] {
        switch source {
        case .netease:
            return try await NetEaseNativeAPIClient(session: session).playlistTracks(
                playlistID: playlistID,
                count: count
            )
        case .qq:
            return try await GDStudioMusicSearchService(session: session).playlistTracks(
                playlistID: playlistID,
                count: count
            )
        default:
            throw MusicSourceError.unsupportedSource(source)
        }
    }

    func toplist(_ chartName: String, count: Int) async throws -> [MusicSong] {
        do {
            return try await NetEaseNativeAPIClient(session: session).toplist(chartName, count: count)
        } catch {
            if Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            MusicSourceDiagnostics.shared.record(
                event: "catalog-fallback",
                source: MusicSource.netease.rawValue,
                provider: "netease-native-eapi",
                duration: 0,
                result: "fallback_to_gdstudio",
                detail: error.localizedDescription
            )
            return try await GDStudioMusicSearchService(session: session).toplist(chartName, count: count)
        }
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
