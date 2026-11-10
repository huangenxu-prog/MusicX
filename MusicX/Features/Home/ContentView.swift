import SwiftUI

private enum MainTab: String, CaseIterable {
    case home = "主页"
    case search = "搜索"
    case library = "音乐库"

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .library: "square.stack"
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
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var libraryFilter: LibraryFilter = .favorites
    @State private var currentSong: AppSong?
    @StateObject private var playerStore = PlayerStore()
    @State private var onlineResults: [AppSong] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var isPlayerPresented = false
    @State private var playbackRequestID = UUID()
    @State private var playbackTask: Task<Void, Never>?
    @State private var playbackQueueSongs: [AppSong] = []
    @State private var isResolvingSong = false
    @AppStorage("musicx.favoriteIDs") private var favoriteIDs = "1,3"
    @AppStorage("musicx.recentIDs") private var recentIDs = ""
    @AppStorage("musicx.downloadedTracks") private var downloadedTracksJSON = "[]"
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
                VStack(spacing: 0) {
                    miniPlayer
                    tabBar
                }
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $isPlayerPresented) { nowPlayingPage }
        .alert("MusicX 设置", isPresented: $isSettingsAlertPresented) {
            Button("完成", role: .cancel) { }
        } message: {
            Text("音质、音源与播放偏好设置将在后续版本开放。")
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
        .fullScreenCover(item: $discoveryRoute) { route in
            MusicDiscoveryPage(route: route, onClose: { discoveryRoute = nil },
                onPlay: { playDiscoverySong($0) },
                currentSong: currentSong?.onlineSong,
                isPlaying: playerStore.isPlaying,
                onTogglePlayback: { playerStore.togglePlayback() },
                onOpenPlayer: { isPlayerPresented = true },
                onQueueChanged: { playbackQueueSongs = $0.map { AppSong(id: stableSongID($0), title: $0.title, artist: $0.artist, album: $0.album ?? "", tint: MusicXTheme.blue, onlineSong: $0) } },
                currentTime: playerStore.currentTime,
                duration: playerStore.duration,
                onOpenPlaylist: { discoveryRoute = .playlist($0) })
        }
        .task { await loadHomeSongs() }
    }

    private var homePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                heroHeader
                recommendationSection
                newMusicSection
                albumSection
                chartSection
            }
            .padding(.bottom, 18)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.20, blue: 0.39), Color(red: 0.06, green: 0.10, blue: 0.19), MusicXTheme.background],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Spacer()
                    Button { isSettingsAlertPresented = true } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("设置")
                }
                Spacer()
                Text("发现音乐")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("好音乐，总在这里")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.horizontal, 24)
            .padding(.top, 54)
            .padding(.bottom, 22)
        }
        .frame(height: 250)
        .clipped()
    }

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("为你推荐").font(.system(size: 25, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text("每日精选").font(.system(size: 13, weight: .medium)).foregroundStyle(MusicXTheme.muted)
            }
            HStack(spacing: 14) {
                recommendationTile(
                    title: "每日推荐", subtitle: "发现今天的好音乐",
                    icon: "sparkles",
                    colors: [Color(red: 0.20, green: 0.43, blue: 0.70), Color(red: 0.10, green: 0.19, blue: 0.36)],
                    route: .daily
                )
                recommendationTile(
                    title: "精选歌单", subtitle: "按心情聆听",
                    icon: "square.stack.fill",
                    colors: [Color(red: 0.39, green: 0.23, blue: 0.49), Color(red: 0.20, green: 0.13, blue: 0.31)],
                    route: .playlists
                )
            }
        }
        .padding(.horizontal, 20)
    }

    private func recommendationTile(title: String, subtitle: String, icon: String, colors: [Color], route: MusicDiscoveryRoute) -> some View {
        Button { discoveryRoute = route } label: {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                    Spacer(minLength: 12)
                    Text(title).font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
                        .padding(.top, 7)
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 188)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 10) {
            homeSectionTitle("新歌速递", action: { discoveryRoute = .daily })
            if isLoadingHomeSongs && songs.isEmpty {
                ProgressView().tint(MusicXTheme.blue).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if let homeLoadError, songs.isEmpty {
                Text(homeLoadError).font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(songs.prefix(3)) { song in
                        homeSongRow(song)
                        if song.id != songs.prefix(3).last?.id {
                            Rectangle().fill(.white.opacity(0.10)).frame(height: 0.5).padding(.leading, 62)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            homeSectionTitle("热门专辑", action: { discoveryRoute = .playlists })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(songs.prefix(8))) { song in
                        if let onlineSong = song.onlineSong { albumTile(song: onlineSong) }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 20)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            homeSectionTitle("排行榜", action: { discoveryRoute = .charts })
            HStack(spacing: 10) {
                chartTile("热歌榜", subtitle: "最受欢迎的歌曲", icon: "chart.bar.fill", color: MusicXTheme.blue)
                chartTile("新歌榜", subtitle: "最新发布的歌曲", icon: "flame.fill", color: .purple)
                chartTile("飙升榜", subtitle: "热度快速上升", icon: "chart.line.uptrend.xyaxis", color: .teal)
            }
        }
        .padding(.horizontal, 20)
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

    private func homeSectionTitle(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Capsule().fill(MusicXTheme.blue).frame(width: 5, height: 27)
                Text(title).font(.system(size: 23, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text("查看全部").font(.system(size: 13, weight: .medium)).foregroundStyle(MusicXTheme.muted)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(MusicXTheme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func homeSongRow(_ song: AppSong) -> some View {
        HStack(spacing: 13) {
            songArtwork(song.onlineSong, tint: song.tint, size: 58)
            Button { select(song) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(song.artist).font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button { select(song) } label: {
                Image(systemName: currentSong?.id == song.id && playerStore.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            Button { discoveryRoute = .daily } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).foregroundStyle(.white.opacity(0.82))
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func songArtwork(_ song: MusicSong?, tint: Color, size: CGFloat) -> some View {
        if let url = song?.artworkURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    artworkFallback(tint: tint)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        if let source = song.onlineSong?.source {
                            Text("·").foregroundStyle(MusicXTheme.muted)
                            Text(source.shortLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(song.tint)
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
        Button { discoveryRoute = .album(song) } label: {
            VStack(alignment: .leading, spacing: 7) {
                songArtwork(song, tint: MusicXTheme.blue, size: 112)
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.08), lineWidth: 1))
                Text(song.album?.isEmpty == false ? song.album! : song.title)
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(song.artist).font(.system(size: 12)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
            }
            .frame(width: 112, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func chartTile(_ title: String, subtitle: String, icon: String, color: Color) -> some View {
        Button { discoveryRoute = .charts } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white).frame(width: 30, height: 30)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(LinearGradient(colors: [color.opacity(0.34), color.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(color.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var miniPlayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { if currentSong != nil { isPlayerPresented = true } } label: {
                    HStack(spacing: 11) {
                        songArtwork(currentSong?.onlineSong, tint: currentSong?.tint ?? MusicXTheme.blue, size: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentSong?.title ?? "尚未播放").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(currentSong?.artist ?? "选择一首歌曲开始聆听").font(.system(size: 12)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { if currentSong != nil { playerStore.togglePlayback() } } label: {
                    Image(systemName: playerStore.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 42, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(currentSong == nil)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
        }
        .background(Color(red: 0.075, green: 0.085, blue: 0.13).opacity(0.98))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5) }
    }

    private var progressFraction: CGFloat {
        guard playerStore.duration > 0 else { return 0 }
        return CGFloat(min(max(playerStore.currentTime / playerStore.duration, 0), 1))
    }

    @State private var isLyricsPresented = false
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
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { discoveryRoute = .album(song) }
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
                                            discoveryRoute = .album(song)
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
                        Slider(value: Binding(
                            get: { playerStore.duration > 0 ? min(playerStore.currentTime, playerStore.duration) : 0 },
                            set: { playerStore.seek(to: $0) }
                        ), in: 0...max(playerStore.duration, 1))
                        .tint(MusicXTheme.blue)
                        .disabled(playerStore.duration <= 0)
                        HStack {
                            Text(playerTime(playerStore.currentTime))
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
                            Image(systemName: playerStore.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .bold)).foregroundStyle(MusicXTheme.background)
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

    private var lyricsSheet: some View {
        NavigationStack {
            ZStack {
                MusicXTheme.background.ignoresSafeArea()
                if lyricLines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "quote.bubble").font(.system(size: 34, weight: .light)).foregroundStyle(MusicXTheme.blue)
                        Text(lyricsUnavailable ? "暂时没有找到歌词" : "正在获取歌词")
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        Text(lyricsUnavailable ? "当前音源没有提供可用的歌词数据。" : "请稍候，正在从音源读取歌词。")
                            .font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
                    }.padding(30)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 22) {
                                ForEach(Array(lyricLines.enumerated()), id: \.element.id) { index, line in
                                    Text(line.text)
                                        .font(.system(size: index == activeLyricIndex ? 21 : 16, weight: index == activeLyricIndex ? .bold : .medium))
                                        .foregroundStyle(index == activeLyricIndex ? .white : MusicXTheme.muted)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .id(line.id)
                                }
                            }.padding(.horizontal, 24).padding(.vertical, 42)
                        }
                        .onChange(of: playerStore.currentTime) { _, _ in
                            if lyricLines.indices.contains(activeLyricIndex) {
                                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(lyricLines[activeLyricIndex].id, anchor: .center) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(currentSong?.title ?? "歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { isLyricsPresented = false } }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
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
                                .padding(.horizontal, 10).padding(.vertical, 9)
                                .background(active ? MusicXTheme.blue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
        var items = playbackQueueSongs.isEmpty ? songs + onlineResults : playbackQueueSongs
        if let currentSong, !items.contains(where: { $0.id == currentSong.id }) {
            items.insert(currentSong, at: 0)
        }
        var seen = Set<Int>()
        return items.filter { seen.insert($0.id).inserted }
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
        select(queue[(index + offset + queue.count) % queue.count])
    }

    private var tabBar: some View {
        HStack {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.system(size: 19, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? MusicXTheme.blue : MusicXTheme.muted)
                    .frame(maxWidth: .infinity).padding(.top, 9).padding(.bottom, 5)
                }
            }
        }.padding(.horizontal, 12).background(MusicXTheme.background.opacity(0.98))
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
            // Keep the current AVPlayer item and Now Playing session alive while
            // the next stream URL resolves. Stopping here releases lock-screen ownership
            // and can leave background playback silent during network resolution.
            isResolvingSong = true
            playbackTask = Task {
                defer {
                    if playbackRequestID == requestID { isResolvingSong = false }
                }
                do {
                    let url = try await LXMusicURLResolver().resolve(song: onlineSong, quality: .high)
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
        async let netease = try? service.search(keyword: keyword, source: .netease, count: 20)
        async let qq = try? service.search(keyword: keyword, source: .qq, count: 20)
        async let kuwo = try? service.search(keyword: keyword, source: .kuwo, count: 20)
        let sourceResults = [await netease ?? [], await qq ?? [], await kuwo ?? []]
        // Interleave providers so one source cannot occupy the entire first page.
        var merged: [MusicSong] = []
        let maxCount = sourceResults.map(\.count).max() ?? 0
        for index in 0..<maxCount {
            for source in sourceResults where source.indices.contains(index) {
                merged.append(source[index])
            }
        }
        guard !Task.isCancelled,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }

        // Collapse cross-provider duplicates by normalized title + artist.
        var seen = Set<String>()
        let uniqueResults = merged.filter { item in
            let key = "\(normalizedSearchKey(item.title))|\(normalizedSearchKey(item.artist))"
            return !key.isEmpty && seen.insert(key).inserted
        }
        let results = Array(uniqueResults.prefix(20))
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
        let service = GDStudioMusicSearchService()
        var collected: [MusicSong] = []
        var failures: [String] = []
        // GDStudio search accepts song, artist or album names, not genre labels.
        for keyword in ["陈奕迅", "周杰伦", "薛之谦"] {
            do {
                collected.append(contentsOf: try await service.search(keyword: keyword, source: .netease, count: 5))
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        var seen = Set<String>()
        songs = collected.filter { seen.insert($0.id).inserted }.map { item in
            AppSong(id: stableSongID(item), title: item.title, artist: item.artist,
                    album: item.album ?? "", tint: MusicXTheme.blue, onlineSong: item)
        }
        if songs.isEmpty {
            homeLoadError = failures.first ?? "在线音源暂时没有返回歌曲，请稍后重试"
        }
    }

    private func openSearch(query: String) {
        searchText = query
        onlineResults = []
        selectedTab = .search
        searchFieldFocused = false
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
                let sourceURL = try await LXMusicURLResolver().resolve(song: song, quality: .high)
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
