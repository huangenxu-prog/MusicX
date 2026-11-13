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

    func dailyRecommendedSongs(count: Int) async throws -> [MusicSong] {
        try await GDStudioMusicSearchService(session: session).dailyRecommendedSongs(count: count)
    }

    func featuredPlaylists(count: Int) async throws -> [MusicPlaylist] {
        let limit = min(max(count, 1), 60)
        async let netease: [MusicPlaylist]? = try? await NetEaseNativeAPIClient(session: session).recommendedPlaylists(count: limit)
        async let qq: [MusicPlaylist]? = try? await GDStudioMusicSearchService(session: session).recommendedPlaylists(count: limit)
        let neteaseResults = await netease ?? []
        let qqResults = await qq ?? []
        try Task.checkCancellation()

        var merged: [MusicPlaylist] = []
        var seen = Set<String>()
        // Alternate the two catalog sources without introducing Kugou, Kuwo,
        // or Migu into recommendation discovery.
        let groups = [neteaseResults, qqResults]
        let rounds = (0..<max(groups.map(\.count).max() ?? 0, 0))
        for index in rounds {
            for group in groups where index < group.count {
                let playlist = group[index]
                let key = playlist.name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ).filter { $0.isLetter || $0.isNumber }
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                merged.append(playlist)
                if merged.count >= limit { break }
            }
            if merged.count >= limit { break }
        }
        guard !merged.isEmpty else {
            throw MusicSourceError.invalidResponse("推荐歌单暂时无法加载")
        }
        return Array(merged.prefix(limit))
    }

    func searchPlaylists(keyword: String, count: Int) async throws -> [MusicPlaylist] {
        async let qq: [MusicPlaylist]? = try? await GDStudioMusicSearchService(session: session)
            .searchPlaylists(keyword: keyword, count: count)
        async let netease: [MusicPlaylist]? = try? await NetEaseNativeAPIClient(session: session)
            .searchPlaylists(keyword: keyword, count: count)
        let groups = [await netease ?? [], await qq ?? []]
        try Task.checkCancellation()

        var merged: [MusicPlaylist] = []
        var seen = Set<String>()
        for group in groups {
            for playlist in group {
                let key = playlist.name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ).filter { $0.isLetter || $0.isNumber }
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                merged.append(playlist)
                if merged.count >= max(count, 1) { break }
            }
            if merged.count >= max(count, 1) { break }
        }
        guard !merged.isEmpty else {
            throw MusicSourceError.invalidResponse("暂时无法获取匹配的歌单")
        }
        return Array(merged.prefix(max(count, 1)))
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
        case .kugou, .kuwo, .migu:
            return try await DomesticPlaylistDiscoveryService(session: session).playlistTracks(
                playlistID: playlistID,
                source: source,
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
