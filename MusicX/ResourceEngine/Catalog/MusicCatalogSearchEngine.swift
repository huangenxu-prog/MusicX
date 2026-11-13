import Foundation

struct MusicCatalogSearchResponse: Sendable {
    let source: MusicSource
    let songs: [MusicSong]
    let errorMessage: String?
}

/// Central search coordinator for the resource library. It streams each provider's
/// result as it completes so the existing search screen can keep its progressive UI.
struct MusicCatalogSearchEngine {
    private let provider: any MusicCatalogSearchProvider

    init(provider: any MusicCatalogSearchProvider = MusicXLegacySupplierLibrary()) {
        self.provider = provider
    }

    func search(
        keyword: String,
        sources: [MusicSource]
    ) -> AsyncStream<MusicCatalogSearchResponse> {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = self.provider

        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: MusicCatalogSearchResponse.self) { group in
                    for source in sources {
                        group.addTask {
                            do {
                                let count = source == .netease ? 100 : 50
                                let songs = try await provider.search(
                                    keyword: query,
                                    source: source,
                                    page: 1,
                                    count: count,
                                    albumOnly: false,
                                    useNativeNetEase: source == .netease
                                )
                                return MusicCatalogSearchResponse(
                                    source: source,
                                    songs: songs,
                                    errorMessage: nil
                                )
                            } catch {
                                MusicSourceDiagnostics.shared.record(
                                    event: "search",
                                    source: source.rawValue,
                                    provider: provider.identifier,
                                    duration: 0,
                                    result: "failed",
                                    detail: error.localizedDescription
                                )
                                return MusicCatalogSearchResponse(
                                    source: source,
                                    songs: [],
                                    errorMessage: error.localizedDescription
                                )
                            }
                        }
                    }

                    for await response in group {
                        guard !Task.isCancelled else { break }
                        continuation.yield(response)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }


    func search(keyword: String, source: MusicSource, page: Int = 1, count: Int = 20, albumOnly: Bool = false, useNativeNetEase: Bool = false) async throws -> [MusicSong] {
        try await provider.search(
            keyword: keyword,
            source: source,
            page: page,
            count: count,
            albumOnly: albumOnly,
            useNativeNetEase: useNativeNetEase
        )
    }

    func searchPlaylists(keyword: String, count: Int = 10) async throws -> [MusicPlaylist] {
        try await provider.searchPlaylists(keyword: keyword, count: count)
    }

    func featuredPlaylists(count: Int = 30) async throws -> [MusicPlaylist] {
        try await provider.featuredPlaylists(count: count)
    }

    func dailyRecommendedSongs(count: Int = 30) async throws -> [MusicSong] {
        try await provider.dailyRecommendedSongs(count: count)
    }

    func qqDailyRecommendedSongs(count: Int = 30) async throws -> [MusicSong] {
        try await provider.qqDailyRecommendedSongs(count: count)
    }

    func playlistTracks(keyword: String, count: Int = 50) async throws -> [MusicSong] {
        try await provider.playlistTracks(keyword: keyword, count: count)
    }

    func playlistTracks(playlistID: String, count: Int = 50) async throws -> [MusicSong] {
        try await provider.playlistTracks(playlistID: playlistID, count: count)
    }

    func playlistTracks(playlistID: String, source: MusicSource, count: Int = 50) async throws -> [MusicSong] {
        try await provider.playlistTracks(playlistID: playlistID, source: source, count: count)
    }

    func toplist(_ chartName: String, count: Int = 50) async throws -> [MusicSong] {
        try await provider.toplist(chartName, count: count)
    }

}
