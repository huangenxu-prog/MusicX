import SwiftUI

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
    let localFileURL: URL?

    init(id: Int, title: String, artist: String, album: String, tint: Color, onlineSong: MusicSong? = nil, localFileURL: URL? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.tint = tint
        self.onlineSong = onlineSong
        self.localFileURL = localFileURL
    }
}

private struct DownloadedTrack: Codable, Identifiable {
    let id: Int
    let song: MusicSong
    let fileName: String
}

private enum LibraryFilter: String, CaseIterable {
    case favorites = "收藏"
    case recent = "最近播放"
    case downloads = "下载"
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

struct ContentView: View {
    @State private var selectedTab: MainTab = .home
    @Namespace private var tabSelectionNamespace
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var libraryFilter: LibraryFilter = .favorites
    @State private var currentSong: AppSong?
    @State private var isSeekingProgress = false
    @State private var seekPreviewTime: TimeInterval = 0
    @StateObject private var playerStore = PlayerStore()
    @State private var onlineResults: [AppSong] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var isPlayerPresented = false
    @State private var playbackRequestID = UUID()
    @State private var playbackTask: Task<Void, Never>?
    @State private var playbackQueueSongs: [AppSong] = []
    @State private var hasCustomPlaybackQueue = false
    @State private var isResolvingSong = false
    @AppStorage("musicx.favoriteIDs") private var favoriteIDs = "1,3"
    @AppStorage("musicx.recentIDs") private var recentIDs = ""
    @AppStorage("musicx.downloadedTracks") private var downloadedTracksJSON = "[]"
    @AppStorage("musicx.playbackQuality") private var playbackQualityRaw = MusicQuality.high.rawValue

    private var selectedMusicQuality: MusicQuality {
        MusicQuality(rawValue: playbackQualityRaw) ?? .high
    }
    @State private var isDownloading = false
    @State private var downloadMessage: String?
    @State private var isDownloadAlertPresented = false

    private var favorites: Set<Int> {
        Set(favoriteIDs.split(separator: ",").compactMap { Int($0) })
    }

    private var recentSongs: [AppSong] {
        let ids = recentIDs.split(separator: ",").compactMap { Int($0) }
        return ids.compactMap { id in songs.first { $0.id == id } }
    }

    private var downloadedTracks: [DownloadedTrack] {
        guard let data = downloadedTracksJSON.data(using: .utf8),
              let tracks = try? JSONDecoder().decode([DownloadedTrack].self, from: data) else { return [] }
        return tracks
    }

    private var downloadedSongs: [AppSong] {
        let folder = downloadsDirectory
        return downloadedTracks.compactMap { track in
            let url = folder.appendingPathComponent(track.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return AppSong(id: track.id, title: track.song.title, artist: track.song.artist,
                           album: track.song.album ?? "", tint: MusicXTheme.blue,
                           onlineSong: track.song, localFileURL: url)
        }
    }

    private var isCurrentSongDownloaded: Bool {
        guard let currentSong else { return false }
        return downloadedSongs.contains { downloaded in downloaded.id == currentSong.id }
    }

    private var downloadsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicXDownloads", isDirectory: true)
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

    private var librarySongs: [AppSong] {
        switch libraryFilter {
        case .favorites: songs.filter { favorites.contains($0.id) }
        case .recent: recentSongs
        case .downloads: downloadedSongs
        }
    }

    var body: some View {
        ZStack {
            MusicXTheme.background.ignoresSafeArea()
            Group {
                switch selectedTab {
                case .home: homePage
                case .search: searchPage
                case .library: libraryPage
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MusicXTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !(selectedTab == .search && searchFieldFocused) {
                VStack(spacing: 8) {
                    miniPlayer
                    tabBar
                }
                .padding(.top, 8)
                .padding(.bottom, 0)
                .zIndex(20)
                .background {
                    LinearGradient(colors: [MusicXTheme.background.opacity(0.02), MusicXTheme.background.opacity(0.78)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $isPlayerPresented) { nowPlayingPage }
        .confirmationDialog("播放设置", isPresented: $isSettingsAlertPresented, titleVisibility: .visible) {
            Button("标准音质 · 128 kbps") { playbackQualityRaw = MusicQuality.standard.rawValue }
            Button("高音质 · 320 kbps") { playbackQualityRaw = MusicQuality.high.rawValue }
            Button("无损音质") { playbackQualityRaw = MusicQuality.lossless.rawValue }
            Button("Hi-Res") { playbackQualityRaw = MusicQuality.hires.rawValue }
            Button("取消", role: .cancel) { }
        } message: {
            Text("当前音质：\(qualityDisplayName(selectedMusicQuality))。不同音源实际支持的最高音质可能不同。")
        }
        .alert("下载歌曲", isPresented: $isDownloadAlertPresented) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(downloadMessage ?? "操作完成")
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
        .fullScreenCover(item: $discoveryRoute) { route in
            MusicDiscoveryPage(route: route, onClose: { discoveryRoute = nil },
                onPlay: { playDiscoverySong($0) },
                currentSong: currentSong?.onlineSong,
                isPlaying: playerStore.isPlaying,
                onTogglePlayback: { playerStore.togglePlayback() },
                onOpenPlayer: { isPlayerPresented = true },
                onQueueChanged: { playbackQueueSongs = $0.map { AppSong(id: stableSongID($0), title: $0.title, artist: $0.artist, album: $0.album ?? "", tint: MusicXTheme.blue, onlineSong: $0) }; hasCustomPlaybackQueue = true }, 
                currentTime: playerStore.currentTime,
                duration: playerStore.duration,
                onOpenPlaylist: { discoveryRoute = .playlist($0) },
                onSelectChart: { discoveryRoute = .chart($0) })
        }
        .task { await loadHomeSongs() }
    }

    private var homePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 15) {
                heroAndRecommendation
                chartSection
                newMusicSection
                albumSection
                editorialPlaylistSection
                forYouSection
            }
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.never)
    }

    private var heroAndRecommendation: some View {
        VStack(alignment: .leading, spacing: 10) { heroHeader; recommendationSection }
    }

    private var heroHeader: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HomeArtwork(name: "home_hero").frame(width: proxy.size.width, height: 170).clipped()
                    .overlay(LinearGradient(colors: [.black.opacity(0.06), .clear, MusicXTheme.background.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("发现音乐")
                            .font(.custom("STXingkai-SC-Bold", size: 38, relativeTo: .largeTitle))
                            .tracking(1.2)
                            .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.88, green: 0.84, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: Color(red: 0.43, green: 0.32, blue: 0.95).opacity(0.42), radius: 8, y: 3)
                        HStack(spacing: 8) {
                            Text("好音乐，总在心里")
                                .font(.system(size: 18, weight: .regular, design: .serif))
                                .tracking(2.0)
                                .foregroundStyle(.white.opacity(0.94))
                            HStack(alignment: .center, spacing: 3) {
                                ForEach([8.0, 14.0, 20.0, 12.0, 7.0], id: \.self) { height in
                                    Capsule().fill(Color(red: 0.86, green: 0.70, blue: 1.0).opacity(0.9))
                                        .frame(width: 2.5, height: height)
                                }
                            }
                            .shadow(color: Color.purple.opacity(0.45), radius: 5)
                        }
                    }
                    Spacer(minLength: 4)
                }.padding(.horizontal, 22).padding(.bottom, 4)
            }
        }
        .frame(height: 170).frame(maxWidth: .infinity).clipped()
        .background {
            GeometryReader { geometry in
                HomeArtwork(name: "home_hero")
                    .frame(width: geometry.size.width, height: geometry.size.height + geometry.safeAreaInsets.top)
                    .clipped()
                    .overlay(LinearGradient(colors: [.clear, MusicXTheme.background.opacity(0.96)], startPoint: .center, endPoint: .bottom))
                    .offset(y: -geometry.safeAreaInsets.top)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private var recommendationSection: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 14
            let gap: CGFloat = 10
            let width = max(0, (proxy.size.width - inset * 2 - gap) / 2)
            HStack(spacing: gap) {
                recommendationTile(title: "每日推荐", subtitle: "为你精选 · 每日更新", icon: "play.fill", colors: [Color(red: 0.16, green: 0.43, blue: 0.72), Color(red: 0.08, green: 0.20, blue: 0.39)], route: .daily, width: width)
                recommendationTile(title: "精选歌单", subtitle: "用音乐，遇见更好的自己", icon: "music.note.list", colors: [Color(red: 0.43, green: 0.26, blue: 0.63), Color(red: 0.20, green: 0.13, blue: 0.38)], route: .playlists, width: width)
            }.padding(.horizontal, inset)
        }.frame(height: 70)
    }

    private func recommendationTile(title: String, subtitle: String, icon: String, colors: [Color], route: MusicDiscoveryRoute, width: CGFloat) -> some View {
        let assetName = title == "每日推荐" ? "daily_recommend" : "featured_playlist"
        return Button { discoveryRoute = route } label: {
            ZStack(alignment: .leading) {
                HomeArtwork(name: assetName).frame(width: width, height: 70).clipped()
                LinearGradient(colors: [colors.last?.opacity(0.70) ?? .black.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 21, height: 21).background(.white.opacity(0.20), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.32), lineWidth: 0.8))
                    Spacer(minLength: 0)
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1).minimumScaleFactor(0.72).padding(.top, 1)
                }.padding(.leading, 12).padding(.vertical, 4)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(.black.opacity(0.24), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.34), lineWidth: 0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(6)
            }
            .frame(width: width, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.46), lineWidth: 1))
            .shadow(color: colors.first?.opacity(0.28) ?? .clear, radius: 10, y: 3)
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
                            Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5).padding(.leading, 42)
                        }
                    }
                }.padding(.horizontal, 20)
            }
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            homeSectionTitle("热门专辑", action: { discoveryRoute = .album(title: "DUO", artist: "陈奕迅") }).padding(.horizontal, 14)
            GeometryReader { proxy in
                let gap: CGFloat = 6
                let width = max(48, (proxy.size.width - 28 - gap * 4) / 5)
                HStack(spacing: gap) {
                    ForEach(0..<5, id: \.self) { index in
                        staticAlbumTile(index: index, width: width)
                    }
                }.padding(.horizontal, 14)
            }.frame(height: 64)
        }
    }

    private func staticAlbumTile(index: Int, width: CGFloat) -> some View {
        let titles = ["DUO", "最伟大的作品", "宇宙的有趣", "A-Lin", "幼鸟指南"]
        let artists = ["陈奕迅", "周杰伦", "告五人", "LINK", "毛不易"]
        return Button { discoveryRoute = .album(title: titles[index], artist: artists[index]) } label: {
            ZStack(alignment: .bottomLeading) {
                HomeArtwork(name: "album_0\(index + 1)")
                    .frame(width: width, height: 64)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titles[index]).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(artists[index]).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.86)).lineLimit(1)
                }.padding(.horizontal, 5).padding(.bottom, 5)
            }
            .frame(width: width, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
         }.buttonStyle(.plain)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            homeSectionTitle("排行榜", action: nil).padding(.horizontal, 14)
            GeometryReader { proxy in
                let width = max(0, (proxy.size.width - 44) / 3)
                HStack(spacing: 8) {
                    chartTile("热歌榜", subtitle: "当下最热的50首", rank: "01", icon: "crown.fill", color: Color(red: 0.95, green: 0.47, blue: 0.38), width: width)
                    chartTile("飙升榜", subtitle: "近期热度上升", rank: "02", icon: "flame.fill", color: Color(red: 0.61, green: 0.35, blue: 0.91), width: width)
                    chartTile("新歌榜", subtitle: "最新发布的50首", rank: "03", icon: "waveform", color: Color(red: 0.05, green: 0.70, blue: 0.83), width: width)
                }.padding(.horizontal, 14)
            }.frame(height: 70)
        }
    }

    private var editorialPlaylistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Capsule().fill(MusicXTheme.blue).frame(width: 4, height: 21)
                    Text("精选歌单").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    Text("· 编辑推荐").font(.system(size: 12, weight: .medium)).foregroundStyle(MusicXTheme.muted)
                    Spacer(minLength: 4)
                }
                Button { discoveryRoute = .playlists } label: {
                    HStack(spacing: 4) { Text("查看更多").font(.system(size: 13, weight: .medium)); Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)) }
                        .foregroundStyle(MusicXTheme.muted)
                }.buttonStyle(.plain)
            }.padding(.horizontal, 14)
            GeometryReader { proxy in
                let width = max(0, (proxy.size.width - 44) / 3)
                HStack(spacing: 8) {
                    editorialPlaylistCard(title: "午后放松", subtitle: "轻音乐 · 治愈 · 放松", width: width)
                    editorialPlaylistCard(title: "深夜独白", subtitle: "安静 · 思考 · 陪伴", width: width)
                    editorialPlaylistCard(title: "车载必听", subtitle: "旅途 · 驾驶 · 精选", width: width)
                }.padding(.horizontal, 14)
            }.frame(height: 76)
        }
    }

    private func editorialPlaylistCard(title: String, subtitle: String, width: CGFloat) -> some View {
        Button { discoveryRoute = .playlist(title) } label: {
            ZStack(alignment: .bottomLeading) {
                HomeArtwork(name: title == "午后放松" ? "playlist_relax" : title == "深夜独白" ? "playlist_night" : "playlist_drive")
                    .frame(width: width, height: 76).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.86)).lineLimit(1).minimumScaleFactor(0.7)
                }.padding(.leading, 8).padding(.bottom, 7)
                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(.black.opacity(0.35), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(8)
            }.frame(width: width, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.26), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private var forYouSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            homeSectionTitle("猜你喜欢", action: { recommendationSongs = Array(songs.shuffled().prefix(6)) }, actionTitle: "换一批").padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                let cardWidth = (UIScreen.main.bounds.width - 52) / 3
                HStack(spacing: 12) {
                    ForEach(0..<min(recommendationSongs.count, 6), id: \.self) { index in
                        let song = recommendationSongs[index]
                        Button { select(song) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HomeArtwork(name: "guess_0\((index % 3) + 1)")
                                    .frame(width: cardWidth, height: cardWidth)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                Text(song.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                Text(song.artist).font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                            }.frame(width: cardWidth, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 14)
            }.frame(height: (UIScreen.main.bounds.width - 52) / 3 + 46)
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
                Image(systemName: "magnifyingglass").foregroundStyle(MusicXTheme.muted)
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
            .padding(.horizontal, 16).frame(height: 54)
            .background(MusicXTheme.surface, in: RoundedRectangle(cornerRadius: 16))

            if searchText.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("热门搜索").font(.system(size: 18, weight: .bold))
                    FlowTags(tags: ["华语流行", "轻音乐", "经典老歌", "纯音乐", "摇滚"])
                }
                .padding(.top, 4)
                Text("输入关键词开始搜索").font(.system(size: 14)).foregroundStyle(MusicXTheme.muted)
            } else {
                HStack {
                    Text("搜索结果").font(.system(size: 19, weight: .bold))
                        .id("searchResults")
                    Spacer()
                    Text(isSearching ? "搜索中…" : "\(filteredSongs.count) 首").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
                }
                if filteredSongs.isEmpty {
                    emptyState(icon: "music.note.list", title: searchError == nil ? "正在搜索在线音源" : "暂时没有搜索结果", detail: searchError ?? "请稍候")
                } else {
                    VStack(spacing: 17) {
                        ForEach(filteredSongs) { song in songRow(song) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
                .padding(.horizontal, 22).padding(.top, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: searchFieldFocused) { _, focused in
                guard focused else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("searchResults", anchor: .top)
                    }
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
        VStack(alignment: .leading, spacing: 24) {
            pageHeader("音乐库", subtitle: "你的音乐，保存在本地")
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    Button { libraryFilter = filter } label: {
                        Text(filter.rawValue).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(libraryFilter == filter ? .white : MusicXTheme.muted)
                            .padding(.horizontal, 15).padding(.vertical, 10)
                            .background(libraryFilter == filter ? MusicXTheme.blue.opacity(0.22) : MusicXTheme.surface, in: Capsule())
                    }
                }
            }
            if librarySongs.isEmpty {
                Spacer()
                emptyState(
                    icon: libraryFilter == .downloads ? "arrow.down.circle" : "music.note.list",
                    title: libraryFilter == .downloads ? "暂无下载歌曲" : "这里还没有内容",
                    detail: libraryFilter == .favorites ? "喜欢的歌曲会出现在这里" : libraryFilter == .recent ? "播放过的歌曲会记录在这里" : "从正在播放页面下载的歌曲会保存在这里"
                )
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 17) {
                        ForEach(librarySongs) { song in songRow(song) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.top, 28)
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
                    Capsule().fill(MusicXTheme.blue).frame(width: 4, height: 21)
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
                Capsule().fill(MusicXTheme.blue).frame(width: 4, height: 21)
                Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Spacer()
            }
            .contentShape(Rectangle())
        }
    }

    private func homeSongRow(_ song: AppSong, artworkName: String? = nil) -> some View {
        Button { select(song) } label: {
            HStack(spacing: 9) {
                Group {
                    if let artworkName {
                        HomeArtwork(name: artworkName)
                    } else {
                        songArtwork(song.onlineSong, tint: song.tint, size: 30)
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(song.artist).font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let duration = song.onlineSong?.duration, duration > 0 {
                    Text(playerTime(duration)).font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(MusicXTheme.muted)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.58))
            }.contentShape(Rectangle()).padding(.vertical, 0)
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
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.38)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.82)))
    }

    private func songRow(_ song: AppSong, number: String? = nil) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [song.tint, song.tint.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 54, height: 54)
                .overlay(Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.8)))
            Button { select(song) } label: {
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
            Button { select(song) } label: {
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
        let assetName = title == "热歌榜" ? "chart_hot" : title == "飙升榜" ? "chart_rising" : "chart_new"
        return Button { discoveryRoute = .chart(title) } label: {
            ZStack(alignment: .bottomLeading) {
                HomeArtwork(name: assetName).frame(width: width, height: 70).clipped()
                LinearGradient(colors: [color.opacity(0.10), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    Text(rank).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.7)
                }.padding(.leading, 8).padding(.bottom, 6)
                HStack(spacing: 1) {
                    ForEach(0..<7, id: \.self) { index in
                        Capsule().fill(color.opacity(0.95)).frame(width: 2, height: CGFloat([4, 7, 10, 6, 12, 8, 5][index]))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.trailing, 28).padding(.bottom, 7)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 19, height: 19).background(.black.opacity(0.32), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(5)
            }
            .frame(width: width, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.34), lineWidth: 0.9))
        }.buttonStyle(.plain)
    }

    private var miniPlayer: some View {
        HStack(spacing: 12) {
            Button { if currentSong != nil { isPlayerPresented = true } } label: {
                HStack(spacing: 12) {
                    Group {
                        if currentSong == nil {
                            HomeArtwork(name: "player_cover").frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            songArtwork(currentSong?.onlineSong, tint: currentSong?.tint ?? MusicXTheme.blue, size: 28)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentSong?.title ?? "尚未播放").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(currentSong?.artist ?? "选择一首歌曲开始聆听").font(.system(size: 11)).foregroundStyle(.white.opacity(0.70)).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { stepSong(by: -1) } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.88)).frame(width: 26, height: 34)
            }.buttonStyle(.plain).disabled(playbackQueue.isEmpty)
            Button { if currentSong != nil { playerStore.togglePlayback() } } label: {
                Group {
                    if isResolvingSong || playerStore.isBuffering { ProgressView().tint(.white) }
                    else { Image(systemName: playerStore.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white) }
                }.frame(width: 32, height: 32).background(.white.opacity(0.18), in: Circle()).overlay(Circle().stroke(.white.opacity(0.34), lineWidth: 1))
            }.buttonStyle(.plain).disabled(currentSong == nil)
            Button { stepSong(by: 1) } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.88)).frame(width: 26, height: 34)
            }.buttonStyle(.plain).disabled(playbackQueue.isEmpty)
            Button { playerDisplayMode = .queue; isPlayerPresented = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 19, weight: .semibold)).foregroundStyle(.white.opacity(0.88)).frame(width: 26, height: 34)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).frame(height: 38)
        .background {
            Capsule().fill(.ultraThinMaterial.opacity(0.68))
                .overlay(Capsule().fill(LinearGradient(colors: [Color(red: 0.06, green: 0.16, blue: 0.34).opacity(0.46), Color(red: 0.20, green: 0.10, blue: 0.34).opacity(0.34)], startPoint: .leading, endPoint: .trailing)))
        }
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.7))
        .shadow(color: MusicXTheme.blue.opacity(0.10), radius: 14, y: 5)
        .padding(.horizontal, 14)
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
                        Text("正在播放").font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Menu {
                            Button {
                                if let currentSong { toggleFavorite(currentSong) }
                            } label: {
                                Label(favorites.contains(currentSong?.id ?? -1) ? "取消喜欢" : "添加到喜欢",
                                      systemImage: favorites.contains(currentSong?.id ?? -1) ? "heart.slash" : "heart")
                            }
                            ShareLink(item: "\(currentSong?.title ?? "歌曲") - \(currentSong?.artist ?? "未知歌手")") {
                                Label("分享歌曲", systemImage: "square.and.arrow.up")
                            }
                            ShareLink(item: MusicSourceDiagnostics.shared.fileURL) {
                                Label("分享音源诊断", systemImage: "waveform.path")
                            }
                            Button {
                                downloadCurrentSong()
                            } label: {
                                Label(isDownloading ? "正在下载…" : (isCurrentSongDownloaded ? "已下载" : "下载歌曲"),
                                      systemImage: "arrow.down.to.line")
                            }
                            .disabled(currentSong?.onlineSong == nil || isDownloading || isCurrentSongDownloaded)
                            Menu {
                                Button("查看专辑") {
                                    if let song = currentSong?.onlineSong {
                                        isPlayerPresented = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { discoveryRoute = .album(title: song.album?.isEmpty == false ? song.album! : song.title, artist: song.artist) }
                                    }
                                }
                                Button("查看歌手") {
                                    if let artist = currentSong?.artist, !artist.isEmpty {
                                        isPlayerPresented = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { openSearch(query: artist) }
                                    }
                                }
                            } label: {
                                Label("查看专辑 / 歌手", systemImage: "person.crop.rectangle")
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 19, weight: .semibold))
                        }
                        .disabled(currentSong == nil)
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
                    .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard abs(horizontal) > 55, abs(horizontal) > abs(vertical) * 1.2 else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            playerDisplayMode = horizontal < 0 ? playerDisplayMode.next : playerDisplayMode.previous
                        }
                    })

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
                        Button { isShuffleEnabled.toggle() } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(isShuffleEnabled ? MusicXTheme.blue : .white.opacity(0.65))
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            ForEach(PlayerDisplayMode.allCases, id: \.self) { mode in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        playerDisplayMode = mode
                                    }
                                } label: {
                                    Capsule()
                                        .fill(playerDisplayMode == mode ? MusicXTheme.blue : .white.opacity(0.30))
                                        .frame(width: playerDisplayMode == mode ? 16 : 5, height: 5)
                                        .frame(width: 20, height: 30)
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
                .simultaneousGesture(DragGesture(minimumDistance: 45).onEnded { value in
                    if value.translation.height > 95 && abs(value.translation.width) < 85 {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            isPlayerPresented = false
                        }
                    }
                })
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            .background {
                playerArtwork
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .blur(radius: 65)
                    .overlay(MusicXTheme.background.opacity(0.78))
            }
            .clipped()
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
                                Button { select(song) } label: {
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
        guard !queue.isEmpty else { return }
        let index = queue.firstIndex(where: { $0.id == currentSong?.id }) ?? 0
        if isShuffleEnabled && queue.count > 1 {
            let candidates = queue.filter { $0.id != currentSong?.id }
            if let next = candidates.randomElement() { select(next) }
            return
        }
        select(queue[(index + offset + queue.count) % queue.count])
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
            let candidates = queue.filter { $0.id != currentSong.id }
            if let next = candidates.randomElement() { select(next) }
            return
        }
        let nextIndex = index + 1
        if queue.indices.contains(nextIndex) { select(queue[nextIndex]) }
        else if repeatMode == 1, let first = queue.first { select(first) }
    }

    private func removeFromQueue(_ song: AppSong) {
        if !hasCustomPlaybackQueue {
            playbackQueueSongs = playbackQueue
            hasCustomPlaybackQueue = true
        }
        playbackQueueSongs.removeAll { $0.id == song.id }
    }

    private func clearQueue() {
        hasCustomPlaybackQueue = true
        playbackQueueSongs = currentSong.map { [$0] } ?? []
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.76, blendDuration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 22, weight: .semibold))
                            .frame(height: 23)
                            .symbolEffect(.bounce, value: selectedTab == tab)
                            .shadow(color: selectedTab == tab ? Color.cyan.opacity(0.48) : .clear,
                                    radius: selectedTab == tab ? 6 : 0, y: 0)
                        Text(tab.rawValue).font(.system(size: 13, weight: .semibold)).frame(height: 15)
                            .shadow(color: selectedTab == tab ? Color.cyan.opacity(0.34) : .clear,
                                    radius: selectedTab == tab ? 6 : 0, y: 0)
                    }
                    .foregroundStyle(selectedTab == tab ? Color(red: 0.34, green: 0.78, blue: 1) : .white.opacity(0.72))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .scaleEffect(selectedTab == tab ? 1.035 : 1)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                                        .fill(LinearGradient(colors: [Color.cyan.opacity(0.11), Color.blue.opacity(0.055), .white.opacity(0.018)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                                        .stroke(LinearGradient(colors: [.white.opacity(0.20), Color.cyan.opacity(0.12), .white.opacity(0.03)],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                                }
                                .shadow(color: Color.cyan.opacity(0.08), radius: 9, y: 2)
                                .matchedGeometryEffect(id: "active-tab-glass", in: tabSelectionNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 9)
        .background {
            Capsule().fill(.ultraThinMaterial.opacity(0.70))
                .overlay(Capsule().fill(LinearGradient(colors: [Color(red: 0.06, green: 0.16, blue: 0.34).opacity(0.46), Color(red: 0.20, green: 0.10, blue: 0.34).opacity(0.34)], startPoint: .leading, endPoint: .trailing)))
        }
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.7))
        .shadow(color: MusicXTheme.blue.opacity(0.12), radius: 15, y: 5)
        .padding(.horizontal, 10)
    }

    private func playDiscoverySong(_ song: MusicSong) {
        // Keep the discovery route mounted while playback starts.
        let appSong = AppSong(id: stableSongID(song), title: song.title, artist: song.artist,
                              album: song.album ?? "", tint: MusicXTheme.blue, onlineSong: song)
        select(appSong)
    }

    private func select(_ song: AppSong) {
        if let localURL = song.localFileURL {
            playbackTask?.cancel()
            playbackRequestID = UUID()
            playerStore.play(url: localURL, title: song.title, artist: song.artist,
                             album: song.album, artworkURL: song.onlineSong?.artworkURL)
            currentSong = song
        } else if currentSong?.id == song.id {
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
                                     album: onlineSong.album, artworkURL: onlineSong.artworkURL)
                } catch is CancellationError {
                    return
                } catch {
                    guard playbackRequestID == requestID else { return }
                    isResolvingSong = false
                    searchError = error.localizedDescription
                }
            }
        } else {
            currentSong = song
        }
        var ids = recentIDs.split(separator: ",").compactMap { Int($0) }
        ids.removeAll { $0 == song.id }
        ids.insert(song.id, at: 0)
        recentIDs = ids.prefix(30).map { String($0) }.joined(separator: ",")
    }

    @MainActor
    private func searchOnline(_ keyword: String) async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        let service = GDStudioMusicSearchService()
        async let netease = try? service.search(keyword: keyword, source: .netease, count: 50)
        async let qq = try? service.search(keyword: keyword, source: .qq, count: 50)
        async let kuwo = try? service.search(keyword: keyword, source: .kuwo, count: 50)
        let sourceResults = [await netease ?? [], await qq ?? [], await kuwo ?? []]
        // Interleave only providers with an implemented playback resolver.
        var merged: [MusicSong] = []
        let maxCount = sourceResults.map(\.count).max() ?? 0
        for index in 0..<maxCount {
            for source in sourceResults where source.indices.contains(index) {
                merged.append(source[index])
            }
        }
        guard !Task.isCancelled,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }

        // Collapse cross-provider duplicates, preserving the first playable source.
        var seen = Set<String>()
        let uniqueResults = merged.filter { item in
            let key = "\(normalizedSearchKey(item.title))|\(normalizedSearchKey(item.artist))"
            return !key.isEmpty && seen.insert(key).inserted
        }
        let results = Array(uniqueResults.prefix(50))
        onlineResults = results.map { item in
            AppSong(id: stableSongID(item), title: item.title, artist: item.artist,
                     album: item.album ?? "",
                     tint: item.source == .netease ? MusicXTheme.blue : item.source == .qq ? .purple : .teal,
                     onlineSong: item)
        }
        if results.isEmpty { searchError = "当前音源暂未返回结果" }
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

    private func normalizedSearchKey(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private func stableSongID(_ song: MusicSong) -> Int {
        let hash = song.id.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        return Int(hash & 0x7FFFFFFFFFFFFFFF)
    }

    private func toggleFavorite(_ song: AppSong) {
        var ids = favorites
        if ids.contains(song.id) { ids.remove(song.id) }
        else { ids.insert(song.id) }
        favoriteIDs = ids.sorted().map { String($0) }.joined(separator: ",")
    }

    private func downloadCurrentSong() {
        guard let appSong = currentSong, let song = appSong.onlineSong else { return }
        if downloadedSongs.contains(where: { $0.id == appSong.id }) {
            downloadMessage = "这首歌曲已经下载，可在「我的 → 下载」中收听。"
            isDownloadAlertPresented = true
            return
        }
        isDownloading = true
        Task {
            do {
                let sourceURL = try await LXMusicURLResolver().resolve(song: song, quality: selectedMusicQuality)
                let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
                let ext = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension
                let fileName = "\(appSong.id)-\(UUID().uuidString).\(ext)"
                let destination = downloadsDirectory.appendingPathComponent(fileName)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                var tracks = downloadedTracks
                tracks.removeAll { $0.id == appSong.id }
                tracks.append(DownloadedTrack(id: appSong.id, song: song, fileName: fileName))
                let data = try JSONEncoder().encode(tracks)
                downloadedTracksJSON = String(decoding: data, as: UTF8.self)
                downloadMessage = "下载完成，已保存到「我的 → 下载」。"
            } catch {
                downloadMessage = "下载失败：\(error.localizedDescription)"
            }
            isDownloading = false
            isDownloadAlertPresented = true
        }
    }
}

private struct SongArtworkView: View {
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
            guard song.artworkURL == nil else { resolvedURL = song.artworkURL; return }
            guard song.pictureID?.isEmpty == false else { return }
            resolvedURL = try? await GDStudioMetadataService().artworkURL(for: song)
        }
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.38)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "music.note").font(.system(size: min(22, size * 0.42))).foregroundStyle(.white.opacity(0.82)))
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
