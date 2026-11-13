import Foundation

/// Native NetEase playback provider. Third-party NetEase resolvers remain
/// available in MusicXLegacySupplierLibrary as fallback routes.
struct NetEaseNativeAudioProvider: MusicResourceProvider {
    let identifier = "netease-native-eapi"
    let displayName = "网易云原生音源"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        guard song.source == .netease else { return nil }
        guard let url = try await NetEaseNativeAPIClient(session: session)
            .playbackURL(songID: song.sourceID, quality: quality) else {
            return nil
        }
        return ResolvedMusicResource(
            url: url,
            providerID: identifier,
            providerName: displayName
        )
    }
}
