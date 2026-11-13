import SwiftUI

enum MusicDiscoveryRoute: Identifiable {
    case daily, playlists, featuredPlaylists, albums, charts, newReleases
    case chart(String)
    case featuredPick
    case playlist(String)
    case playlistByID(MusicPlaylist)
    case album(title: String, artist: String)
    case musicCategory(title: String, subtitle: String, artwork: String, keyword: String)
    var id: String {
        switch self {
        case .daily: "daily"
        case .playlists: "playlists"
        case .featuredPlaylists: "featured-playlists"
        case .albums: "albums"
        case .charts: "charts"
        case .newReleases: "new-releases"
        case .chart(let name): "chart-\(name)"
        case .featuredPick: "featured-pick"
        case .playlist(let name): "playlist-\(name)"
        case .playlistByID(let playlist): "playlist-\(playlist.id)"
        case .album(let title, let artist): "album-\(title)-\(artist)"
        case .musicCategory(let title, _, _, _): "music-category-\(title)"
        }
    }
}

private struct PlaylistCardItem {
    let title: String
    let subtitle: String
    let artwork: String
}

private enum RecommendationTab: Hashable {
    case daily
    case featured
}

struct MusicDiscoveryPage: View {
    let route: MusicDiscoveryRoute
    let featuredAlbums: [MusicSong]
    let selectedMainTab: String
    let onSelectMainTab: (String) -> Void
    let onClose: (Bool) -> Void
    let onPlay: (MusicSong) -> Void
    let currentSong: MusicSong?
    let isPlaying: Bool
    let onTogglePlayback: () -> Void
    let onOpenPlayer: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onOpenQueue: () -> Void
    let onQueueChanged: ([MusicSong]) -> Void
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onOpenPlaylist: (MusicPlaylist) -> Void
    let onOpenPlaylistKeyword: (String) -> Void
    let onOpenFeaturedPick: () -> Void
    let onOpenAlbum: (String, String) -> Void
    let onSelectChart: (String) -> Void

    @State private var songs: [MusicSong] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedChartOverride: String?
    @State private var chartSongCache: [String: [MusicSong]] = [:]
    @State private var chartLoadToken = UUID()
    @State private var songsLoadToken = UUID()
    @State private var playlistCardResults: [String: MusicPlaylist] = [:]
    @State private var featuredPlaylistResults: [MusicPlaylist] = []
    @State private var isPlaylistUnavailableAlertPresented = false
    @State private var playlistUnavailableMessage = ""
    @State private var selectedRecommendationTab: RecommendationTab = .daily
    @State private var recommendationSongCache: [RecommendationTab: [MusicSong]] = [:]
    private var selectedChart: String {
        if let selectedChartOverride { return selectedChartOverride }
        if case .chart(let name) = route { return name }
        return "热歌榜"
    }
    private var isChartRoute: Bool {
        switch route {
        case .charts, .chart: true
        default: false
        }
    }
    private let catalog = MusicCatalogSearchEngine()

    private func closePage(isSwipeBack: Bool = false) {
        onClose(isSwipeBack)
    }

    private func playlistSubtitle(for name: String) -> String {
        let moodNames: Set<String> = ["开心愉悦", "温柔治愈", "放松舒缓", "安静专注", "释放情绪", "夜晚助眠"]
        let featuredNames: Set<String> = []
        if moodNames.contains(name) { return "心情歌单" }
        return featuredNames.contains(name) ? "精选歌单" : "歌单"
    }

    private var title: String {
        switch route {
        case .daily, .featuredPick:
            selectedRecommendationTab == .daily ? "每日推荐" : "精选歌曲"
        case .playlists: "心情歌单"
        case .featuredPlaylists: "精选歌单"
        case .albums: "热门专辑"
        case .charts, .chart: "排行榜"
        case .newReleases: "新歌速递"
        case .playlist(let name): name
        case .playlistByID: "推荐歌单"
        case .album: "专辑"
        case .musicCategory(let title, _, _, _): title
        }
    }
    private var query: String {
        switch route {
        case .daily: "陈奕迅"
        case .playlists: "华语歌手"
        case .featuredPlaylists, .featuredPick, .albums: ""
        case .charts: "陈奕迅"
        case .chart(let name): name == "新歌榜" ? "新歌" : name == "飙升榜" ? "飙升" : "热歌"
        case .newReleases: "新歌"
        case .playlist(let name):
            switch name {
            case "开心愉悦": "开心"
            case "温柔治愈": "治愈"
            case "放松舒缓": "放松"
            case "安静专注": "专注"
            case "释放情绪": "摇滚"
            case "夜晚助眠": "助眠"
            case "本周编辑精选": "本周精选"
            case "华语流行精选": "华语流行"
            case "经典金曲精选": "经典金曲"
            case "独立音乐精选": "独立音乐"
            case "影视原声精选": "影视原声"
            case "通勤驾驶精选": "通勤"
            default: name
            }
        case .playlistByID(let playlist): playlist.name
        case .album(let title, let artist): "\(title) \(artist)"
        case .musicCategory(_, _, _, let keyword): keyword
        }
    }

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 14/255, blue: 31/255).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                if isRecommendationRoute {
                    VStack(spacing: 0) {
                        topBar
                            .padding(.top, 8)
                        vinylRecord
                            .padding(.top, 12)
                        recommendationTabs
                            .padding(.top, 18)
                        recommendationSectionTitle
                            .padding(.top, 20)
                        trackList
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        topBar
                        switch route {
                        case .daily, .featuredPick:
                            recommendationTabs
                            if selectedRecommendationTab == .daily { dailyHeader } else { featuredRecommendationHeader }
                        case .playlists: playlistIntro
                        case .featuredPlaylists: featuredPlaylistsIntro
                        case .albums: albumsIntro
                        case .charts, .chart: chartIntro
                        case .newReleases: newReleasesHeader
                        case .playlist(let name): musicCategoryAlbumHeader(title: name, subtitle: playlistSubtitle(for: name), artwork: categoryArtworkName(for: name))
                        case .playlistByID(let playlist): recommendationPlaylistBanner(playlist)
                        case .album(let title, let artist): albumBanner(title: title, artist: artist)
                        case .musicCategory(let title, let subtitle, let artwork, _):
                            musicCategoryAlbumHeader(title: title, subtitle: subtitle, artwork: artwork)
                        }
                        if case .playlists = route {
                            playlistGrid
                        } else if case .featuredPlaylists = route {
                            featuredPlaylistGrid
                        } else if case .albums = route {
                            albumGrid
                        } else {
                            if case .charts = route { chartTabs }
                            if case .chart = route { chartTabs }
                            if case .album = route {
                                musicCategoryTrackList
                            } else if case .musicCategory = route {
                                musicCategoryTrackList
                            } else if case .playlist = route {
                                musicCategoryTrackList
                            } else {
                                trackList
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                miniPlayerBar(song: currentSong)
                discoveryTabBar
            }
            .background(Color(red: 10/255, green: 14/255, blue: 31/255))
        }
        .simultaneousGesture(DragGesture(minimumDistance: 22, coordinateSpace: .global).onEnded { value in
            let horizontal = value.translation.width
            let vertical = value.translation.height
            guard value.startLocation.x <= 28, horizontal > 88, horizontal > abs(vertical) * 1.25 else { return }
            closePage(isSwipeBack: true)
        })
        .task(id: route.id) {
            if case .daily = route { selectedRecommendationTab = .daily }
            if case .featuredPick = route { selectedRecommendationTab = .featured }
            await loadSongs()
        }
        .alert("暂未找到匹配歌单", isPresented: $isPlaylistUnavailableAlertPresented) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(playlistUnavailableMessage)
        }
    }

    private var recommendationSectionTitle: some View {
        HStack(spacing: 11) {
            Capsule()
                .fill(Color(red: 0.28, green: 0.55, blue: 0.98))
                .frame(width: 4, height: 22)
            Text("为你推荐")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var vinylRecord: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.20, green: 0.22, blue: 0.55).opacity(0.42), .clear],
                                     center: .center, startRadius: 42, endRadius: 112))
                .frame(width: 190, height: 190)
            Circle().fill(Color(red: 0.055, green: 0.075, blue: 0.16))
                .frame(width: 164, height: 164)
                .overlay(Circle().stroke(Color(red: 0.18, green: 0.25, blue: 0.49).opacity(0.8), lineWidth: 1))
            ForEach([CGFloat(142), 126, 110, 94], id: \.self) { diameter in
                Circle().stroke(Color(red: 0.12, green: 0.18, blue: 0.36).opacity(0.82), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
            }
            Circle().stroke(Color(red: 0.25, green: 0.43, blue: 0.98), lineWidth: 2)
                .frame(width: 148, height: 148)
            Circle().trim(from: 0.58, to: 0.79)
                .stroke(Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 126, height: 126)
                .rotationEffect(.degrees(-90))
            Circle().trim(from: 0.08, to: 0.29)
                .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 126, height: 126)
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(LinearGradient(colors: [
                    Color(red: 0.40, green: 0.25, blue: 0.65),
                    Color(red: 0.88, green: 0.36, blue: 0.58),
                    Color(red: 0.98, green: 0.58, blue: 0.34)
                ], startPoint: .top, endPoint: .bottom))
                .frame(width: 60, height: 60)
                .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 0.8))
            Circle().fill(Color(red: 10/255, green: 14/255, blue: 31/255))
                .frame(width: 11, height: 11)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
        .accessibilityHidden(true)
    }

    private var discoveryTabBar: some View {
        HStack(spacing: 0) {
            discoveryTab("首页", symbol: "house", selected: selectedMainTab == "首页")
            discoveryTab("搜索", symbol: "magnifyingglass", selected: selectedMainTab == "搜索")
            discoveryTab("音乐库", symbol: "music.note", selected: selectedMainTab == "音乐库")
        }
        .padding(.horizontal, 12)
        .padding(.top, 5)
        .padding(.bottom, 4)
        .background {
            Color(red: 0.035, green: 0.047, blue: 0.075)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 0.8)
                }
        }
    }

    private func discoveryTab(_ title: String, symbol: String, selected: Bool) -> some View {
        Button { onSelectMainTab(title) } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 25, weight: .medium))
                    .frame(height: 29)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(selected ? Color(red: 0.36, green: 0.66, blue: 1) : .white.opacity(0.78))
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private var topBar: some View {
        HStack {
            Button { closePage() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            Text(title)
                .font(.system(size: 27, weight: .bold))
                .tracking(5)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(.white)
        .frame(height: 48)
        .padding(.bottom, 2)
    }

    private var isRecommendationPlaylistRoute: Bool {
        if case .playlistByID = route { return true }
        return false
    }

    private var isRecommendationRoute: Bool {
        if case .daily = route { return true }
        if case .featuredPick = route { return true }
        return false
    }

    private var recommendationTabs: some View {
        HStack(spacing: 12) {
            recommendationTabButton("每日推荐", tab: .daily)
            recommendationTabButton("精选歌曲", tab: .featured)
        }
    }

    private func recommendationTabButton(_ title: String, tab: RecommendationTab) -> some View {
        let selected = selectedRecommendationTab == tab
        return Button {
            guard selectedRecommendationTab != tab else { return }
            selectedRecommendationTab = tab
            songs = []
            errorMessage = nil
            isLoading = true
            Task { await loadRecommendationSongs(for: tab) }
        } label: {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(selected ? Color(red: 0.08, green: 0.10, blue: 0.25) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(selected ? Color(red: 0.87, green: 0.89, blue: 0.96) : Color.white.opacity(0.035), in: Capsule())
                .overlay(Capsule().stroke(selected ? .white.opacity(0.18) : Color(red: 0.18, green: 0.24, blue: 0.46), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var featuredRecommendationHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            ZStack(alignment: .bottomLeading) {
                Image("featured_playlist").resizable().scaledToFill()
                LinearGradient(colors: [.clear, .black.opacity(0.56)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text("精选歌曲").font(.system(size: 27, weight: .bold)).foregroundStyle(.white)
                    Text("热歌精选").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.84))
                }
                .padding(22)
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            playAllBar
        }
    }

    @MainActor
    private func loadRecommendationSongs(for tab: RecommendationTab) async {
        if let cached = recommendationSongCache[tab], !cached.isEmpty {
            songs = cached
            errorMessage = nil
            isLoading = false
            return
        }
        let requestToken = UUID()
        songsLoadToken = requestToken
        isLoading = songs.isEmpty
        errorMessage = nil
        defer {
            if songsLoadToken == requestToken { isLoading = false }
        }
        do {
            let result: [MusicSong]
            if tab == .daily {
                result = try await catalog.dailyRecommendedSongs(count: 30)
            } else {
                // 精选歌曲独立于每日推荐：从平台热歌榜提取真实歌曲条目。
                result = Array((try await catalog.toplist("热歌榜", count: 100)).shuffled().prefix(50))
            }
            guard !Task.isCancelled, songsLoadToken == requestToken else { return }
            recommendationSongCache[tab] = result
            songs = result
            if result.isEmpty {
                errorMessage = tab == .daily ? "每日推荐暂时没有可用歌曲" : "精选歌曲暂时没有可用歌曲"
            }
        } catch {
            guard !Task.isCancelled, songsLoadToken == requestToken else { return }
            errorMessage = tab == .daily
                ? "每日推荐暂时无法加载：\(error.localizedDescription)"
                : "精选歌曲暂时无法加载：\(error.localizedDescription)"
        }
    }

    private var dailyHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image("daily_recommend")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            playAllBar
        }
    }

    private var newReleasesHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("新歌速递").font(.system(size: 28, weight: .bold))
            Text("MusicX 新歌精选 · 持续更新").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
        }
    }

    private var playlistIntro: some View {
        playlistCategoryIntro(title: "心情歌单", subtitle: "从不同心情与场景中，发现适合此刻的音乐")
    }

    private var featuredPlaylistsIntro: some View {
        playlistCategoryIntro(title: "推荐歌单", subtitle: "来自网易云音乐与 QQ 音乐的真实歌单")
    }

    private func playlistCategoryIntro(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Capsule()
                    .fill(Color(red: 0.31, green: 0.53, blue: 1.0))
                    .frame(width: 4, height: 24)
                Text(title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.94, green: 0.95, blue: 0.99))
            }
            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 0.69, green: 0.72, blue: 0.81))
        }
        .padding(.top, 4)
    }

    private var albumsIntro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("热门专辑").font(.system(size: 27, weight: .bold, design: .rounded))
            Text("精选专辑与代表作品").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.66))
        }.padding(.top, 4)
    }

    // DESIGN LOCK: fixed skyline hero from the ranking reference; never swap artwork or copy when chart tabs change.
    private var chartIntro: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.48, green: 0.16, blue: 0.62), location: 0.00),
                    .init(color: Color(red: 0.77, green: 0.30, blue: 0.55), location: 0.34),
                    .init(color: Color(red: 0.98, green: 0.48, blue: 0.37), location: 0.70),
                    .init(color: Color(red: 0.96, green: 0.60, blue: 0.30), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            ChartSkyline()
                .fill(Color(red: 0.055, green: 0.055, blue: 0.15))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            LinearGradient(
                colors: [.clear, Color(red: 0.035, green: 0.045, blue: 0.11).opacity(0.96)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 7) {
                Text("热歌榜")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("当下最热的 50 首 · 每日更新")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.leading, 20)
            .padding(.bottom, 24)
            Button {
                guard !songs.isEmpty else { return }
                onQueueChanged(songs)
                onPlay(songs[0])
            } label: {
                Label("播放全部", systemImage: "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.035, green: 0.045, blue: 0.11))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.94, green: 0.95, blue: 0.99), in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(18)
        }
        .frame(height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private func albumArtworkName(title: String, artist: String) -> String {
        switch title {
        case "DUO": "album_01"
        case "最伟大的作品": "album_02"
        case "宇宙的有趣": "album_03"
        case "LINK": "album_04"
        case "幼鸟指南": "album_05"
        default: artist == "陈奕迅" ? "album_01" : "album_02"
        }
    }

    // These names map to the six imported high-resolution catalog image sets.
    private func categoryArtworkName(for name: String) -> String {
        switch name {
        case "开心愉悦", "华语流行精选": "category_chinese_pop"
        case "温柔治愈": "playlist_relax"
        case "放松舒缓": "category_light"
        case "安静专注", "影视原声精选": "category_instrumental"
        case "释放情绪": "category_rock"
        case "夜晚助眠": "playlist_night"
        case "本周编辑精选": "featured_playlist"
        case "经典金曲精选": "category_classic"
        case "通勤驾驶精选": "playlist_drive"
        default: "category_singers"
        }
    }

    private func detailBanner(_ name: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .bottomLeading) {
                Image(categoryArtworkName(for: name)).resizable().scaledToFill()
                LinearGradient(colors: [.black.opacity(0.02), .black.opacity(0.66)], startPoint: .top, endPoint: .bottom)
                Circle().fill(MusicXTheme.blue.opacity(0.18)).frame(width: 210, height: 210).blur(radius: 42).offset(x: 210, y: -70)
                Image(systemName: "waveform").font(.system(size: 100, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.14)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(26)
                VStack(alignment: .leading, spacing: 7) {
                    Text(name).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.70))
                }.padding(24)
            }
            .frame(height: 196)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.13), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.22), radius: 20, y: 10)
            playAllBar
        }
    }

    private func musicCategoryAlbumHeader(title: String, subtitle: String, artwork: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 136, height: 136)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
                VStack(alignment: .leading, spacing: 9) {
                    Text(title).font(.system(size: 23, weight: .bold)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(MusicXTheme.blue)
                    Text("精选分类 · \(songs.count) 首").font(.system(size: 12)).foregroundStyle(MusicXTheme.muted)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button {
                    guard let first = songs.first else { return }
                    onQueueChanged(songs)
                    onPlay(first)
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.035, green: 0.045, blue: 0.11))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.94, green: 0.95, blue: 0.99), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)
                Button {
                    guard !songs.isEmpty else { return }
                    let shuffled = songs.shuffled()
                    onQueueChanged(shuffled)
                    onPlay(shuffled[0])
                } label: {
                    Label("随机播放", systemImage: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.085, green: 0.105, blue: 0.20), in: Capsule())
                        .overlay(Capsule().stroke(Color(red: 0.19, green: 0.23, blue: 0.43), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)
            }
        }
    }

    private var musicCategoryTrackList: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView().tint(MusicXTheme.blue).frame(maxWidth: .infinity).padding(.vertical, 28)
            } else if let errorMessage, songs.isEmpty {
                Text("内容暂时无法加载，请稍后重试").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if songs.isEmpty {
                Text("暂时没有找到曲目").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    let isCurrent = currentSong?.id == song.id
                    Button {
                        onQueueChanged(songs)
                        onPlay(song)
                    } label: {
                        HStack(spacing: 14) {
                            if isCurrent && isPlaying {
                                Image(systemName: "waveform")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(MusicXTheme.blue)
                                    .frame(width: 22)
                            } else {
                                Text("\(index + 1)")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(MusicXTheme.muted)
                                    .frame(width: 22)
                            }
                            Text(song.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isCurrent ? MusicXTheme.blue : .white)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(MusicXTheme.muted)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 76)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isCurrent ? Color(red: 0.10, green: 0.15, blue: 0.30) : .clear,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(alignment: .bottom) {
                            if !isCurrent {
                                Rectangle().fill(Color(red: 0.13, green: 0.16, blue: 0.28)).frame(height: 0.7)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recommendationPlaylistBanner(_ playlist: MusicPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                AsyncImage(url: playlist.artworkURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color(red: 0.24, green: 0.30, blue: 0.58), Color(red: 0.08, green: 0.10, blue: 0.20)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note.list")
                                .font(.system(size: 42, weight: .light))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
                .frame(width: 134, height: 134)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))

                VStack(alignment: .leading, spacing: 9) {
                    Text(playlist.name)
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text("共 \(songs.count) 首")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(red: 0.69, green: 0.76, blue: 0.94))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    guard let first = songs.first else { return }
                    onQueueChanged(songs)
                    onPlay(first)
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.035, green: 0.045, blue: 0.11))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.94, green: 0.95, blue: 0.99), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)

                Button {
                    guard !songs.isEmpty else { return }
                    let shuffledSongs = songs.shuffled()
                    onQueueChanged(shuffledSongs)
                    onPlay(shuffledSongs[0])
                } label: {
                    Label("随机播放", systemImage: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.085, green: 0.105, blue: 0.20), in: Capsule())
                        .overlay(Capsule().stroke(Color(red: 0.19, green: 0.23, blue: 0.43), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)
            }
        }
    }

    private func albumBanner(title: String, artist: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(albumArtworkName(title: title, artist: artist))
                    .resizable()
                    .scaledToFill()
                    .frame(width: 134, height: 134)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
                VStack(alignment: .leading, spacing: 9) {
                    Text(title).font(.system(size: 27, weight: .bold)).foregroundStyle(.white)
                    Text(artist).font(.system(size: 15, weight: .medium)).foregroundStyle(MusicXTheme.blue)
                    Text("专辑 · 共 \(songs.count) 首").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button {
                    guard let first = songs.first else { return }
                    onQueueChanged(songs)
                    onPlay(first)
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.035, green: 0.045, blue: 0.11))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.94, green: 0.95, blue: 0.99), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)
                Button {
                    guard !songs.isEmpty else { return }
                    let shuffledSongs = songs.shuffled()
                    onQueueChanged(shuffledSongs)
                    onPlay(shuffledSongs[0])
                } label: {
                    Label("随机播放", systemImage: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.085, green: 0.105, blue: 0.20), in: Capsule())
                        .overlay(Capsule().stroke(Color(red: 0.19, green: 0.23, blue: 0.43), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(songs.isEmpty)
            }
        }
    }

    private func artwork(title: String, subtitle: String, colors: [Color], height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "waveform").font(.system(size: 70, weight: .ultraLight)).foregroundStyle(.white.opacity(0.16)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(18)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 18, weight: .bold)).lineLimit(2)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            }.padding(18)
        }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var playAllBar: some View {
        HStack {
            Button {
                guard !songs.isEmpty else { return }
                onQueueChanged(songs)
                onPlay(songs[0])
            } label: {
                Label("播放全部", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 20).padding(.vertical, 13)
                    .background(LinearGradient(colors: [MusicXTheme.blue, Color(red: 0.20, green: 0.43, blue: 0.84)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.20), lineWidth: 1))
                    .shadow(color: MusicXTheme.blue.opacity(0.22), radius: 12, y: 5)
            }.buttonStyle(.plain)
            Spacer()
            Text("\(songs.count) 首").font(.system(size: 12, weight: .medium)).foregroundStyle(MusicXTheme.muted)
        }
    }

    private func miniPlayerBar(song: MusicSong?) -> some View {
        HStack(spacing: 10) {
            Button(action: onOpenPlayer) {
                HStack(spacing: 10) {
                    Group {
                        if let song {
                            SongArtworkView(song: song, tint: MusicXTheme.blue, size: 40)
                        } else {
                            Image("player_cover")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(song?.title ?? "尚未播放")
                            .font(.system(size: isRecommendationRoute ? 17 : 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(song?.artist ?? "选择一首歌曲开始聆听")
                            .font(.system(size: isRecommendationRoute ? 13 : 11)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !isRecommendationRoute {
                Button(action: onPrevious) {
                    Image(systemName: "backward.end.fill").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92)).frame(width: 30, height: 46)
                }.buttonStyle(.plain).disabled(song == nil)
            }
            Button(action: onTogglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.22), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 1))
            }.buttonStyle(.plain).disabled(song == nil)
            Button(action: onNext) {
                Image(systemName: "forward.end.fill").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92)).frame(width: 30, height: 46)
            }.buttonStyle(.plain).disabled(song == nil)
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.10, green: 0.12, blue: 0.27).opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [
                            Color(red: 0.40, green: 0.31, blue: 0.66).opacity(0.34),
                            Color(red: 0.08, green: 0.11, blue: 0.25).opacity(0.12)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.30), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.30), radius: 16, y: 7)
        .padding(.horizontal, 12)
    }

    private var progressFraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(currentTime / duration, 0), 1))
    }

    private func playlistCardArtwork(for key: String, fallback: String, width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        Image(fallback)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
    }

    private var playlistGrid: some View {
        playlistCategoryGrid(items: [
            PlaylistCardItem(title: "开心愉悦", subtitle: "明亮轻快，让好心情延续", artwork: "category_chinese_pop"),
            PlaylistCardItem(title: "温柔治愈", subtitle: "温暖柔和，给情绪一点空间", artwork: "playlist_relax"),
            PlaylistCardItem(title: "放松舒缓", subtitle: "舒缓节奏，放松身心", artwork: "category_light"),
            PlaylistCardItem(title: "安静专注", subtitle: "纯音乐与轻旋律，适合专注", artwork: "category_instrumental"),
            PlaylistCardItem(title: "释放情绪", subtitle: "用更有力量的节奏释放压力", artwork: "category_rock"),
            PlaylistCardItem(title: "夜晚助眠", subtitle: "安静氛围，适合睡前聆听", artwork: "playlist_night")
        ])
    }

    private var featuredPlaylistGrid: some View {
        let screenWidth = UIScreen.main.bounds.width
        let cardWidth = max((screenWidth - 32 - 12) / 2, 0)
        return LazyVGrid(
            columns: [GridItem(.fixed(cardWidth), spacing: 12), GridItem(.fixed(cardWidth), spacing: 12)],
            alignment: .leading,
            spacing: 14
        ) {
            if featuredPlaylistResults.isEmpty {
                if isLoading {
                    ProgressView().tint(MusicXTheme.blue).frame(maxWidth: .infinity).padding(.vertical, 28).gridCellColumns(2)
                } else {
                    Text("暂时没有可展示的歌单")
                        .font(.system(size: 13))
                        .foregroundStyle(MusicXTheme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 28).gridCellColumns(2)
                }
            } else {
                ForEach(Array(featuredPlaylistResults.enumerated()), id: \.element.id) { index, playlist in
                    featuredPlaylistTile(playlist, index: index, width: cardWidth, imageHeight: cardWidth * 0.705)
                }
            }
        }
    }

    private func featuredPlaylistTile(_ playlist: MusicPlaylist, index: Int, width: CGFloat, imageHeight: CGFloat) -> some View {
        Button { onOpenPlaylist(playlist) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let artworkURL = playlist.artworkURL {
                        AsyncImage(url: artworkURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                gradientCollectionCard(index: index, title: playlist.name)
                            }
                        }
                    } else {
                        gradientCollectionCard(index: index, title: playlist.name)
                    }
                }
                .frame(width: width, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(playlist.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.94, green: 0.95, blue: 0.99))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(playlist.source.displayName)
                    Text("· " + {
                        switch playlist.provenance {
                        case .some(.officialEditorial): "官方精选"
                        case .some(.platformRecommended): "平台推荐"
                        case .some(.categoryFeatured): "分类推荐"
                        case .some(.searchResult), .none: "歌单"
                        }
                    }())
                    if let trackCount = playlist.trackCount, trackCount > 0 {
                        Text("· \(trackCount)首")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.69, green: 0.72, blue: 0.81))
                .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Mood and editorial categories deliberately share one page template and card geometry.
    private func playlistCategoryGrid(items: [PlaylistCardItem]) -> some View {
        let screenWidth = UIScreen.main.bounds.width
        let cardWidth = max((screenWidth - 32 - 12) / 2, 0)
        return LazyVGrid(
            columns: [GridItem(.fixed(cardWidth), spacing: 12), GridItem(.fixed(cardWidth), spacing: 12)],
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(items, id: \.title) { item in
                playlistTile(item, width: cardWidth, imageHeight: cardWidth * 0.705)
            }
        }
    }

    private func playlistTile(_ item: PlaylistCardItem, width: CGFloat, imageHeight: CGFloat) -> some View {
        Button {
            if case .featuredPlaylists = route, item.title == "本周编辑精选" {
                onOpenFeaturedPick()
            } else if let playlist = playlistCardResults[item.title] {
                onOpenPlaylist(playlist)
            } else {
                playlistUnavailableMessage = "暂未找到“\(item.title)”对应的真实歌单，暂不使用普通关键词搜索结果代替分类歌单。"
                isPlaylistUnavailableAlertPresented = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                let paletteIndex = ["本周编辑精选", "华语流行精选", "经典金曲精选", "独立音乐精选", "影视原声精选", "通勤驾驶精选", "开心愉悦", "温柔治愈", "放松舒缓", "安静专注", "释放情绪", "夜晚助眠"].firstIndex(of: item.title) ?? 0
                gradientCollectionCard(index: paletteIndex, title: item.title)
                    .frame(width: width, height: imageHeight)
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.94, green: 0.95, blue: 0.99))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.69, green: 0.72, blue: 0.81))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var albumGrid: some View {
        let items = Array(featuredAlbums.prefix(6))
        let cardWidth = max((UIScreen.main.bounds.width - 32 - 12) / 2, 0)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 20) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button { onOpenAlbum(item.album ?? item.title, item.artist) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        SongArtworkView(song: item, tint: MusicXTheme.blue, size: cardWidth)
                            .frame(width: cardWidth, height: cardWidth)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
                        Text(item.album ?? item.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(item.artist).font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func gradientCollectionCard(index: Int, title: String) -> some View {
        let palettes: [[Color]] = [
            [Color(red: 0.18, green: 0.22, blue: 0.78), Color(red: 0.25, green: 0.08, blue: 0.48)],
            [Color(red: 0.82, green: 0.12, blue: 0.31), Color(red: 0.36, green: 0.05, blue: 0.20)],
            [Color(red: 0.56, green: 0.34, blue: 0.12), Color(red: 0.24, green: 0.12, blue: 0.08)],
            [Color(red: 0.78, green: 0.72, blue: 0.40), Color(red: 0.35, green: 0.39, blue: 0.18)],
            [Color(red: 0.76, green: 0.84, blue: 0.94), Color(red: 0.30, green: 0.45, blue: 0.62)],
            [Color(red: 0.04, green: 0.65, blue: 0.72), Color(red: 0.02, green: 0.25, blue: 0.39)],
            [Color(red: 0.25, green: 0.62, blue: 0.46), Color(red: 0.04, green: 0.24, blue: 0.22)],
            [Color(red: 0.62, green: 0.34, blue: 0.76), Color(red: 0.22, green: 0.10, blue: 0.40)],
            [Color(red: 0.90, green: 0.48, blue: 0.25), Color(red: 0.35, green: 0.13, blue: 0.09)],
            [Color(red: 0.16, green: 0.48, blue: 0.72), Color(red: 0.04, green: 0.17, blue: 0.34)],
            [Color(red: 0.78, green: 0.28, blue: 0.42), Color(red: 0.30, green: 0.08, blue: 0.22)],
            [Color(red: 0.70, green: 0.61, blue: 0.34), Color(red: 0.28, green: 0.20, blue: 0.10)],
            [Color(red: 0.35, green: 0.53, blue: 0.83), Color(red: 0.10, green: 0.17, blue: 0.43)],
            [Color(red: 0.44, green: 0.64, blue: 0.60), Color(red: 0.10, green: 0.27, blue: 0.28)],
            [Color(red: 0.72, green: 0.43, blue: 0.78), Color(red: 0.27, green: 0.11, blue: 0.38)],
            [Color(red: 0.90, green: 0.66, blue: 0.35), Color(red: 0.38, green: 0.20, blue: 0.10)]
        ]
        let colors = palettes[index % palettes.count]
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            RadialGradient(colors: [.white.opacity(0.34), .clear], center: UnitPoint(x: 0.60, y: 0.38), startRadius: 2, endRadius: 130)
            Circle().fill(Color.black.opacity(0.48))
                .frame(width: 38, height: 38)
                .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
                .overlay(Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
                .padding(12)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.42, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.34), lineWidth: 1))
        .shadow(color: colors.first!.opacity(0.20), radius: 12, y: 5)
    }

    private var chartTabs: some View {
        HStack(spacing: 8) {
            ForEach(["热歌榜", "新歌榜", "飙升榜"], id: \.self) { name in
                Button { Task { await selectChart(name) } } label: {
                    Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(selectedChart == name ? .white : MusicXTheme.muted)
                         .padding(.horizontal, 17).padding(.vertical, 11)
                        .background(selectedChart == name ? MusicXTheme.blue.opacity(0.92) : Color.white.opacity(0.055), in: Capsule())
                        .overlay(Capsule().stroke(selectedChart == name ? Color.white.opacity(0.22) : Color.white.opacity(0.08), lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }

    private var albumNote: some View {
        Text("曲目根据在线音源搜索结果整理，具体收录信息以音源返回为准。")
            .font(.system(size: 12)).foregroundStyle(MusicXTheme.muted)
    }

    private func songArtwork(_ song: MusicSong, index: Int, isCurrent: Bool, size: CGFloat = 54) -> some View {
        let palettes: [[Color]] = [
            [Color(red: 0.28, green: 0.52, blue: 0.91), Color(red: 0.10, green: 0.20, blue: 0.43)],
            [Color(red: 0.55, green: 0.36, blue: 0.84), Color(red: 0.22, green: 0.16, blue: 0.48)],
            [Color(red: 0.12, green: 0.62, blue: 0.67), Color(red: 0.06, green: 0.25, blue: 0.42)],
            [Color(red: 0.78, green: 0.43, blue: 0.30), Color(red: 0.35, green: 0.16, blue: 0.22)],
            [Color(red: 0.72, green: 0.58, blue: 0.28), Color(red: 0.34, green: 0.24, blue: 0.13)],
            [Color(red: 0.36, green: 0.60, blue: 0.57), Color(red: 0.13, green: 0.28, blue: 0.32)]
        ]
        let colors = palettes[index % palettes.count]
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            RadialGradient(colors: [.white.opacity(0.22), .clear], center: .topLeading, startRadius: 1, endRadius: size * 1.2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Image(systemName: isCurrent && isPlaying ? "waveform" : "music.note")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
        .accessibilityLabel("\(song.title) 封面占位图")
    }

    private var trackList: some View {
        VStack(spacing: 2) {
            if isLoading {
                ProgressView().tint(MusicXTheme.blue).frame(maxWidth: .infinity).padding(.vertical, 28)
            } else if let errorMessage, songs.isEmpty {
                Text("内容暂时无法加载，请稍后重试").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if songs.isEmpty {
                Text("暂时没有找到曲目").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    let isCurrent = currentSong?.id == song.id
                    Button {
                        onQueueChanged(songs)
                        onPlay(song)
                    } label: {
                        if isRecommendationPlaylistRoute {
                            HStack(spacing: 18) {
                                Text("\(index + 1)")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(isCurrent ? MusicXTheme.blue : MusicXTheme.muted)
                                    .frame(width: 24, alignment: .center)
                                Text(song.title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(isCurrent ? MusicXTheme.blue : .white)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(MusicXTheme.muted)
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 88)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(isCurrent ? MusicXTheme.blue.opacity(0.17) : Color.white.opacity(0.012))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(isCurrent ? MusicXTheme.blue.opacity(0.24) : Color.white.opacity(0.045), lineWidth: 1)
                            }
                        } else {
                            HStack(spacing: 14) {
                                songArtwork(song, index: index, isCurrent: isCurrent, size: isRecommendationRoute ? 56 : 44)
                                    .frame(width: isRecommendationRoute ? 56 : 44, height: isRecommendationRoute ? 56 : 44)
                                    .clipShape(RoundedRectangle(cornerRadius: isRecommendationRoute ? 15 : 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(song.title)
                                        .font(.system(size: isRecommendationRoute ? 17 : 15, weight: .semibold))
                                        .foregroundStyle(isCurrent ? MusicXTheme.blue : .white)
                                        .lineLimit(1)
                                    Text(song.artist)
                                        .font(.system(size: isRecommendationRoute ? 14 : 12))
                                        .foregroundStyle(isCurrent ? .white.opacity(0.78) : MusicXTheme.muted)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if isRecommendationRoute {
                                    Text(song.duration.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) } ?? "")
                                        .font(.system(size: 14))
                                        .foregroundStyle(MusicXTheme.muted)
                                } else {
                                    if isCurrent && isPlaying {
                                        Image(systemName: "waveform").font(.system(size: 13, weight: .semibold)).foregroundStyle(MusicXTheme.blue)
                                    }
                                    Image(systemName: isChartRoute ? "ellipsis" : "chevron.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(MusicXTheme.muted.opacity(0.82))
                                }
                            }
                            .padding(.horizontal, isRecommendationRoute ? 0 : 12)
                            .padding(.vertical, isRecommendationRoute ? 8 : 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background {
                                if !isRecommendationRoute {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(isCurrent ? MusicXTheme.blue.opacity(0.12) : Color.white.opacity(0.018))
                                }
                            }
                            .overlay {
                                if !isRecommendationRoute {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(isCurrent ? MusicXTheme.blue.opacity(0.30) : Color.white.opacity(0.045), lineWidth: 1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    if isRecommendationRoute && index < songs.count - 1 {
                        Rectangle().fill(.white.opacity(0.10)).frame(height: 0.7)
                            .padding(.leading, 70)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    @MainActor
    private func loadFeaturedPlaylists() async {
        if !featuredPlaylistResults.isEmpty { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let results = try await withThrowingTaskGroup(of: [MusicPlaylist].self) { group in
                group.addTask {
                    try await catalog.featuredPlaylists(count: 25)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 18_000_000_000)
                    throw MusicSourceError.invalidResponse("平台推荐歌单加载超时，请稍后重试")
                }
                guard let first = try await group.next() else {
                    throw MusicSourceError.invalidResponse("平台暂时没有返回推荐歌单")
                }
                group.cancelAll()
                return first
            }
            guard !Task.isCancelled else { return }
            featuredPlaylistResults = results
            if results.isEmpty { errorMessage = "平台暂时没有返回可用歌单" }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "推荐内容暂时无法加载，请稍后重试"
        }
    }

    @MainActor
    private func loadPlaylistCards(forMood: Bool) async {
        guard forMood else {
            await loadFeaturedPlaylists()
            return
        }
        let items: [(String, [String])] = [
            ("开心愉悦", ["开心", "快乐", "愉悦", "好心情"]),
            ("温柔治愈", ["治愈", "温柔", "疗愈", "舒缓"]),
            ("放松舒缓", ["放松", "轻松", "休闲", "Relax"]),
            ("安静专注", ["专注", "学习", "工作", "纯音乐"]),
            ("释放情绪", ["摇滚", "热血", "燃", "释放情绪"]),
            ("夜晚助眠", ["助眠", "睡眠", "晚安", "轻音乐"])
        ]

        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        }

        var updated = playlistCardResults
        var assignedPlaylistIDs = Set(updated.values.map { $0.id })
        for (category, keywords) in items where updated[category] == nil {
            guard !Task.isCancelled else { return }
            var selected: MusicPlaylist?
            var lastError: String?
            for keyword in keywords {
                guard !Task.isCancelled else { return }
                do {
                    let results = try await catalog.searchPlaylists(keyword: keyword, count: 30)
                    guard !Task.isCancelled else { return }
                    let token = normalized(keyword)
                    let match = results
                        .filter { !assignedPlaylistIDs.contains($0.id) }
                        .map { playlist -> (MusicPlaylist, Int) in
                            let name = normalized(playlist.name)
                            let score = name == token ? 100 : (name.contains(token) ? 80 : 0)
                            return (playlist, score)
                        }
                        .filter { $0.1 >= 80 }
                        .sorted {
                            if $0.1 != $1.1 { return $0.1 > $1.1 }
                            return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
                        }
                        .first?.0
                    if let match {
                        selected = match
                        break
                    }
                } catch {
                    if Task.isCancelled { return }
                    lastError = error.localizedDescription
                }
            }
            if let selected {
                updated[category] = selected
                assignedPlaylistIDs.insert(selected.id)
                playlistCardResults = updated
            } else if let lastError {
                MusicSourceDiagnostics.shared.record(
                    event: "playlist-discovery", source: MusicSource.qq.rawValue,
                    provider: "qq-playlist-search", duration: 0,
                    result: "failed", detail: "\(category): \(lastError)"
                )
            }
        }
        guard !Task.isCancelled else { return }
        playlistCardResults = updated
    }

    @MainActor
    private func loadSongs() async {
        let requestToken = UUID()
        songsLoadToken = requestToken
        if isRecommendationRoute {
            await loadRecommendationSongs(for: selectedRecommendationTab)
            return
        }
        if case .playlists = route {
            songs = []
            await loadPlaylistCards(forMood: true)
            return
        }
        if case .featuredPlaylists = route {
            songs = []
            await loadPlaylistCards(forMood: false)
            return
        }
        if case .albums = route { songs = []; return }
        if isChartRoute { await loadChart(selectedChart, showInitialLoading: true); return }
        isLoading = true
        errorMessage = nil
        defer {
            if songsLoadToken == requestToken { isLoading = false }
        }
        do {
            var result: [MusicSong]
            switch route {
            case .charts, .chart:
                result = []
            case .newReleases:
                result = try await catalog.toplist("新歌榜", count: 50)
            case .album(let albumTitle, let albumArtist):
                result = await searchAlbumTracks(title: albumTitle, artist: albumArtist)
            case .musicCategory(_, _, _, let keyword):
                result = try await catalog.search(keyword: keyword, source: .netease, count: 30)
            case .featuredPick:
                result = []
            case .playlist(let name):
                result = try await catalog.playlistTracks(keyword: name, count: 50)
            case .playlistByID(let playlist):
                do {
                    result = try await catalog.playlistTracks(
                        playlistID: playlist.sourceID,
                        source: playlist.source,
                        count: 50
                    )
                } catch {
                    if Task.isCancelled { return }
                    result = []
                    MusicSourceDiagnostics.shared.record(
                        event: "playlist-tracks",
                        source: playlist.source.rawValue,
                        provider: "\(playlist.source.rawValue)-playlist-detail",
                        duration: 0,
                        result: "failed",
                        detail: playlist.name
                    )
                }
            default:
                result = try await catalog.search(keyword: query, source: .netease, count: 30)
            }
            if result.isEmpty, case .playlistByID(let playlist) = route {
                let alternatives = (try? await catalog.searchPlaylists(
                    keyword: playlist.name,
                    count: 30
                )) ?? []
                let normalizedName = playlist.name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ).filter { $0.isLetter || $0.isNumber }
                if let alternate = alternatives.first(where: { candidate in
                    let candidateName = candidate.name.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    ).filter { $0.isLetter || $0.isNumber }
                    return candidate.source != playlist.source
                        && !normalizedName.isEmpty
                        && candidateName == normalizedName
                }) {
                    result = (try? await catalog.playlistTracks(
                        playlistID: alternate.sourceID,
                        source: alternate.source,
                        count: 50
                    )) ?? []
                    MusicSourceDiagnostics.shared.record(
                        event: "playlist-tracks",
                        source: playlist.source.rawValue,
                        provider: "cross-catalog-playlist-fallback",
                        duration: 0,
                        result: result.isEmpty ? "failed" : "fallback_success",
                        detail: playlist.name
                    )
                }
            }
            guard !Task.isCancelled, songsLoadToken == requestToken else { return }
            songs = result
            if songs.isEmpty {
                errorMessage = "内容暂时无法加载，请稍后重试"
            }
        } catch {
            guard !Task.isCancelled, songsLoadToken == requestToken else { return }
            errorMessage = "内容暂时无法加载，请稍后重试"
        }
    }


    private func searchAlbumTracks(title: String, artist: String) async -> [MusicSong] {
        func normalize(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        }

        let albumToken = normalize(title)
        let artistToken = normalize(artist)
        guard !albumToken.isEmpty, !artistToken.isEmpty else { return [] }

        let sources: [MusicSource] = [.netease, .qq, .kuwo, .kugou, .migu]
        var candidates: [MusicSong] = []

        // Album-specific endpoints first; regular song search is a fallback when providers
        // omit album metadata or their album endpoint returns no usable rows.
        for source in sources {
            guard !Task.isCancelled else { return candidates }
            do {
                let rows = try await catalog.search(keyword: title, source: source, count: 50, albumOnly: true)
                candidates.append(contentsOf: rows)
            } catch {
                if Task.isCancelled { return candidates }
                MusicSourceDiagnostics.shared.record(
                    event: "album-search", source: source.rawValue,
                    provider: "gdstudio-album-search", duration: 0,
                    result: "failed", detail: error.localizedDescription
                )
            }
        }

        let hasCredibleAlbumResults = candidates.contains { song in
            let songArtist = normalize(song.artist)
            let album = normalize(song.album ?? "")
            return !album.isEmpty
                && (album == albumToken || album.contains(albumToken) || albumToken.contains(album))
                && (songArtist.contains(artistToken) || artistToken.contains(songArtist))
        }

        if !hasCredibleAlbumResults {
            for source in sources {
                guard !Task.isCancelled else { return candidates }
                do {
                    let rows = try await catalog.search(keyword: "\(title) \(artist)", source: source, count: 50)
                    candidates.append(contentsOf: rows)
                } catch {
                    if Task.isCancelled { return candidates }
                    MusicSourceDiagnostics.shared.record(
                        event: "album-fallback-search", source: source.rawValue,
                        provider: "gdstudio-search", duration: 0,
                        result: "failed", detail: error.localizedDescription
                    )
                }
            }
        }

        func versionMarkers(_ song: MusicSong) -> String {
            let text = normalize("\(song.title) \(song.album ?? "")")
            let markers = ["live", "remix", "cover", "acoustic", "instrumental", "伴奏", "纯音乐", "现场", "翻唱", "混音", "演唱会"]
            return markers.filter { text.contains(normalize($0)) }.sorted().joined(separator: ",")
        }

        // Keep likely album tracks. Missing album metadata is tolerated only when the
        // provider search also identifies the requested artist; explicit conflicting albums
        // are down-ranked rather than silently discarded.
        let ranked: [(MusicSong, Int)] = candidates.compactMap { song in
            let songArtist = normalize(song.artist)
            let songAlbum = normalize(song.album ?? "")
            let artistMatch = songArtist == artistToken
                || songArtist.contains(artistToken)
                || artistToken.contains(songArtist)
            guard artistMatch else { return nil }

            let albumScore: Int
            if songAlbum.isEmpty {
                albumScore = 35
            } else if songAlbum == albumToken {
                albumScore = 100
            } else if songAlbum.contains(albumToken) || albumToken.contains(songAlbum) {
                albumScore = 75
            } else {
                albumScore = 0
            }
            guard albumScore >= 35 else { return nil }
            return (song, albumScore + (songAlbum.isEmpty ? 0 : 10))
        }

        var seenRecordings = Set<String>()
        let sorted = ranked.sorted { $0.1 > $1.1 }
        let unique = sorted.compactMap { song, _ -> MusicSong? in
            let titleKey = normalize(song.title)
            let artistKey = normalize(song.artist)
            guard !titleKey.isEmpty else { return nil }
            let durationKey = song.duration.map { String(Int($0.rounded())) } ?? "unknown"
            let key = "\(titleKey)|\(artistKey)|\(versionMarkers(song))|\(durationKey)"
            return seenRecordings.insert(key).inserted ? song : nil
        }
        return Array(unique.prefix(50))
    }

    @MainActor
    private func selectChart(_ name: String) async {
        guard name != selectedChart else { return }
        selectedChartOverride = name
        let requestToken = UUID()
        chartLoadToken = requestToken
        if let cached = chartSongCache[name], !cached.isEmpty {
            songs = cached
            errorMessage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer {
            if chartLoadToken == requestToken { isLoading = false }
        }
        do {
            let result = try await catalog.toplist(name, count: 50)
            guard !Task.isCancelled, chartLoadToken == requestToken else { return }
            if !result.isEmpty {
                chartSongCache[name] = result
                songs = result
                errorMessage = nil
            } else {
                songs = []
                errorMessage = "音源没有返回匹配的歌曲，请稍后重试"
            }
        } catch {
            guard !Task.isCancelled, chartLoadToken == requestToken else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadChart(_ name: String, showInitialLoading: Bool) async {
        let requestToken = UUID()
        chartLoadToken = requestToken
        if let cached = chartSongCache[name], !cached.isEmpty {
            songs = cached
            errorMessage = nil
            return
        }
        if showInitialLoading { isLoading = true }
        errorMessage = nil
        defer {
            if showInitialLoading, chartLoadToken == requestToken { isLoading = false }
        }
        do {
            let result = try await catalog.toplist(name, count: 50)
            guard !Task.isCancelled, chartLoadToken == requestToken else { return }
            if !result.isEmpty { chartSongCache[name] = result }
            songs = result
            if result.isEmpty { errorMessage = "音源没有返回匹配的歌曲，请稍后重试" }
        } catch {
            guard !Task.isCancelled, chartLoadToken == requestToken else { return }
            errorMessage = error.localizedDescription
        }
    }
}


// Static city silhouette used by the fixed ranking banner.
private struct ChartSkyline: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let points: [(CGFloat, CGFloat)] = [
            (0.00, 0.78), (0.04, 0.78), (0.04, 0.66), (0.10, 0.66),
            (0.10, 0.72), (0.16, 0.72), (0.16, 0.57), (0.21, 0.57),
            (0.21, 0.63), (0.27, 0.63), (0.27, 0.42), (0.32, 0.35),
            (0.37, 0.42), (0.37, 0.68), (0.43, 0.68), (0.43, 0.58),
            (0.49, 0.58), (0.49, 0.72), (0.55, 0.72), (0.55, 0.52),
            (0.61, 0.52), (0.61, 0.68), (0.67, 0.68), (0.67, 0.60),
            (0.73, 0.60), (0.73, 0.73), (0.79, 0.73), (0.79, 0.55),
            (0.84, 0.55), (0.84, 0.70), (0.90, 0.70), (0.90, 0.62),
            (0.95, 0.62), (0.95, 0.75), (1.00, 0.75), (1.00, 1.00),
            (0.00, 1.00)
        ]
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        for (x, y) in points {
            path.addLine(to: CGPoint(x: x * w, y: y * h))
        }
        path.closeSubpath()
        return path
    }
}
