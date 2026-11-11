import SwiftUI

/// Crops one tile from the generated 4×6 artwork sheet.
/// Each tile is square; destination frames crop naturally without stretching.
struct HomeArtwork: View {
    let name: String

    private let names = [
        "home_hero", "daily_recommend", "featured_playlist", "chart_hot",
        "chart_rising", "chart_new", "album_01", "album_02",
        "album_03", "album_04", "album_05", "playlist_relax",
        "playlist_night", "playlist_drive", "song_01", "song_02",
        "song_03", "song_04", "song_05", "song_06",
        "guess_01", "guess_02", "guess_03", "player_cover"
    ]

    var body: some View {
        GeometryReader { proxy in
            let cell = max(proxy.size.width, proxy.size.height)
            let index = names.firstIndex(of: name) ?? 0
            Image("HomeArtworkSheet")
                .resizable()
                .interpolation(.high)
                .frame(width: cell * 4, height: cell * 6, alignment: .topLeading)
                .offset(x: -CGFloat(index % 4) * cell - max(0, (cell - proxy.size.width) / 2),
                        y: -CGFloat(index / 4) * cell - max(0, (cell - proxy.size.height) / 2))
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
        }
    }
}
