import Foundation

struct MusicCatalogSearchResponse {
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
                                    count: count
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
}
