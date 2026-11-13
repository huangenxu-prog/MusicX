import SwiftUI
import AVFoundation

private enum MainTab: String, CaseIterable {
    case home = "首页"
    case search = "搜索"
    case library = "音乐库"

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .library: "music.note"
        }
    }
}

private struct AppSong: Identifiable, Equatable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let tint: Color
    let onlineSong: MusicSong?

    init(id: Int, title: String, artist: String, album: String, tint: Color, onlineSong: MusicSong? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.tint = tint
        self.onlineSong = onlineSong
    }
}

private struct LibraryArtist: Identifiable {
    let artist: String
    let song: AppSong
    let count: Int
    var id: String { artist }
}

private struct LibraryAlbum: Identifiable {
    let title: String
    let artist: String
    let song: AppSong
    let count: Int
    var id: String { "\(title)-\(artist)" }
}

private enum LibraryFilter: String, CaseIterable {
    case recent = "最近播放"
    case favorites = "收藏歌曲"
}

private enum LibraryContentType: String, CaseIterable {
    case songs = "歌曲"
    case playlists = "歌单"
    case albums = "专辑"
    case artists = "歌手"
}

private enum PlayerDisplayMode: CaseIterable, Hashable {
    case artwork
    case lyrics
    case queue

    var title: String {
        switch self {
        case .artwork: "封面"
        case .lyrics: "歌词"
        case .queue: "播放队列"
        }
    }

    var symbol: String {
        switch self {
        case .artwork: "square"
        case .lyrics: "quote.bubble"
        case .queue: "list.bullet"
        }
    }

    var next: PlayerDisplayMode {
        let modes = Self.allCases
        let index = modes.firstIndex(of: self) ?? 0
        return modes[(index + 1) % modes.count]
    }

    var previous: PlayerDisplayMode {
        let modes = Self.allCases
        let index = modes.firstIndex(of: self) ?? 0
        return modes[(index - 1 + modes.count) % modes.count]
    }
}

private struct MusicXPageBackground: View {
    var body: some View {
        Color(red: 10/255, green: 14/255, blue: 31/255)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct ContentView: View {
    @State private var selectedTab: MainTab = .home
    @Namespace private var tabSelectionNamespace
    @State private var searchText = ""
    @State private var searchSuggestions = ["十年", "突然好想你", "晴天", "青花瓷"]
    @FocusState private var searchFieldFocused: Bool
    @State private var libraryFilter: LibraryFilter = .recent
    @State private var libraryContentType: LibraryContentType = .songs
    @State private var isLocalMusicAlertPresented = false
    @State private var currentSong: AppSong?
    @State private var isSeekingProgress = false
    @State private var seekPreviewTime: TimeInterval = 0
    @StateObject private var playerStore = PlayerStore()
    @State private var onlineResults: [AppSong] = []
    @State private var isSearching = false
    @State private var searchRequestID = UUID()
    @State private var searchError: String?
    @State private var isPlayerPresented = false
    @State private var playbackRequestID = UUID()
    @State private var playbackTask: Task<Void, Never>?
    @State private var playbackQueueSongs: [AppSong] = []
    @State private var shuffleHistory: [Int] = []
    @State private var shuffleForwardHistory: [Int] = []
    @State private var hasCustomPlaybackQueue = false
    @State private var isResolvingSong = false
    @State private var failedPlaybackSongIDs: Set<Int> = []
    @State private var refreshedPlaybackSongIDs: Set<Int> = []
    @AppStorage("musicx.favoriteIDs") private var favoriteIDs = "1,3"
    @AppStorage("musicx.recentIDs") private var recentIDs = ""
    @AppStorage("musicx.recentSongs") private var recentSongsJSON = "[]"
    @AppStorage("musicx.favoriteSongs") private var favoriteSongsJSON = "[]"
    @AppStorage("musicx.playbackQuality") private var playbackQualityRaw = MusicQuality.high.rawValue

    private var selectedMusicQuality: MusicQuality {
        MusicQuality(rawValue: playbackQualityRaw) ?? .high
    }

    private var favorites: Set<Int> {
        Set(favoriteIDs.split(separator: ",").compactMap { Int($0) })
    }

    private var recentSongs: [AppSong] {
        let stored = decodeLibrarySongs(recentSongsJSON).map { appSong(from: $0) }
        var available = stored
        available.append(contentsOf: songs)
        available.append(contentsOf: onlineResults)
        available.append(contentsOf: playbackQueueSongs)
        if let currentSong { available.append(currentSong) }
        available = uniqueLibrarySongs(available)
        let ids = recentIDs.split(separator: ",").compactMap { Int($0) }
        let ordered = ids.compactMap { id in available.first { $0.id == id } }
        return ordered.isEmpty ? stored : ordered
    }

    private var favoriteSongs: [AppSong] {
        let stored = decodeLibrarySongs(favoriteSongsJSON).map { appSong(from: $0) }
        var available = stored
        available.append(contentsOf: songs)
        available.append(contentsOf: onlineResults)
        available.append(contentsOf: playbackQueueSongs)
        if let currentSong { available.append(currentSong) }
        available = uniqueLibrarySongs(available)
        let ids = favorites
        let current = available.filter { ids.contains($0.id) }
        return uniqueLibrarySongs(stored + current).filter { ids.contains($0.id) }
    }

    private func decodeLibrarySongs(_ raw: String) -> [MusicSong] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MusicSong].self, from: data) else { return [] }
        return decoded
    }

    private func uniqueLibrarySongs(_ items: [AppSong]) -> [AppSong] {
        var seen = Set<Int>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func appSong(from song: MusicSong) -> AppSong {
        AppSong(id: stableSongID(song), title: song.title, artist: song.artist,
                album: song.album ?? "", tint: MusicXTheme.blue, onlineSong: song)
    }

    private func encodedLibrarySongs(_ items: [MusicSong]) -> String {
        guard let data = try? JSONEncoder().encode(items),
              let value = String(data: data, encoding: .utf8) else { return "[]" }
        return value
    }

    @State private var songs: [AppSong] = []
    @State private var recommendationSongs: [AppSong] = []
    @State private var isLoadingHomeSongs = false
    @State private var homeLoadError: String?
    @State private var discoveryRoute: MusicDiscoveryRoute?
    @State private var isSettingsAlertPresented = false

    private var filteredSongs: [AppSong] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return songs }
        return onlineResults
    }

    private var libraryArtists: [LibraryArtist] {
        let grouped = Dictionary(grouping: librarySongs) { $0.artist.trimmingCharacters(in: .whitespacesAndNewlines) }
        return grouped.keys.filter { !$0.isEmpty }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.compactMap { artist in
            guard let tracks = grouped[artist], let first = tracks.first else { return nil }
            return LibraryArtist(artist: artist, song: first, count: tracks.count)
        }
    }

    private var librarySongs: [AppSong] {
        switch libraryFilter {
        case .favorites: favoriteSongs
        case .recent: recentSongs
        }
    }

    private var libraryAlbums: [LibraryAlbum] {
        let grouped = Dictionary(grouping: librarySongs) { song in
            let album = song.album.trimmingCharacters(in: .whitespacesAndNewlines)
            return album.isEmpty ? song.title : album
        }
        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.compactMap { title in
            guard let tracks = grouped[title], let first = tracks.first else { return nil }
            return LibraryAlbum(title: title, artist: first.artist, song: first, count: tracks.count)
        }
    }

    var body: some View {
        ZStack {
            MusicXPageBackground()
            Group {
                switch selectedTab {
                case .home: homePage
                case .search: searchPage
                case .library: libraryPage
                }
            }
            .id(selectedTab)
            .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !(selectedTab == .search && searchFieldFocused) {
                VStack(spacing: 8) {
                    miniPlayer
                    tabBar
                }
                .padding(.top, 8)
                .padding(.bottom, 0)
                .offset(y: 16)
                .zIndex(20)
                .background {
                    LinearGradient(colors: [Color(red: 0.015, green: 0.035, blue: 0.085).opacity(0.02),
                                                   Color(red: 0.012, green: 0.025, blue: 0.065).opacity(0.90)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("播放设置", isPresented: $isSettingsAlertPresented, titleVisibility: .visible) {
            Button("标准音质 · 128 kbps") { playbackQualityRaw = MusicQuality.standard.rawValue }
            Button("高音质 · 320 kbps") { playbackQualityRaw = MusicQuality.high.rawValue }
            Button("无损音质") { playbackQualityRaw = MusicQuality.lossless.rawValue }
            Button("Hi-Res") { playbackQualityRaw = MusicQuality.hires.rawValue }
            Button("取消", role: .cancel) { }
        } message: {
            Text("当前音质：\(qualityDisplayName(selectedMusicQuality))。不同音源实际支持的最高音质可能不同。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .musicXRemoteNextTrack)) { _ in
            stepSong(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .musicXRemotePreviousTrack)) { _ in
            stepSong(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .musicXPlaybackDidFinish)) { _ in
            playNextAfterNaturalFinish()
        }
        .onReceive(NotificationCenter.default.publisher(for: .musicXPlaybackFailed)) { notification in
            guard let failedItem = notification.object as? AVPlayerItem,
                  playerStore.isCurrentItem(failedItem) else { return }
            retryCurrentSongWithFreshURL()
        }
        .overlay {
            if let route = discoveryRoute {
                MusicDiscoveryPage(route: route,
                    selectedMainTab: selectedTab.rawValue,
                    onSelectMainTab: { title in
                        withAnimation(.easeInOut(duration: 0.20)) {
                            selectedTab = MainTab.allCases.first(where: { $0.rawValue == title }) ?? .home
                            discoveryRoute = nil
                        }
                    },
                    onClose: { isSwipeBack in
                    if isSwipeBack {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { discoveryRoute = nil }
                    } else {
                        withAnimation(.easeInOut(duration: 0.28)) { discoveryRoute = nil }
                    }
                },
                    onPlay: { playDiscoverySong($0) },
                    currentSong: currentSong?.onlineSong,
                    isPlaying: playerStore.isPlaying,
                    onTogglePlayback: { playerStore.togglePlayback() },
                    onOpenPlayer: { isPlayerPresented = true },
                    onPrevious: { stepSong(by: -1) },
                    onNext: { stepSong(by: 1) },
                    onOpenQueue: { playerDisplayMode = .queue; isPlayerPresented = true },
                    onQueueChanged: {
                        playbackQueueSongs = $0.map { AppSong(id: stableSongID($0), title: $0.title, artist: $0.artist, album: $0.album ?? "", tint: MusicXTheme.blue, onlineSong: $0) }
                        hasCustomPlaybackQueue = true
                        resetShuffleHistory()
                    },
                    currentTime: playerStore.currentTime,
                    duration: playerStore.duration,
                    onOpenPlaylist: { discoveryRoute = .playlistByID($0) },
                    onOpenPlaylistKeyword: { discoveryRoute = .playlist($0) },
                    onOpenFeaturedPick: { discoveryRoute = .featuredPick },
                    onOpenAlbum: { discoveryRoute = .album(title: $0, artist: $1) },
                    onSelectChart: { discoveryRoute = .chart($0) })
                    .id(route.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MusicXPageBackground())
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
                    .zIndex(30)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: discoveryRoute?.id)
        .overlay {
            if isPlayerPresented {
                nowPlayingPage
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
                    .zIndex(40)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isPlayerPresented)
        .animation(.easeInOut(duration: 0.28), value: selectedTab)
        .task { await loadHomeSongs() }
    }

    private var homePage: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 15) {
                    HomeScrollBounceDisabler().frame(width: 0, height: 0)
                    heroAndRecommendation
                    chartSection
                    newMusicSection
                    albumSection
                    editorialPlaylistSection
                }
                .padding(.top, 0)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            let navy = Color(red: 10/255, green: 14/255, blue: 31/255)

            LinearGradient(
                stops: [
                    .init(color: Color(red: 30/255,  green: 42/255,  blue: 107/255), location: 0.00),
                    .init(color: Color(red: 75/255,  green: 52/255,  blue: 144/255), location: 0.25),
                    .init(color: Color(red: 154/255, green: 79/255,  blue: 143/255), location: 0.45),
                    .init(color: Color(red: 232/255, green: 112/255, blue: 138/255), location: 0.64),
                    .init(color: Color(red: 248/255, green: 176/255, blue: 104/255), location: 0.75),
                    .init(color: Color(red: 122/255, green: 74/255,  blue: 120/255), location: 0.85),
                    .init(color: navy,                                               location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var heroAndRecommendation: some View {
        VStack(alignment: .leading, spacing: 10) { heroHeader; recommendationSection }
    }

    // DESIGN LOCK: fixed vinyl-record hero artwork from the approved home reference.
    // Home hero follows the supplied gradient-header reference.
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("发现音乐")
                .font(.system(size: 34, weight: .bold))
                .tracking(0.1)
                .foregroundStyle(.white)
            Text("— 好音乐，总在心里 —")
                .font(.system(size: 13, weight: .medium))
                .tracking(1.25)
                .foregroundStyle(.white.opacity(0.90))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 122, alignment: .bottomLeading)
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .offset(y: -63)
        .accessibilityElement(children: .combine)
    }

    // Two rectangular gradient entry cards, matching the supplied home reference.
    private var recommendationSection: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 12
            let width = max(0, (proxy.size.width - gap) / 2)
            HStack(spacing: gap) {
                recommendationTile(
                    title: "每日推荐", subtitle: "每日更新", icon: "play.fill",
                    colors: [Color(red: 0.98, green: 0.61, blue: 0.36), Color(red: 0.70, green: 0.25, blue: 0.48)],
                    route: .daily, width: width
                )
                recommendationTile(
                    title: "精选歌单", subtitle: "遇见更好的自己", icon: "text.alignleft",
                    colors: [Color(red: 0.52, green: 0.36, blue: 0.91), Color(red: 0.22, green: 0.12, blue: 0.55)],
                    route: .featuredPick, width: width
                )
            }
        }
        .frame(height: 84)
        .padding(.horizontal, 16)
    }

    private func recommendationTile(title: String, subtitle: String, icon: String, colors: [Color], route: MusicDiscoveryRoute, width: CGFloat) -> some View {
        return Button { discoveryRoute = route } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: colors + [colors.last!.opacity(0.52)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 76, height: 76)
                    .blur(radius: 22)
                    .offset(x: width * 0.58, y: -23)
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 27, height: 27)
                        .background(.white.opacity(0.22), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 0.8))
                    Spacer(minLength: 0)
                    Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1).minimumScaleFactor(0.75).padding(.top, 2)
                }.padding(.leading, 15).padding(.vertical, 10)
            }
            .frame(width: width, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.26), lineWidth: 0.9))
            .shadow(color: colors.first?.opacity(0.20) ?? .clear, radius: 10, y: 4)
        }.buttonStyle(.plain)
    }

    private func featuredCard(title: String, subtitle: String, route: MusicDiscoveryRoute, variant: Int) -> some View {
        Button { discoveryRoute = route } label: {
            ZStack(alignment: .bottomLeading) {
                MountainBackdrop(variant: variant + 1)
                LinearGradient(colors: [.clear, Color.black.opacity(0.48)], startPoint: .center, endPoint: .bottom)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 25, weight: .bold))
                        Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.78))
                    }
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var newMusicSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            homeSectionTitle("新歌速递", action: { discoveryRoute = .newReleases }).padding(.horizontal, 14)
            if isLoadingHomeSongs && songs.isEmpty {
                ProgressView().tint(MusicXTheme.blue).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if let homeLoadError, songs.isEmpty {
                Text(homeLoadError).font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).padding(.vertical, 14)
            } else {
                VStack(spacing: 5) {
                    ForEach(0..<min(songs.count, 6), id: \.self) { index in
                        let song = songs[index]
                        homeSongRow(song)
                        if song.id != songs.prefix(6).last?.id {
                            Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
                        }
                    }
                }.padding(.horizontal, 20)
            }
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            homeSectionTitle("热门专辑", action: { discoveryRoute = .albums }).padding(.horizontal, 14)
            GeometryReader { proxy in
                let gap: CGFloat = 12
                let width = max(112, (proxy.size.width - 28 - gap * 2) / 3)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: gap) {
                        ForEach(0..<5, id: \.self) { index in staticAlbumTile(index: index, width: width) }
                    }.padding(.horizontal, 14)
                }
            }.frame(height: 150)
        }
    }

    private func staticAlbumTile(index: Int, width: CGFloat) -> some View {
        let titles = ["DUO", "最伟大的作品", "宇宙的有趣", "A-Lin", "幼鸟指南"]
        let artists = ["陈奕迅", "周杰伦", "告五人", "LINK", "毛不易"]
        return Button { discoveryRoute = .album(title: titles[index], artist: artists[index]) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Image("album_0\(index + 1)").resizable().scaledToFill()
                    .frame(width: width, height: width).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
                Text(titles[index]).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(artists[index]).font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
            }.frame(width: width, alignment: .leading)
         }.buttonStyle(.plain)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            homeSectionTitle("排行榜", action: nil).padding(.horizontal, 14)
            GeometryReader { proxy in
                let gap: CGFloat = 10
                let horizontalInset: CGFloat = 16
                let width = max(0, (proxy.size.width - horizontalInset * 2 - gap * 2) / 3)
                HStack(spacing: gap) {
                    chartTile("热歌榜", subtitle: "Top 50", rank: "01", icon: "crown.fill", color: Color(red: 0.98, green: 0.48, blue: 0.34), width: width)
                    chartTile("飙升榜", subtitle: "热度上升", rank: "02", icon: "flame.fill", color: Color(red: 0.60, green: 0.37, blue: 0.98), width: width)
                    chartTile("新歌榜", subtitle: "最新 50 首", rank: "03", icon: "waveform", color: Color(red: 0.08, green: 0.72, blue: 0.88), width: width)
                }.padding(.horizontal, horizontalInset)
            }.frame(height: 104)
        }
        // The reference design leaves a distinct breathing space before New Releases.
        .padding(.bottom, 18)
    }

    private var editorialPlaylistSection: some View {
        let items: [(title: String, subtitle: String, artwork: String)] = [
            ("本周编辑精选", "本周精选", "featured_playlist"),
            ("华语流行精选", "宝藏好歌 · 优质华语流行歌曲合集", "category_chinese_pop"),
            ("经典金曲精选", "经久不衰的动人歌声", "category_classic"),
            ("独立音乐精选", "Indie Music｜独立音乐聚落", "category_singers"),
            ("影视原声精选", "问心系列 影视原声带", "category_instrumental"),
            ("通勤驾驶精选", "通勤路上｜有前行感的节奏", "playlist_drive")
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Capsule().fill(MusicXTheme.blue).frame(width: 4, height: 21)
                Text("精选歌单").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Button { discoveryRoute = .featuredPlaylists } label: {
                    HStack(spacing: 4) {
                        Text("全部").font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }.foregroundStyle(MusicXTheme.muted)
                }.buttonStyle(.plain)
            }.padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                let cardWidth = (UIScreen.main.bounds.width - 44) / 2.15
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items, id: \.title) { item in
                        Button {
                            if item.title == "本周编辑精选" {
                                discoveryRoute = .featuredPlaylists
                            } else {
                                discoveryRoute = .playlist(item.title)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HomeArtwork(name: item.artwork)
                                    .frame(width: cardWidth, height: cardWidth * 0.78)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.8))
                                Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }.frame(width: cardWidth, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 14)
            }
        }
    }

    private func albumArtwork(_ song: MusicSong?, tint: Color, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let url = song?.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { artworkFallback(tint: tint) }
                }
            } else { artworkFallback(tint: tint) }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchPage: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    pageHeader("搜索", subtitle: "搜索歌曲、歌手或专辑")
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(Color(red: 0.69, green: 0.73, blue: 0.84))
                        TextField("输入歌曲、歌手或专辑", text: $searchText)
                            .font(.system(size: 16))
                            .tint(MusicXTheme.blue)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($searchFieldFocused)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(MusicXTheme.muted)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(Color(red: 0.075, green: 0.09, blue: 0.17), in: Capsule())
                    .overlay(Capsule().stroke(Color(red: 0.19, green: 0.23, blue: 0.43), lineWidth: 1))
                    .shadow(color: Color(red: 0.16, green: 0.22, blue: 0.55).opacity(0.10), radius: 12, y: 4)

                    if searchText.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Capsule().fill(MusicXTheme.blue).frame(width: 4, height: 20)
                                Text("热门搜索").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 9) {
                                    ForEach(Array(searchSuggestions.enumerated()), id: \.element) { index, title in
                                        Button {
                                            searchText = title
                                            searchFieldFocused = false
                                        } label: {
                                            Text(title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(index == 0 ? Color(red: 0.035, green: 0.055, blue: 0.12) : .white)
                                                .padding(.horizontal, 17)
                                                .frame(height: 40)
                                                .background(index == 0 ? MusicXTheme.blue : Color(red: 0.085, green: 0.105, blue: 0.20), in: Capsule())
                                                .overlay(Capsule().stroke(index == 0 ? .white.opacity(0.12) : Color(red: 0.16, green: 0.19, blue: 0.34), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Capsule().fill(MusicXTheme.blue).frame(width: 4, height: 20)
                                Text("音乐分类").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                SearchCategoryCard(title: "华语流行", subtitle: "精选华语流行", asset: "SearchCategory01", symbol: "circle.fill", tint: Color(red: 0.10, green: 0.43, blue: 0.88)) { discoveryRoute = .musicCategory(title: "华语流行", subtitle: "精选华语流行", artwork: "category_chinese_pop", keyword: "华语流行") }
                                SearchCategoryCard(title: "经典老歌", subtitle: "时代金曲回忆", asset: "SearchCategory02", symbol: "mic.fill", tint: Color(red: 0.73, green: 0.20, blue: 0.53)) { discoveryRoute = .musicCategory(title: "经典老歌", subtitle: "时代金曲回忆", artwork: "category_classic", keyword: "经典老歌") }
                                SearchCategoryCard(title: "轻音乐", subtitle: "舒缓 · 放松", asset: "SearchCategory03", symbol: "leaf.fill", tint: Color(red: 0.08, green: 0.55, blue: 0.43)) { discoveryRoute = .musicCategory(title: "轻音乐", subtitle: "舒缓 · 放松", artwork: "category_light", keyword: "轻音乐") }
                                SearchCategoryCard(title: "纯音乐", subtitle: "器乐 · 演奏", asset: "SearchCategory04", symbol: "square.fill", tint: Color(red: 0.48, green: 0.23, blue: 0.80)) { discoveryRoute = .musicCategory(title: "纯音乐", subtitle: "器乐 · 演奏", artwork: "category_instrumental", keyword: "纯音乐") }
                                SearchCategoryCard(title: "摇滚", subtitle: "激情 · 力量", asset: "SearchCategory05", symbol: "bolt.fill", tint: Color(red: 0.82, green: 0.30, blue: 0.10)) { discoveryRoute = .musicCategory(title: "摇滚", subtitle: "激情 · 力量", artwork: "category_rock", keyword: "摇滚") }
                                SearchCategoryCard(title: "欧美音乐", subtitle: "欧美流行精选", asset: "SearchCategory06", symbol: "headphones", tint: Color(red: 0.05, green: 0.52, blue: 0.75)) { discoveryRoute = .musicCategory(title: "欧美音乐", subtitle: "欧美流行精选", artwork: "category_singers", keyword: "欧美音乐") }
                            }
                        }
                        Text("选择分类，发现更多音乐")
                            .font(.system(size: 14))
                            .foregroundStyle(MusicXTheme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 1)
                    } else {
                        HStack {
                            Text("搜索结果").font(.system(size: 19, weight: .bold)).id("searchResults")
                            Spacer()
                            Text(isSearching ? "搜索中…" : "\(filteredSongs.count) 首")
                                .font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
                        }
                        if filteredSongs.isEmpty {
                            emptyState(icon: "music.note.list", title: searchError == nil ? "正在搜索在线音源" : "暂时没有搜索结果", detail: searchError ?? "请稍候")
                        } else {
                            VStack(spacing: 17) {
                                ForEach(filteredSongs) { song in songRow(song, startsSearchQueue: true) }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 70)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: searchFieldFocused) { _, focused in
                guard focused else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("searchResults", anchor: .top) }
                }
            }
            .task(id: searchText) {
                let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !keyword.isEmpty else { onlineResults = []; searchError = nil; return }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await searchOnline(keyword)
            }
        }
    }

    private var libraryPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("音乐库")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("最近听过的音乐与喜欢的歌曲")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MusicXTheme.muted)
                    }
                    Spacer()
                    Button {
                        selectedTab = .search
                        searchFieldFocused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 44, height: 44)
                            .background(Color(red: 0.075, green: 0.09, blue: 0.17), in: Circle())
                            .overlay(Circle().stroke(Color(red: 0.19, green: 0.23, blue: 0.43), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("搜索音乐")
                }

                HStack(spacing: 8) {
                    ForEach([LibraryContentType.songs, .artists], id: \.self) { type in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { libraryContentType = type }
                        } label: {
                            Text(type.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(libraryContentType == type ? Color(red: 0.035, green: 0.045, blue: 0.11) : .white.opacity(0.88))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(libraryContentType == type ? MusicXTheme.blue : Color(red: 0.085, green: 0.105, blue: 0.20), in: Capsule())
                                .overlay(Capsule().stroke(libraryContentType == type ? .white.opacity(0.14) : Color(red: 0.16, green: 0.19, blue: 0.34), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if libraryContentType == .songs {
                    HStack(spacing: 9) {
                        ForEach(LibraryFilter.allCases, id: \.self) { filter in
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) { libraryFilter = filter }
                            } label: {
                                Text(filter.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(libraryFilter == filter ? MusicXTheme.blue.opacity(0.98) : .white.opacity(0.88))
                                    .padding(.horizontal, 15)
                                    .frame(height: 38)
                                    .background(libraryFilter == filter ? Color(red: 0.10, green: 0.15, blue: 0.29) : Color(red: 0.085, green: 0.105, blue: 0.20), in: Capsule())
                                    .overlay(Capsule().stroke(libraryFilter == filter ? MusicXTheme.blue : Color(red: 0.16, green: 0.19, blue: 0.34), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Text("\(librarySongs.count) 首")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MusicXTheme.muted)
                    }
                    .padding(.top, 2)

                    if librarySongs.isEmpty {
                        emptyState(
                            icon: libraryFilter == .favorites ? "heart" : "clock.arrow.circlepath",
                            title: libraryFilter == .favorites ? "还没有收藏歌曲" : "暂无最近播放",
                            detail: libraryFilter == .favorites ? "在歌曲列表中点亮爱心，收藏的歌曲会显示在这里" : "播放过的歌曲会自动保存在这里"
                        )
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        VStack(spacing: 3) {
                            ForEach(librarySongs) { song in
                                HStack(spacing: 12) {
                                    songArtwork(song.onlineSong, tint: song.tint, size: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Button { selectManually(song) } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(song.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(currentSong?.id == song.id ? MusicXTheme.blue : .white)
                                                .lineLimit(1)
                                            Text(song.artist)
                                                .font(.system(size: 12))
                                                .foregroundStyle(MusicXTheme.muted)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Button { toggleFavorite(song) } label: {
                                        Image(systemName: favorites.contains(song.id) ? "heart.fill" : "heart")
                                            .font(.system(size: 19, weight: .medium))
                                            .foregroundStyle(favorites.contains(song.id) ? MusicXTheme.blue : MusicXTheme.muted)
                                            .frame(width: 30, height: 48)
                                    }
                                    .buttonStyle(.plain)
                                    Button { selectManually(song) } label: {
                                        Image(systemName: currentSong?.id == song.id && playerStore.isPlaying ? "pause.circle" : "play.circle")
                                            .font(.system(size: 25, weight: .regular))
                                            .foregroundStyle(.white.opacity(0.92))
                                            .frame(width: 34, height: 48)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(currentSong?.id == song.id ? Color(red: 0.10, green: 0.15, blue: 0.29) : Color.white.opacity(0.012), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .overlay(alignment: .bottom) {
                                    if currentSong?.id != song.id {
                                        Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 10)
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 24)
                    }
                } else {
                    HStack {
                        Text("歌手")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(libraryArtists.count) 位")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MusicXTheme.muted)
                    }
                    if libraryArtists.isEmpty {
                        emptyState(icon: "person.2", title: "暂无歌手", detail: "最近播放或收藏歌曲后，歌手会自动整理在这里")
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        VStack(spacing: 3) {
                            ForEach(libraryArtists) { item in
                                Button {
                                    searchText = item.artist
                                    selectedTab = .search
                                } label: {
                                    HStack(spacing: 14) {
                                        songArtwork(item.song.onlineSong, tint: item.song.tint, size: 48)
                                            .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.artist).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                            Text("\(item.count) 首歌曲").font(.system(size: 12)).foregroundStyle(MusicXTheme.muted)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(MusicXTheme.muted)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 0)
            .padding(.bottom, 20)
        }
    }

    private func libraryShortcutCard(
        title: String,
        count: String,
        symbol: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(count).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 94)
            .padding(.horizontal, 6)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func pageHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 34, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(MusicXTheme.muted)
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(MusicXTheme.muted)
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 23, weight: .bold))
            Spacer()
            Text(detail).font(.system(size: 12, weight: .medium)).foregroundStyle(MusicXTheme.muted)
        }
    }

    @ViewBuilder
    private func homeSectionTitle(_ title: String, action: (() -> Void)?, actionTitle: String = "查看全部") -> some View {
        if let action {
            Button(action: action) {
                HStack(spacing: 10) {
                    Capsule().fill(MusicXTheme.blue).frame(width: 3, height: 21)
                    Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Text(actionTitle).font(.system(size: 12, weight: .medium)).foregroundStyle(MusicXTheme.muted)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(MusicXTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                Capsule().fill(MusicXTheme.blue).frame(width: 3, height: 21)
                Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Spacer()
            }
            .contentShape(Rectangle())
        }
    }

    private func homeSongRow(_ song: AppSong, artworkName: String? = nil) -> some View {
        Button { selectManually(song) } label: {
            HStack(spacing: 12) {
                songArtwork(song.onlineSong, tint: song.tint, size: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(song.artist).font(.system(size: 12)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let duration = song.onlineSong?.duration, duration > 0 {
                    Text(playerTime(duration)).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(MusicXTheme.muted)
                }
            }.contentShape(Rectangle()).padding(.vertical, 7)
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func songArtwork(_ song: MusicSong?, tint: Color, size: CGFloat) -> some View {
        if let song {
            SongArtworkView(song: song, tint: tint, size: size)
        } else {
            artworkFallback(tint: tint).frame(width: size, height: size)
        }
    }

    private func artworkFallback(tint: Color) -> some View {
        MusicArtworkPlaceholder(seed: "musicx-default", tint: tint)
    }

    private func songRow(_ song: AppSong, number: String? = nil, startsSearchQueue: Bool = false) -> some View {
        HStack(spacing: 13) {
            songArtwork(song.onlineSong, tint: song.tint, size: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button { startsSearchQueue ? playSearchResult(song) : selectManually(song) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(song.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(song.artist).font(.system(size: 12)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                        if let source = song.onlineSong?.source,
                           source == .spotify || source == .youtube || source == .youtubeMusic {
                            sourceIcon(source)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button { toggleFavorite(song) } label: {
                Image(systemName: favorites.contains(song.id) ? "heart.fill" : "heart")
                    .font(.system(size: 17)).foregroundStyle(favorites.contains(song.id) ? MusicXTheme.blue : MusicXTheme.muted)
            }
            Button { startsSearchQueue ? playSearchResult(song) : selectManually(song) } label: {
                Image(systemName: currentSong?.id == song.id && playerStore.isPlaying ? "pause.circle.fill" : "play.circle")
                    .font(.system(size: 25)).foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private func albumTile(song: MusicSong) -> some View {
        Button { discoveryRoute = .album(title: song.album?.isEmpty == false ? song.album! : song.title, artist: song.artist) } label: {
            ZStack(alignment: .bottomLeading) {
                songArtwork(song, tint: MusicXTheme.blue, size: 132)
                LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.album?.isEmpty == false ? song.album! : song.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(song.artist).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.82)).lineLimit(1)
                }.padding(.leading, 9).padding(.bottom, 9)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(.black.opacity(0.36), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(7)
            }.frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func chartTile(_ title: String, subtitle: String, rank: String, icon: String, color: Color, width: CGFloat) -> some View {
        return Button { discoveryRoute = .chart(title) } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.12, green: 0.13, blue: 0.23), location: 0.0),
                                .init(color: Color(red: 0.075, green: 0.09, blue: 0.17), location: 0.62),
                                .init(color: Color(red: 0.035, green: 0.05, blue: 0.11), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RadialGradient(
                    colors: [color.opacity(0.88), color.opacity(0.36), .clear],
                    center: UnitPoint(x: 0.82, y: 0.18),
                    startRadius: 1,
                    endRadius: width * 0.82
                )
                LinearGradient(
                    colors: [.clear, Color(red: 0.025, green: 0.035, blue: 0.085).opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(rank).font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.82)).lineLimit(1).minimumScaleFactor(0.72)
                }.padding(12)
            }
            .frame(width: width, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(color.opacity(0.48), lineWidth: 0.9))
            .shadow(color: color.opacity(0.16), radius: 10, y: 4)
        }.buttonStyle(.plain)
    }

    private var miniPlayer: some View {
        HStack(spacing: 10) {
            Button { if currentSong != nil { isPlayerPresented = true } } label: {
                HStack(spacing: 10) {
                    Group {
                        if currentSong == nil {
                            HomeArtwork(name: "player_cover").frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        } else {
                            songArtwork(currentSong?.onlineSong, tint: currentSong?.tint ?? MusicXTheme.blue, size: 40)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(currentSong?.title ?? "尚未播放")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(currentSong?.artist ?? "选择一首歌曲开始聆听")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { stepSong(by: -1) } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92)).frame(width: 30, height: 46)
            }.buttonStyle(.plain).disabled(playbackQueue.isEmpty)
            Button { if currentSong != nil { playerStore.togglePlayback() } } label: {
                Group {
                    if isResolvingSong || playerStore.isBuffering { ProgressView().tint(.white) }
                    else { Image(systemName: playerStore.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 19, weight: .bold)).foregroundStyle(.white) }
                }
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.22), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 1))
            }.buttonStyle(.plain).disabled(currentSong == nil)
            Button { stepSong(by: 1) } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92)).frame(width: 30, height: 46)
            }.buttonStyle(.plain).disabled(playbackQueue.isEmpty)
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.10, green: 0.12, blue: 0.27).opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.40, green: 0.31, blue: 0.66).opacity(0.34), Color(red: 0.08, green: 0.11, blue: 0.25).opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.30), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.30), radius: 16, y: 7)
        .padding(.horizontal, 12)
    }

        private var progressFraction: CGFloat {
        guard playerStore.duration > 0 else { return 0 }
        return CGFloat(min(max(playerStore.currentTime / playerStore.duration, 0), 1))
    }

    @State private var playerDisplayMode: PlayerDisplayMode = .artwork
    @State private var isShuffleEnabled = false
    @State private var repeatMode = 0
    @State private var resolvedArtworkURL: URL?
    @State private var lyricLines: [PlayerLyricLine] = []
    @State private var lyricsUnavailable = false

    private var nowPlayingPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                    // Fixed top navigation.
                    HStack {
                        Button { isPlayerPresented = false } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 19, weight: .semibold))
                        }
                        Spacer()
                        Text("正在播放").font(.system(size: 18, weight: .semibold))
                        Spacer()
                        Menu {
                            Button("播放队列", systemImage: "list.bullet") { playerDisplayMode = .queue }
                            Button("歌词", systemImage: "quote.bubble") { playerDisplayMode = .lyrics }
                            Button("封面", systemImage: "square") { playerDisplayMode = .artwork }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.top, 8)

                    // The entire middle region is reserved for artwork or lyrics.
                    // Artwork stays square and centered; lyrics use the full available region.
                    GeometryReader { contentGeometry in
                        if playerDisplayMode != .artwork {
                            playerVisualContent
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            let artworkSize = min(contentGeometry.size.width - 48, contentGeometry.size.height - 20)
                            playerVisualContent
                                .frame(width: max(0, artworkSize), height: max(0, artworkSize))
                                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                                .shadow(color: (currentSong?.tint ?? MusicXTheme.blue).opacity(0.28), radius: 30, y: 14)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 18)
                    .contentShape(Rectangle())

                    // Fixed lower controls: track information, timeline and transport.
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(currentSong?.title ?? "尚未选择歌曲")
                                .font(.system(size: 27, weight: .bold))
                                .foregroundStyle(.white).lineLimit(1)
                            Text(currentSong?.artist ?? "选择一首歌曲开始聆听")
                                .font(.system(size: 16)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                            if let album = currentSong?.album, !album.isEmpty {
                                Button {
                                    if let song = currentSong?.onlineSong {
                                        isPlayerPresented = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            discoveryRoute = .album(title: song.album?.isEmpty == false ? song.album! : song.title, artist: song.artist)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(album).lineLimit(1)
                                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.58))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer(minLength: 4)
                        Button { if let currentSong { toggleFavorite(currentSong) } } label: {
                            Image(systemName: currentSong.map { favorites.contains($0.id) } == true ? "heart.fill" : "heart")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(currentSong.map { favorites.contains($0.id) } == true ? MusicXTheme.blue : .white.opacity(0.82))
                        }
                        .disabled(currentSong == nil)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 10)

                    VStack(spacing: 5) {
                        Slider(
                            value: Binding(
                                get: {
                                    isSeekingProgress
                                        ? seekPreviewTime
                                        : (playerStore.duration > 0 ? min(playerStore.currentTime, playerStore.duration) : 0)
                                },
                                set: { seekPreviewTime = $0 }
                            ),
                            in: 0...max(playerStore.duration, 1),
                            onEditingChanged: { editing in
                                if editing {
                                    // Start the preview thumb at the actual playback position.
                                    seekPreviewTime = min(playerStore.currentTime, playerStore.duration)
                                    isSeekingProgress = true
                                } else {
                                    isSeekingProgress = false
                                    playerStore.seek(to: seekPreviewTime)
                                }
                            }
                        )
                        .tint(MusicXTheme.blue)
                        .disabled(playerStore.duration <= 0)
                        HStack {
                            Text(playerTime(isSeekingProgress ? seekPreviewTime : playerStore.currentTime))
                            Spacer()
                            Text(playerTime(playerStore.duration))
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(MusicXTheme.muted)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)

                    HStack(spacing: 0) {
                        Button { stepSong(by: -1) } label: {
                            Image(systemName: "backward.end.fill").font(.system(size: 27))
                                .foregroundStyle(.white).frame(maxWidth: .infinity)
                        }
                        Button { if currentSong != nil { playerStore.togglePlayback() } } label: {
                            Group {
                                if isResolvingSong || playerStore.isBuffering {
                                    ProgressView().tint(MusicXTheme.background)
                                } else {
                                    Image(systemName: playerStore.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 28, weight: .bold)).foregroundStyle(MusicXTheme.background)
                                }
                            }
                            .frame(width: 74, height: 74).background(.white, in: Circle())
                        }
                        .frame(maxWidth: .infinity)
                        Button { stepSong(by: 1) } label: {
                            Image(systemName: "forward.end.fill").font(.system(size: 27))
                                .foregroundStyle(.white).frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: geometry.size.width - 56, alignment: .center)
                    .padding(.top, 10)

                    HStack {
                        Button {
                            isShuffleEnabled.toggle()
                            resetShuffleHistory()
                        } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(isShuffleEnabled ? MusicXTheme.blue : .white.opacity(0.65))
                        }
                        Spacer()
                        HStack(spacing: 30) {
                            ForEach(PlayerDisplayMode.allCases, id: \.self) { mode in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        playerDisplayMode = mode
                                    }
                                } label: {
                                    VStack(spacing: 11) {
                                        Text(mode.title)
                                            .font(.system(size: 15, weight: playerDisplayMode == mode ? .semibold : .medium))
                                            .foregroundStyle(playerDisplayMode == mode ? .white : MusicXTheme.muted)
                                        Rectangle()
                                            .fill(playerDisplayMode == mode ? MusicXTheme.blue : .clear)
                                            .frame(width: 60, height: 2.5)
                                    }
                                    .frame(minWidth: 48)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(mode.title)
                                .accessibilityAddTraits(playerDisplayMode == mode ? .isSelected : [])
                            }
                        }
                        Spacer()
                        Button { repeatMode = (repeatMode + 1) % 3 } label: {
                            Image(systemName: repeatMode == 2 ? "repeat.1" : "repeat")
                                .foregroundStyle(repeatMode == 0 ? .white.opacity(0.65) : MusicXTheme.blue)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 34)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                .simultaneousGesture(DragGesture(minimumDistance: 24, coordinateSpace: .global).onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    if value.startLocation.y <= 120,
                       vertical > 110,
                       vertical > abs(horizontal) * 1.25 {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            isPlayerPresented = false
                        }
                        return
                    }
                    guard value.startLocation.x <= 28,
                          horizontal > 80,
                          horizontal > abs(vertical) * 1.25 else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        isPlayerPresented = false
                    }
                })
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            .background {
                playerArtwork
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: 65)
                    .overlay(MusicXTheme.background.opacity(0.56))
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .task(id: currentSong?.id) { await loadPlayerMetadata() }
    }

    private var activeLyricIndex: Int {
        guard !lyricLines.isEmpty else { return 0 }
        return lyricLines.lastIndex(where: { $0.time <= playerStore.currentTime }) ?? 0
    }

    @MainActor
    private func loadPlayerMetadata() async {
        guard let song = currentSong?.onlineSong else {
            resolvedArtworkURL = nil
            lyricLines = []
            lyricsUnavailable = true
            return
        }
        resolvedArtworkURL = song.artworkURL
        lyricLines = []
        lyricsUnavailable = false
        let service = GDStudioMetadataService()
        async let artwork = try? service.artworkURL(for: song)
        async let lyrics = try? service.lyrics(for: song)
        let artworkResult = await artwork
        let lyricsResult = await lyrics
        guard !Task.isCancelled, currentSong?.onlineSong?.id == song.id else { return }
        if let artworkResult { resolvedArtworkURL = artworkResult }
        if let lyricsResult {
            lyricLines = parseLyrics(lyricsResult.original)
        }
        lyricsUnavailable = lyricLines.isEmpty
    }

    private func parseLyrics(_ raw: String) -> [PlayerLyricLine] {
        raw.components(separatedBy: .newlines).compactMap { line in
            guard let close = line.firstIndex(of: "]"),
                  let open = line.firstIndex(of: "[") else { return nil }
            let stamp = String(line[line.index(after: open)..<close])
            let parts = stamp.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { return nil }
            let text = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return PlayerLyricLine(time: minutes * 60 + seconds, text: text)
        }.sorted { $0.time < $1.time }
    }

    private var playerQueueContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("播放队列").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text("\(playbackQueue.count) 首").font(.system(size: 12, weight: .medium)).foregroundStyle(MusicXTheme.muted)
                Button("清空") { clearQueue() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MusicXTheme.muted)
                    .disabled(playbackQueue.isEmpty || (playbackQueue.count == 1 && currentSong != nil))
            }
            .padding(.horizontal, 6)
            if playbackQueue.isEmpty {
                Spacer()
                Text("播放队列为空").font(.system(size: 15)).foregroundStyle(MusicXTheme.muted).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(playbackQueue) { song in
                            let active = song.id == currentSong?.id
                            HStack(spacing: 8) {
                                Button { selectManually(song) } label: {
                                    HStack(spacing: 12) {
                                        songArtwork(song.onlineSong, tint: song.tint, size: 42)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(song.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(active ? MusicXTheme.blue : .white).lineLimit(1)
                                            Text(song.artist).font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                                        }
                                        Spacer(minLength: 4)
                                        if active { Image(systemName: playerStore.isPlaying ? "waveform" : "pause.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(MusicXTheme.blue) }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button { removeFromQueue(song) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(MusicXTheme.muted)
                                        .frame(width: 30, height: 38)
                                }
                                .buttonStyle(.plain)
                                .disabled(active)
                                .opacity(active ? 0.25 : 1)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .background(active ? MusicXTheme.blue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MusicXTheme.surface.opacity(0.28), in: RoundedRectangle(cornerRadius: 22))
    }
    @ViewBuilder
    private var playerVisualContent: some View {
        switch playerDisplayMode {
        case .queue:
            playerQueueContent
        case .lyrics:
            if lyricLines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble").font(.system(size: 34, weight: .light)).foregroundStyle(MusicXTheme.blue)
                    Text(lyricsUnavailable ? "暂时没有找到歌词" : "正在获取歌词").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    Text(lyricsUnavailable ? "当前音源没有提供可用的歌词数据。" : "请稍候，正在读取歌词。").font(.system(size: 12)).foregroundStyle(MusicXTheme.muted).multilineTextAlignment(.center)
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MusicXTheme.surface.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            ForEach(Array(lyricLines.enumerated()), id: \.element.id) { index, line in
                                Text(line.text)
                                    .font(.system(size: index == activeLyricIndex ? 22 : 16, weight: index == activeLyricIndex ? .bold : .medium))
                                    .foregroundStyle(index == activeLyricIndex ? .white : MusicXTheme.muted)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .id(line.id)
                            }
                        }
                        .padding(.horizontal, 26)
                        .padding(.vertical, 34)
                    }
                    .onChange(of: activeLyricIndex) { _, index in
                        guard lyricLines.indices.contains(index) else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(lyricLines[index].id, anchor: .center)
                        }
                    }
                    .onAppear {
                        guard lyricLines.indices.contains(activeLyricIndex) else { return }
                        proxy.scrollTo(lyricLines[activeLyricIndex].id, anchor: .center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MusicXTheme.surface.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
        case .artwork:
            playerArtwork
        }
    }

    @ViewBuilder
    private var playerArtwork: some View {
        if let url = resolvedArtworkURL ?? currentSong?.onlineSong?.artworkURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    artworkPlaceholder
                }
            }
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(LinearGradient(
                colors: [currentSong?.tint ?? MusicXTheme.blue, Color(red: 0.025, green: 0.045, blue: 0.075)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay(Image(systemName: "waveform").font(.system(size: 76, weight: .ultraLight)).foregroundStyle(.white.opacity(0.85)))
    }

    private var playbackQueue: [AppSong] {
        var items = hasCustomPlaybackQueue ? playbackQueueSongs : (songs + onlineResults)
        if let currentSong, !items.contains(where: { $0.id == currentSong.id }) {
            items.insert(currentSong, at: 0)
        }
        var seen = Set<Int>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func qualityDisplayName(_ quality: MusicQuality) -> String {
        switch quality {
        case .standard: "标准音质"
        case .high: "高音质"
        case .lossless: "无损音质"
        case .hires: "Hi-Res"
        }
    }

    private func playerTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func stepSong(by offset: Int) {
        let queue = playbackQueue
        guard !queue.isEmpty, offset == -1 || offset == 1 else { return }
        let index = queue.firstIndex(where: { $0.id == currentSong?.id }) ?? 0
        if isShuffleEnabled && queue.count > 1 {
            if offset < 0 {
                guard let previousID = shuffleHistory.popLast(),
                      let previous = queue.first(where: { $0.id == previousID }),
                      let currentSong else { return }
                shuffleForwardHistory.insert(currentSong.id, at: 0)
                select(previous)
            } else if !shuffleForwardHistory.isEmpty {
                guard let nextID = shuffleForwardHistory.first,
                      let next = queue.first(where: { $0.id == nextID }),
                      let currentSong else { return }
                shuffleForwardHistory.removeFirst()
                shuffleHistory.append(currentSong.id)
                select(next)
            } else {
                selectRandomNextTrack(from: queue)
            }
            return
        }

        let nextIndex = index + offset
        if queue.indices.contains(nextIndex) {
            select(queue[nextIndex])
        } else if repeatMode == 1 {
            select(offset > 0 ? queue[0] : queue[queue.count - 1])
        }
    }

    private func selectRandomNextTrack(from queue: [AppSong]) {
        guard let currentSong else { return }
        let candidates = queue.filter { $0.id != currentSong.id }
        guard let next = candidates.randomElement() else { return }
        shuffleHistory.append(currentSong.id)
        shuffleForwardHistory.removeAll()
        select(next)
    }

    /// A resolved stream URL can expire before playback starts. Invalidate the cached
    /// URL and resolve the same track once before giving up and advancing the queue.
    private func retryCurrentSongWithFreshURL() {
        guard let song = currentSong, let onlineSong = song.onlineSong,
              !refreshedPlaybackSongIDs.contains(song.id) else {
            advanceAfterPlaybackFailure()
            return
        }
        refreshedPlaybackSongIDs.insert(song.id)
        playbackTask?.cancel()
        playbackRequestID = UUID()
        let requestID = playbackRequestID
        playerStore.pauseForTrackChange()
        isResolvingSong = true
        playbackTask = Task {
            defer {
                if playbackRequestID == requestID { isResolvingSong = false }
            }
            do {
                let resolver = LXMusicURLResolver()
                let url = try await resolver.resolveFresh(song: onlineSong, quality: selectedMusicQuality)
                try Task.checkCancellation()
                guard playbackRequestID == requestID else { return }
                playerStore.play(url: url, title: onlineSong.title, artist: onlineSong.artist,
                                 album: onlineSong.album, artworkURL: onlineSong.artworkURL, artworkSong: onlineSong)
            } catch is CancellationError {
                return
            } catch {
                guard playbackRequestID == requestID else { return }
                searchError = "重新获取播放地址失败：\(error.localizedDescription)"
                advanceAfterPlaybackFailure()
            }
        }
    }

    /// Skip a track that failed after selection or during AVPlayer playback.
    /// Each track is attempted at most once per user-initiated playback selection.
    private func advanceAfterPlaybackFailure() {
        guard let failedSong = currentSong else { return }
        failedPlaybackSongIDs.insert(failedSong.id)
        let queue = playbackQueue
        guard failedPlaybackSongIDs.count < queue.count,
              let currentIndex = queue.firstIndex(where: { $0.id == failedSong.id }) else {
            searchError = "队列中的歌曲均无法播放，请更换音源或稍后重试"
            return
        }

        let remaining = queue.filter { !failedPlaybackSongIDs.contains($0.id) }
        guard !remaining.isEmpty else {
            searchError = "队列中的歌曲均无法播放，请更换音源或稍后重试"
            return
        }

        // A failed track breaks the shuffle forward path. Keep the successful
        // backward history, but do not let Next return to a failed selection path.
        if isShuffleEnabled {
            shuffleHistory.removeAll { failedPlaybackSongIDs.contains($0) }
            shuffleForwardHistory.removeAll()
        }

        let next: AppSong
        if isShuffleEnabled, let random = remaining.randomElement() {
            next = random
        } else {
            let ordered = Array(queue.dropFirst(currentIndex + 1)) + Array(queue.prefix(currentIndex))
            guard let candidate = ordered.first(where: { !failedPlaybackSongIDs.contains($0.id) }) else {
                searchError = "队列中的歌曲均无法播放，请更换音源或稍后重试"
                return
            }
            next = candidate
        }
        select(next, isFailureFallback: true)
    }

    private func playNextAfterNaturalFinish() {
        guard let currentSong else { return }
        if repeatMode == 2 {
            playerStore.replayCurrentTrack()
            return
        }
        let queue = playbackQueue
        guard let index = queue.firstIndex(where: { $0.id == currentSong.id }) else { return }
        if isShuffleEnabled && queue.count > 1 {
            selectRandomNextTrack(from: queue)
            return
        }
        let nextIndex = index + 1
        if queue.indices.contains(nextIndex) { select(queue[nextIndex]) }
        else if repeatMode == 1, let first = queue.first { select(first) }
    }

    private func resetShuffleHistory() {
        shuffleHistory.removeAll()
        shuffleForwardHistory.removeAll()
    }

    private func removeFromQueue(_ song: AppSong) {
        if !hasCustomPlaybackQueue {
            playbackQueueSongs = playbackQueue
            hasCustomPlaybackQueue = true
        }
        playbackQueueSongs.removeAll { $0.id == song.id }
        let remainingIDs = Set(playbackQueue.map(\.id))
        shuffleHistory.removeAll { !remainingIDs.contains($0) }
        shuffleForwardHistory.removeAll { !remainingIDs.contains($0) }
    }

    private func clearQueue() {
        hasCustomPlaybackQueue = true
        playbackQueueSongs = currentSong.map { [$0] } ?? []
        resetShuffleHistory()
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    if tab == .search && selectedTab != .search {
                        searchSuggestions = ["十年", "突然好想你", "晴天", "青花瓷", "稻香", "后来", "演员", "夜曲", "富士山下", "海阔天空"].shuffled().prefix(4).map { $0 }
                    }
                    withAnimation(.easeInOut(duration: 0.20)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 25, weight: .medium))
                            .frame(height: 29)
                            .shadow(color: selectedTab == tab ? Color(red: 0.28, green: 0.58, blue: 1).opacity(0.72) : .clear,
                                    radius: selectedTab == tab ? 9 : 0, y: 0)
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab
                        ? Color(red: 0.36, green: 0.66, blue: 1)
                        : .white.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .frame(height: 66)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Color(red: 0.045, green: 0.055, blue: 0.12).opacity(0.96)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 0.8)
                }
        }
    }

    private func playSearchResult(_ song: AppSong) {
        // A search result selection replaces the active queue with this exact
        // result set, keeping the tapped song at its natural position.
        playbackQueueSongs = filteredSongs
        hasCustomPlaybackQueue = true
        resetShuffleHistory()
        select(song)
    }

    private func playDiscoverySong(_ song: MusicSong) {
        // Keep the discovery route mounted while playback starts.
        let appSong = AppSong(id: stableSongID(song), title: song.title, artist: song.artist,
                              album: song.album ?? "", tint: MusicXTheme.blue, onlineSong: song)
        selectManually(appSong)
    }

    private func selectManually(_ song: AppSong) {
        // Tapping the current track only toggles playback; it must not discard
        // the user's shuffle back/forward navigation path.
        if currentSong?.id != song.id {
            resetShuffleHistory()
        }
        select(song)
    }

    private func select(_ song: AppSong, isFailureFallback: Bool = false) {
        if !isFailureFallback {
            failedPlaybackSongIDs.removeAll()
            refreshedPlaybackSongIDs.removeAll()
        }
        if currentSong?.id == song.id {
            if playerStore.isPlaying { playerStore.pause() }
            else if isResolvingSong { return }
            else { playerStore.resume() }
        } else if let onlineSong = song.onlineSong {
            // Cancel URL lookups for the previous selection and silence it immediately.
            playbackTask?.cancel()
            playbackRequestID = UUID()
            let requestID = playbackRequestID
            // Pause the old stream but retain its AVPlayer item and Now Playing
            // ownership while the next stream URL resolves.
            playerStore.pauseForTrackChange()
            currentSong = song
            isResolvingSong = true
            playbackTask = Task {
                defer {
                    if playbackRequestID == requestID { isResolvingSong = false }
                }
                do {
                    let url = try await LXMusicURLResolver().resolve(song: onlineSong, quality: selectedMusicQuality)
                    try Task.checkCancellation()
                    guard playbackRequestID == requestID else { return }
                    currentSong = song
                    playerStore.play(url: url, title: onlineSong.title, artist: onlineSong.artist,
                                     album: onlineSong.album, artworkURL: onlineSong.artworkURL, artworkSong: onlineSong)
                } catch is CancellationError {
                    return
                } catch {
                    guard playbackRequestID == requestID else { return }
                    isResolvingSong = false
                    searchError = error.localizedDescription
                    advanceAfterPlaybackFailure()
                }
            }
        } else {
            currentSong = song
        }
        var ids = recentIDs.split(separator: ",").compactMap { Int($0) }
        ids.removeAll { $0 == song.id }
        ids.insert(song.id, at: 0)
        recentIDs = ids.prefix(30).map { String($0) }.joined(separator: ",")
        if let onlineSong = song.onlineSong {
            var stored = decodeLibrarySongs(recentSongsJSON)
            stored.removeAll { stableSongID($0) == song.id }
            stored.insert(onlineSong, at: 0)
            recentSongsJSON = encodedLibrarySongs(Array(stored.prefix(50)))
        }
    }

    @MainActor
    private func searchOnline(_ keyword: String) async {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { onlineResults = []; searchError = nil; return }
        let requestID = UUID()
        searchRequestID = requestID
        isSearching = true
        searchError = nil
        onlineResults = []
        defer {
            if searchRequestID == requestID { isSearching = false }
        }

        let service = GDStudioMusicSearchService()
        var received: [[MusicSong]] = []
        await withTaskGroup(of: [MusicSong].self) { group in
            for source in [MusicSource.netease, .qq, .kuwo, .kugou, .migu] {
                group.addTask {
                    (try? await service.search(keyword: query, source: source, count: 50)) ?? []
                }
            }
            for await result in group {
                guard !Task.isCancelled,
                      searchRequestID == requestID,
                      searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { continue }
                if !result.isEmpty {
                    received.append(result)
                    var merged: [MusicSong] = []
                    let maxCount = received.map(\.count).max() ?? 0
                    for index in 0..<maxCount {
                        for sourceResults in received where sourceResults.indices.contains(index) {
                            merged.append(sourceResults[index])
                        }
                    }
                    var seen = Set<String>()
                    let uniqueResults = merged.filter { item in
                        let title = normalizedSearchKey(item.title)
                        let artist = normalizedArtistSearchKey(item.artist)
                        guard !title.isEmpty, !artist.isEmpty else { return true }
                        let version = searchVersionMarkers(item)
                        let durationKey = item.duration.map { String(Int($0.rounded())) } ?? "unknown"
                        return seen.insert("\(title)|\(artist)|\(version)|\(durationKey)").inserted
                    }
                    onlineResults = Array(uniqueResults.prefix(50)).map { item in
                        AppSong(id: stableSongID(item), title: item.title, artist: item.artist,
                                album: item.album ?? "", tint: searchTint(for: item.source), onlineSong: item)
                    }
                }
            }
        }
        guard !Task.isCancelled,
              searchRequestID == requestID,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
        if onlineResults.isEmpty { searchError = "当前音源暂未返回结果" }
    }

    @MainActor
    private func loadHomeSongs() async {
        guard songs.isEmpty, !isLoadingHomeSongs else { return }
        isLoadingHomeSongs = true
        homeLoadError = nil
        defer { isLoadingHomeSongs = false }
        do {
            let latestTracks = try await GDStudioMusicSearchService().toplist("新歌榜", count: 50)
            guard !Task.isCancelled else { return }
            songs = latestTracks.map { item in
                AppSong(id: stableSongID(item), title: item.title, artist: item.artist,
                        album: item.album ?? "", tint: MusicXTheme.blue, onlineSong: item)
            }
            recommendationSongs = Array(songs.shuffled().prefix(6))
            if songs.isEmpty {
                homeLoadError = "网易云新歌榜暂时没有返回歌曲，请稍后重试"
            }
        } catch {
            homeLoadError = "新歌榜加载失败：\(error.localizedDescription)"
        }
    }

    private func openSearch(query: String) {
        searchText = query
        onlineResults = []
        selectedTab = .search
        searchFieldFocused = false
    }

    @ViewBuilder
    private func sourceIcon(_ source: MusicSource) -> some View {
        switch source {
        case .spotify:
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.78, blue: 0.36))
                .accessibilityLabel("Spotify")
        case .youtube:
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.12, blue: 0.12))
                .accessibilityLabel("YouTube")
        case .youtubeMusic:
            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.18, blue: 0.22))
                .accessibilityLabel("YouTube Music")
        default:
            EmptyView()
        }
    }

    private func searchTint(for source: MusicSource) -> Color {
        switch source {
        case .netease: MusicXTheme.blue
        case .qq: .purple
        case .kuwo: .teal
        case .kugou: .orange
        case .migu: .pink
        case .qishui, .youtubeMusic, .youtube, .spotify: MusicXTheme.muted
        }
    }

    private func normalizedSearchKey(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private func normalizedArtistSearchKey(_ value: String) -> String {
        value.split(whereSeparator: { $0 == "/" || $0 == "、" || $0 == "," || $0 == "，" })
            .map { normalizedSearchKey(String($0)) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "+")
    }

    private func searchVersionMarkers(_ song: MusicSong) -> String {
        let text = "\(song.title) \(song.album ?? "")".lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        let markers = [
            "live", "remix", "instrumental", "伴奏", "纯音乐", "现场", "演唱会",
            "翻唱", "cover", "acoustic", "不插电", "demo", "示范", "合唱",
            "remaster", "重制", "sped up", "slowed", "加速", "降速", "dj"
        ]
        return markers.filter { text.contains($0) }.sorted().joined(separator: ",")
    }

    private func stableSongID(_ song: MusicSong) -> Int {
        let hash = song.id.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        return Int(hash & 0x7FFFFFFFFFFFFFFF)
    }

    private func toggleFavorite(_ song: AppSong) {
        var ids = favorites
        var stored = decodeLibrarySongs(favoriteSongsJSON)
        if ids.contains(song.id) {
            ids.remove(song.id)
            stored.removeAll { stableSongID($0) == song.id }
        } else {
            ids.insert(song.id)
            if let onlineSong = song.onlineSong, !stored.contains(where: { stableSongID($0) == song.id }) {
                stored.insert(onlineSong, at: 0)
            }
        }
        favoriteIDs = ids.sorted().map { String($0) }.joined(separator: ",")
        favoriteSongsJSON = encodedLibrarySongs(stored)
    }

}

struct SongArtworkView: View {
    let song: MusicSong
    let tint: Color
    let size: CGFloat
    @State private var resolvedURL: URL?

    var body: some View {
        Group {
            if let url = resolvedURL ?? song.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: song.id) {
            // Prefer the provider-normalized artwork URL when an image ID exists;
            // retain the original NetEase picUrl as a fallback if metadata lookup fails.
            guard song.pictureID?.isEmpty == false else {
                resolvedURL = song.artworkURL
                return
            }
            if let metadataURL = try? await GDStudioMetadataService().artworkURL(for: song) {
                resolvedURL = metadataURL
            }
        }
    }

    private var fallback: some View {
        MusicArtworkPlaceholder(seed: song.id, tint: tint)
    }
}

/// Branded fallback artwork used only when a remote album cover is absent or unavailable.
private struct MusicArtworkPlaceholder: View {
    let seed: String
    let tint: Color

    private let palettes: [[Color]] = [
        [Color(red: 0.12, green: 0.36, blue: 0.68), Color(red: 0.035, green: 0.10, blue: 0.25), Color(red: 0.34, green: 0.72, blue: 0.98)],
        [Color(red: 0.34, green: 0.25, blue: 0.62), Color(red: 0.10, green: 0.08, blue: 0.28), Color(red: 0.68, green: 0.50, blue: 0.96)],
        [Color(red: 0.08, green: 0.42, blue: 0.48), Color(red: 0.025, green: 0.13, blue: 0.22), Color(red: 0.30, green: 0.82, blue: 0.78)],
        [Color(red: 0.42, green: 0.25, blue: 0.38), Color(red: 0.16, green: 0.07, blue: 0.20), Color(red: 0.94, green: 0.52, blue: 0.66)]
    ]

    private var paletteIndex: Int {
        Int(seed.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 } % UInt64(palettes.count))
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let palette = palettes[paletteIndex]
            ZStack {
                LinearGradient(colors: [palette[0], palette[1]], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(palette[2].opacity(0.34))
                    .frame(width: side * 0.72, height: side * 0.72)
                    .blur(radius: side * 0.12)
                    .offset(x: side * 0.18, y: -side * 0.20)
                Circle()
                    .stroke(.white.opacity(0.13), lineWidth: max(1, side * 0.008))
                    .frame(width: side * 0.72, height: side * 0.72)
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: max(1, side * 0.006))
                    .frame(width: side * 0.54, height: side * 0.54)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: side * 0.30, height: side * 0.30)
                Image(systemName: "waveform")
                    .font(.system(size: side * 0.27, weight: .light))
                    .foregroundStyle(.white.opacity(0.90))
                    .shadow(color: palette[2].opacity(0.45), radius: side * 0.08)
                HStack(spacing: max(2, side * 0.018)) {
                    ForEach(Array([0.30, 0.52, 0.76, 0.46, 0.64, 0.36].enumerated()), id: \.offset) { _, height in
                        Capsule().fill(.white.opacity(0.46)).frame(width: max(2, side * 0.018), height: side * height * 0.10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(side * 0.10)
                LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("MusicX 默认专辑封面")
    }
}

private struct MountainBackdrop: View {
    let variant: Int

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                LinearGradient(
                    colors: variant.isMultiple(of: 2)
                        ? [Color(red: 0.27, green: 0.39, blue: 0.61), Color(red: 0.10, green: 0.17, blue: 0.30), Color(red: 0.035, green: 0.07, blue: 0.13)]
                        : [Color(red: 0.47, green: 0.31, blue: 0.42), Color(red: 0.14, green: 0.20, blue: 0.34), Color(red: 0.035, green: 0.07, blue: 0.13)],
                    startPoint: .top, endPoint: .bottom
                )
                Circle()
                    .fill(Color(red: 1.0, green: 0.72, blue: 0.48).opacity(0.78))
                    .frame(width: size.width * 0.15)
                    .blur(radius: 15)
                    .position(x: size.width * 0.52, y: size.height * 0.48)
                Circle()
                    .fill(Color(red: 1.0, green: 0.77, blue: 0.53).opacity(0.62))
                    .frame(width: size.width * 0.075)
                    .position(x: size.width * 0.52, y: size.height * 0.48)
                MountainRidge(points: [0.62, 0.45, 0.58, 0.34, 0.55, 0.40, 0.64, 0.42, 0.60, 0.38, 0.68])
                    .fill(Color(red: 0.18, green: 0.27, blue: 0.43).opacity(0.86))
                MountainRidge(points: [0.75, 0.56, 0.70, 0.47, 0.72, 0.52, 0.78, 0.49, 0.71, 0.57, 0.82])
                    .fill(Color(red: 0.10, green: 0.19, blue: 0.32).opacity(0.94))
                MountainRidge(points: [0.88, 0.70, 0.82, 0.63, 0.89, 0.66, 0.80, 0.62, 0.86, 0.71, 0.94])
                    .fill(Color(red: 0.035, green: 0.09, blue: 0.16))
                LinearGradient(colors: [.clear, Color.black.opacity(0.42)], startPoint: .center, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

private struct MountainRidge: Shape {
    let points: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        path.move(to: CGPoint(x: 0, y: rect.height * points[0]))
        for index in 1..<points.count {
            let x = rect.width * CGFloat(index) / CGFloat(points.count - 1)
            path.addLine(to: CGPoint(x: x, y: rect.height * points[index]))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PlayerLyricLine: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

private struct SearchCategoryCard: View {
    let title: String
    let subtitle: String
    let asset: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    private var designGradient: [Color] {
        switch title {
        case "华语流行":
            [Color(red: 0.12, green: 0.41, blue: 0.84), Color(red: 0.07, green: 0.25, blue: 0.53), Color(red: 0.04, green: 0.11, blue: 0.25)]
        case "经典老歌":
            [Color(red: 0.73, green: 0.22, blue: 0.55), Color(red: 0.45, green: 0.13, blue: 0.38), Color(red: 0.14, green: 0.07, blue: 0.19)]
        case "轻音乐":
            [Color(red: 0.11, green: 0.62, blue: 0.50), Color(red: 0.07, green: 0.38, blue: 0.34), Color(red: 0.04, green: 0.13, blue: 0.18)]
        case "纯音乐":
            [Color(red: 0.50, green: 0.25, blue: 0.83), Color(red: 0.29, green: 0.14, blue: 0.51), Color(red: 0.09, green: 0.07, blue: 0.21)]
        case "摇滚":
            [Color(red: 0.83, green: 0.35, blue: 0.11), Color(red: 0.50, green: 0.20, blue: 0.07), Color(red: 0.15, green: 0.09, blue: 0.11)]
        default:
            [Color(red: 0.12, green: 0.57, blue: 0.77), Color(red: 0.07, green: 0.33, blue: 0.48), Color(red: 0.04, green: 0.11, blue: 0.21)]
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: designGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.25), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.8))
                    Spacer(minLength: 0)
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tint.opacity(0.82), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct FlowTags: View {
    let tags: [String]
    var body: some View {
        HStack(spacing: 9) {
            ForEach(tags, id: \.self) { tag in
                Text(tag).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MusicXTheme.muted)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(MusicXTheme.surface, in: Capsule())
            }
        }
    }
}
