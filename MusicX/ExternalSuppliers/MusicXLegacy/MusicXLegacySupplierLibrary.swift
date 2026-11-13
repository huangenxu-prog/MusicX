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

    func featuredPlaylists(count: Int) async throws -> [MusicPlaylist] {
        let limit = min(max(count, 1), 60)
        async let netease: [MusicPlaylist]? = try? await NetEaseNativeAPIClient(session: session).recommendedPlaylists(count: limit)
        async let qq: [MusicPlaylist]? = try? await GDStudioMusicSearchService(session: session).recommendedPlaylists(count: limit)
        async let other: [MusicPlaylist]? = try? await DomesticPlaylistDiscoveryService(session: session).featuredPlaylists(count: limit)
        let neteaseResults = await netease
        let qqResults = await qq
        let otherResults = await other
        let groups = [neteaseResults ?? [], qqResults ?? [], otherResults ?? []]
        try Task.checkCancellation()
        if neteaseResults == nil {
            MusicSourceDiagnostics.shared.record(
                event: "playlist-discovery", source: MusicSource.netease.rawValue,
                provider: "netease-recommendations", duration: 0, result: "failed",
                detail: "网易云推荐歌单接口未返回有效结果"
            )
        }
        if qqResults == nil {
            MusicSourceDiagnostics.shared.record(
                event: "playlist-discovery", source: MusicSource.qq.rawValue,
                provider: "qq-recommendations", duration: 0, result: "failed",
                detail: "QQ音乐推荐歌单接口未返回有效结果"
            )
        }

        let bySource = Dictionary(grouping: groups.flatMap { $0 }, by: \\.source)
        let sourceOrder: [MusicSource] = [.netease, .qq, .kugou, .kuwo, .migu]
        var merged: [MusicPlaylist] = []
        var seenIDs = Set<String>()
        var seenNames = Set<String>()
        let maximumPerSource = max(1, Int(ceil(Double(limit) / Double(sourceOrder.count))))
        for source in sourceOrder {
            let candidates = Array((bySource[source] ?? []).prefix(maximumPerSource * 3))
            var added = 0
            for playlist in candidates {
                let normalizedName = playlist.name
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .filter { $0.isLetter || $0.isNumber }
                guard !normalizedName.isEmpty,
                      seenIDs.insert(playlist.id).inserted,
                      seenNames.insert(normalizedName).inserted else { continue }
                merged.append(playlist)
                added += 1
                if added >= maximumPerSource { break }
            }
        }
        guard !merged.isEmpty else {
            throw MusicSourceError.invalidResponse("五个平台均未返回可用推荐或分类歌单")
        }
        return Array(merged.prefix(limit))
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
