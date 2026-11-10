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

    init(id: Int, title: String, artist: String, album: String, tint: Color, onlineSong: MusicSong? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.tint = tint
        self.onlineSong = onlineSong
    }
}

private enum LibraryFilter: String, CaseIterable {
    case favorites = "收藏"
    case recent = "最近播放"
    case downloads = "下载"
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
    @AppStorage("musicx.favoriteIDs") private var favoriteIDs = "1,3"
    @AppStorage("musicx.recentIDs") private var recentIDs = ""

    private var favorites: Set<Int> {
        Set(favoriteIDs.split(separator: ",").compactMap { Int($0) })
    }

    private var recentSongs: [AppSong] {
        let ids = recentIDs.split(separator: ",").compactMap { Int($0) }
        return ids.compactMap { id in songs.first { $0.id == id } }
    }

    @State private var songs: [AppSong] = []
    @State private var isLoadingHomeSongs = false
    @State private var homeLoadError: String?
    @State private var discoveryRoute: MusicDiscoveryRoute?

    private var filteredSongs: [AppSong] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return songs }
        return onlineResults
    }

    private var librarySongs: [AppSong] {
        switch libraryFilter {
        case .favorites: songs.filter { favorites.contains($0.id) }
        case .recent: recentSongs
        case .downloads: []
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
        .fullScreenCover(item: $discoveryRoute) { route in
            MusicDiscoveryPage(route: route, onClose: { discoveryRoute = nil },
                onPlay: { playDiscoverySong($0) },
                onOpenPlaylist: { discoveryRoute = .playlist($0) })
        }
        .task { await loadHomeSongs() }
    }

    private var homePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                heroHeader
                recommendationSection
                newMusicSection
                albumSection
                chartSection
            }
            .padding(.bottom, 28)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.12, green: 0.25, blue: 0.43), Color(red: 0.08, green: 0.12, blue: 0.23), MusicXTheme.background], startPoint: .topTrailing, endPoint: .bottomLeading)
            RadialGradient(colors: [MusicXTheme.blue.opacity(0.35), .clear], center: .topTrailing, startRadius: 5, endRadius: 260)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Image(systemName: "waveform").font(.system(size: 21, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.09), in: Circle())
                }
                Spacer()
                Text("发现音乐").font(.system(size: 38, weight: .bold, design: .rounded))
                Text("好音乐，总在这里").font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 24).padding(.top, 64).padding(.bottom, 30)
        }
        .frame(height: 285)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, MusicXTheme.background.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .frame(height: 48).allowsHitTesting(false)
        }
    }

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("为你推荐", detail: "每日精选")
            HStack(spacing: 14) {
                recommendationCard(title: "每日推荐", subtitle: "发现今天的好音乐", colors: [Color(red: 0.18, green: 0.38, blue: 0.61), Color(red: 0.13, green: 0.18, blue: 0.35)], icon: "sparkles", route: .daily)
                recommendationCard(title: "精选歌单", subtitle: "按心情聆听", colors: [Color(red: 0.39, green: 0.25, blue: 0.48), Color(red: 0.18, green: 0.15, blue: 0.31)], icon: "square.stack.fill", route: .playlists)
            }
        }.padding(.horizontal, 20)
    }

    private func recommendationCard(title: String, subtitle: String, colors: [Color], icon: String, route: MusicDiscoveryRoute) -> some View {
        Button { discoveryRoute = route } label: {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 12)
            Text(title).font(.system(size: 19, weight: .bold))
            Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var newMusicSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("新歌速递", detail: "在线音源")
            if isLoadingHomeSongs && songs.isEmpty {
                ProgressView().tint(MusicXTheme.blue).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if let homeLoadError, songs.isEmpty {
                Text(homeLoadError).font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).padding(.vertical, 12)
            } else {
                ForEach(songs.prefix(3)) { song in songRow(song) }
            }
        }.padding(.horizontal, 20)
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("热门专辑", detail: "精选推荐")
            HStack(spacing: 14) {
                ForEach(Array(songs.prefix(3))) { song in
                    if let onlineSong = song.onlineSong { albumTile(song: onlineSong) }
                }
            }
        }.padding(.horizontal, 20)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Button { discoveryRoute = .charts } label: {
                sectionTitle("排行榜", detail: "查看全部")
            }.buttonStyle(.plain)
            HStack(spacing: 12) {
                chartTile("热歌榜", subtitle: "热门歌曲", icon: "flame.fill", color: .orange)
                chartTile("新歌榜", subtitle: "最新发行", icon: "sparkles", color: MusicXTheme.blue)
                chartTile("飙升榜", subtitle: "正在上升", icon: "chart.line.uptrend.xyaxis", color: .mint)
            }
        }.padding(.horizontal, 20)
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
                    detail: libraryFilter == .favorites ? "喜欢的歌曲会出现在这里" : libraryFilter == .recent ? "播放过的歌曲会记录在这里" : "下载功能将在音源接入后开放"
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

    private func songRow(_ song: AppSong, number: String? = nil) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [song.tint, song.tint.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 54, height: 54)
                .overlay(Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.8)))
            Button { select(song) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(song.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text(song.artist).font(.system(size: 12)).foregroundStyle(MusicXTheme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
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
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [MusicXTheme.blue, MusicXTheme.blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(Image(systemName: "waveform").font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.75)))
                Text(song.album?.isEmpty == false ? song.album! : song.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(song.artist).font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
    }

    private func chartTile(_ title: String, subtitle: String, icon: String, color: Color) -> some View {
        Button { discoveryRoute = .charts } label: {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.system(size: 21)).foregroundStyle(color)
            Text(title).font(.system(size: 15, weight: .bold))
            Text(subtitle).font(.system(size: 10)).foregroundStyle(MusicXTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12).background(MusicXTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var miniPlayer: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [currentSong?.tint ?? MusicXTheme.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "music.note").foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(currentSong?.title ?? "尚未播放").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(currentSong?.artist ?? "选择一首歌曲开始聆听").font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
            }
            Spacer()
            Button { if currentSong != nil { playerStore.togglePlayback() } } label: {
                Image(systemName: playerStore.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
            }
            .disabled(currentSong == nil)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(MusicXTheme.surface.opacity(0.96))
        .contentShape(Rectangle())
        .onTapGesture { if currentSong != nil { isPlayerPresented = true } }
    }

    @State private var isQueuePresented = false
    @State private var isShuffleEnabled = false
    @State private var repeatMode = 0

    private var nowPlayingPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Button { isPlayerPresented = false } label: {
                        Image(systemName: "chevron.down").font(.system(size: 19, weight: .semibold))
                    }
                    Spacer()
                    Text("正在播放").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: "ellipsis").font(.system(size: 19))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .padding(.top, 12)

                Spacer(minLength: 22)

                playerArtwork
                    .frame(width: min(geometry.size.width - 64, geometry.size.height * 0.48),
                           height: min(geometry.size.width - 64, geometry.size.height * 0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .shadow(color: (currentSong?.tint ?? MusicXTheme.blue).opacity(0.16), radius: 28, y: 12)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(currentSong?.title ?? "尚未选择歌曲")
                                .font(.system(size: 27, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(currentSong?.artist ?? "选择一首歌曲开始聆听")
                                .font(.system(size: 16))
                                .foregroundStyle(MusicXTheme.muted)
                                .lineLimit(1)
                            if let album = currentSong?.album, !album.isEmpty {
                                Text(album).font(.system(size: 12)).foregroundStyle(.white.opacity(0.42)).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Button { if let currentSong { toggleFavorite(currentSong) } } label: {
                            Image(systemName: currentSong.map { favorites.contains($0.id) } == true ? "heart.fill" : "heart")
                                .font(.system(size: 23, weight: .medium))
                                .foregroundStyle(currentSong.map { favorites.contains($0.id) } == true ? MusicXTheme.blue : .white.opacity(0.82))
                        }
                        .disabled(currentSong == nil)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)

                VStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { playerStore.duration > 0 ? min(playerStore.currentTime, playerStore.duration) : 0 },
                        set: { playerStore.seek(to: $0) }
                    ), in: 0...max(playerStore.duration, 1))
                    .tint(MusicXTheme.blue)
                    .disabled(playerStore.duration <= 0)
                    HStack {
                        Text(playerTime(playerStore.currentTime))
                        Spacer()
                        Text("-" + playerTime(max(0, playerStore.duration - playerStore.currentTime)))
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(MusicXTheme.muted)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)

                HStack(spacing: 0) {
                    Button { isShuffleEnabled.toggle() } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(isShuffleEnabled ? MusicXTheme.blue : .white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                    }
                    Button { stepSong(by: -1) } label: {
                        Image(systemName: "backward.end.fill").font(.system(size: 27))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    Button { if currentSong != nil { playerStore.togglePlayback() } } label: {
                        Image(systemName: playerStore.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(MusicXTheme.background)
                            .frame(width: 82, height: 82)
                            .background(.white, in: Circle())
                    }
                    .frame(maxWidth: .infinity)
                    Button { stepSong(by: 1) } label: {
                        Image(systemName: "forward.end.fill").font(.system(size: 27))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    Button { repeatMode = (repeatMode + 1) % 3 } label: {
                        Image(systemName: repeatMode == 2 ? "repeat.1" : "repeat")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(repeatMode == 0 ? .white.opacity(0.55) : MusicXTheme.blue)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 32)

                HStack {
                    Button {} label: {
                        Label("歌词", systemImage: "quote.bubble")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    Spacer()
                    Button { isQueuePresented = true } label: {
                        Label("播放队列", systemImage: "list.bullet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 24)
                Spacer(minLength: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(colors: [
                    (currentSong?.tint ?? MusicXTheme.blue).opacity(0.34),
                    Color(red: 0.035, green: 0.065, blue: 0.11),
                    MusicXTheme.background
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isQueuePresented) { playbackQueueSheet }
    }

    @ViewBuilder
    private var playerArtwork: some View {
        if let url = currentSong?.onlineSong?.artworkURL {
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

    private var playbackQueueSheet: some View {
        NavigationStack {
            List {
                ForEach(songs) { song in
                    Button {
                        select(song)
                        isQueuePresented = false
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title).foregroundStyle(.primary).lineLimit(1)
                                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if song.id == currentSong?.id {
                                Image(systemName: "waveform").foregroundStyle(MusicXTheme.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { isQueuePresented = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func playerTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func stepSong(by offset: Int) {
        guard !songs.isEmpty else { return }
        let index = songs.firstIndex(where: { $0.id == currentSong?.id }) ?? 0
        select(songs[(index + offset + songs.count) % songs.count])
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
        let appSong = AppSong(id: stableSongID(song), title: song.title, artist: song.artist,
                              album: song.album ?? "", tint: MusicXTheme.blue, onlineSong: song)
        select(appSong)
        discoveryRoute = nil
    }

    private func select(_ song: AppSong) {
        if currentSong?.id == song.id {
            playerStore.togglePlayback()
        } else if let onlineSong = song.onlineSong {
            currentSong = song
            Task {
                do {
                    let url = try await LXMusicURLResolver().resolve(song: onlineSong, quality: .high)
                    playerStore.play(url: url, title: onlineSong.title, artist: onlineSong.artist)
                } catch {
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
        async let netease = try? service.search(keyword: keyword, source: .netease, count: 5)
        async let qq = try? service.search(keyword: keyword, source: .qq, count: 5)
        async let kuwo = try? service.search(keyword: keyword, source: .kuwo, count: 5)
        let results = (await netease ?? []) + (await qq ?? []) + (await kuwo ?? [])
        guard !Task.isCancelled,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }
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
