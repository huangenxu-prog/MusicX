import SwiftUI

enum MusicDiscoveryRoute: Identifiable {
    case daily, playlists, featuredPlaylists, albums, charts, newReleases
    case chart(String)
    case featuredPick
    case playlist(String)
    case playlistByID(MusicPlaylist)
    case album(title: String, artist: String)
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
        }
    }
}

private struct PlaylistCardItem {
    let title: String
    let subtitle: String
    let artwork: String
}

struct MusicDiscoveryPage: View {
    let route: MusicDiscoveryRoute
    let onClose: () -> Void
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
    @State private var playlistCardResults: [String: MusicPlaylist] = [:]
    @State private var isPlaylistUnavailableAlertPresented = false
    @State private var playlistUnavailableMessage = ""
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
    private let service = GDStudioMusicSearchService()

    private func closePage() {
        onClose()
    }

    private func playlistSubtitle(for name: String) -> String {
        let moodNames: Set<String> = ["开心愉悦", "温柔治愈", "放松舒缓", "安静专注", "释放情绪", "夜晚助眠"]
        let featuredNames: Set<String> = ["本周编辑精选", "华语流行精选", "经典金曲精选", "独立音乐精选", "影视原声精选", "通勤驾驶精选"]
        if moodNames.contains(name) { return "心情歌单" }
        return featuredNames.contains(name) ? "精选歌单" : "歌单"
    }

    private var title: String {
        switch route {
        case .daily: "每日推荐"
        case .playlists: "心情歌单"
        case .featuredPlaylists: "精选歌单"
        case .featuredPick: "编辑精选"
        case .albums: "热门专辑"
        case .charts, .chart: "排行榜"
        case .newReleases: "新歌速递"
        case .playlist(let name): name
        case .playlistByID(let playlist): playlist.name
        case .album(let title, _): title
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
        }
    }

    var body: some View {
        ZStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.018, green: 0.040, blue: 0.095), Color(red: 0.025, green: 0.055, blue: 0.115), Color(red: 0.014, green: 0.030, blue: 0.075)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(red: 0.48, green: 0.12, blue: 0.58).opacity(0.38), .clear], center: .top, startRadius: 12, endRadius: 520)
                RadialGradient(colors: [Color(red: 1.0, green: 0.34, blue: 0.36).opacity(0.16), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
            }.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    topBar
                    switch route {
                    case .daily: dailyHeader
                    case .playlists: playlistIntro
                    case .featuredPlaylists: featuredPlaylistsIntro
                    case .featuredPick: detailBanner("本周编辑精选", subtitle: "精选歌单")
                    case .albums: albumsIntro
                    case .charts, .chart: chartIntro
                    case .newReleases: newReleasesHeader
                    case .playlist(let name): detailBanner(name, subtitle: playlistSubtitle(for: name))
                    case .playlistByID(let playlist): detailBanner(playlist.name, subtitle: playlistSubtitle(for: playlist.name))
                    case .album(let title, let artist): albumBanner(title: title, artist: artist)
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
                        if case .album = route { albumNote }
                        trackList
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            miniPlayerBar(song: currentSong)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 22, coordinateSpace: .global).onEnded { value in
            let horizontal = value.translation.width
            let vertical = value.translation.height
            guard value.startLocation.x <= 28, horizontal > 88, horizontal > abs(vertical) * 1.25 else { return }
            closePage()
        })
        .task(id: route.id) { await loadSongs() }
        .alert("暂未找到匹配歌单", isPresented: $isPlaylistUnavailableAlertPresented) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(playlistUnavailableMessage)
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: closePage) {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                    .frame(width: 48, height: 46, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).zIndex(10)
            Spacer()
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer()
            Color.clear.frame(width: 48, height: 46)
        }.foregroundStyle(.white).padding(.bottom, 4)
    }

    private var dailyHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            ZStack(alignment: .bottomLeading) {
                Image("daily_recommend").resizable().scaledToFill()
                LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "sun.horizon.fill").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(.white.opacity(0.13)).frame(maxWidth: .infinity, alignment: .topTrailing).padding(22)
                VStack(alignment: .leading, spacing: 7) {
                    Text("为你精选").font(.system(size: 27, weight: .bold))
                    Text("根据在线曲库整理 · 每日更新").font(.system(size: 13)).foregroundStyle(.white.opacity(0.72))
                }.padding(22)
            }.frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 24))
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
        playlistCategoryIntro(title: "编辑精选", subtitle: "从不同风格与场景中，发现值得收藏的歌单")
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

    private var chartIntro: some View {
        ZStack(alignment: .bottomLeading) {
            Image(chartArtworkName).resizable().scaledToFill()
            LinearGradient(colors: [.black.opacity(0.02), .black.opacity(0.70)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 7) {
                Text("排行榜").font(.system(size: 29, weight: .bold, design: .rounded))
                Text("MusicX 精选榜单 · 持续更新").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.78))
            }.padding(22)
        }
        .frame(height: 194).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.13), lineWidth: 1))
    }

    private var chartArtworkName: String {
        switch selectedChart {
        case "新歌榜": "chart_new"
        case "飙升榜": "chart_rising"
        default: "chart_hot"
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

    private func albumBanner(title: String, artist: String) -> some View {
        HStack(spacing: 18) {
            artwork(title: title, subtitle: artist, colors: [Color(red: 0.20, green: 0.42, blue: 0.68), Color(red: 0.10, green: 0.16, blue: 0.30)], height: 176).frame(width: 176)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 22, weight: .bold))
                Text(artist).font(.system(size: 14)).foregroundStyle(MusicXTheme.muted)
                Text("专辑曲目").font(.system(size: 12)).foregroundStyle(MusicXTheme.muted)
            }
            Spacer(minLength: 0)
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
            Button { if let first = songs.first { onPlay(first) } } label: {
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
                            SongArtworkView(song: song, tint: MusicXTheme.blue, size: 48)
                        } else {
                            Image("player_cover")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(song?.title ?? "尚未播放")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(song?.artist ?? "选择一首歌曲开始聆听")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: onPrevious) {
                Image(systemName: "backward.end.fill").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92)).frame(width: 30, height: 46)
            }.buttonStyle(.plain).disabled(song == nil)
            Button(action: onTogglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.22), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 1))
            }.buttonStyle(.plain).disabled(song == nil)
            Button(action: onNext) {
                Image(systemName: "forward.end.fill").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92)).frame(width: 30, height: 46)
            }.buttonStyle(.plain).disabled(song == nil)
            Button(action: onOpenQueue) {
                Image(systemName: "list.bullet").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92)).frame(width: 30, height: 46)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 76)
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
        playlistCategoryGrid(items: [
            PlaylistCardItem(title: "本周编辑精选", subtitle: "本周精选", artwork: "featured_playlist"),
            PlaylistCardItem(title: "华语流行精选", subtitle: "宝藏好歌 · 优质华语流行歌曲合集", artwork: "category_chinese_pop"),
            PlaylistCardItem(title: "经典金曲精选", subtitle: "经久不衰的动人歌声", artwork: "category_classic"),
            PlaylistCardItem(title: "独立音乐精选", subtitle: "Indie Music｜独立音乐聚落", artwork: "category_singers"),
            PlaylistCardItem(title: "影视原声精选", subtitle: "问心系列 影视原声带", artwork: "category_instrumental"),
            PlaylistCardItem(title: "通勤驾驶精选", subtitle: "通勤路上｜有前行感的节奏", artwork: "playlist_drive")
        ])
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
                playlistCardArtwork(
                    for: item.title,
                    fallback: item.artwork,
                    width: width,
                    height: imageHeight,
                    cornerRadius: 16
                )
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
        let items: [(String, String, String)] = [
            ("DUO", "陈奕迅", "album_01"),
            ("最伟大的作品", "周杰伦", "album_02"),
            ("宇宙的有趣", "告五人", "album_03"),
            ("LINK", "A-Lin", "album_04"),
            ("幼鸟指南", "毛不易", "album_05")
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
            ForEach(items, id: \.0) { item in
                Button { onOpenAlbum(item.0, item.1) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(item.2).resizable().scaledToFill()
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
                        Text(item.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(item.1).font(.system(size: 10)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                    }
                }.buttonStyle(.plain)
            }
        }
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
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
                .frame(width: 39, height: 39)
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 1)
                .frame(width: 25, height: 25)
            Image(systemName: isCurrent && isPlaying ? "waveform" : "music.note")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
            if isCurrent && isPlaying {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: 8)
                    .offset(x: 18, y: 18)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
        .accessibilityLabel("\(song.title) 封面占位图")
    }

    private var trackList: some View {
        VStack(spacing: 10) {
            if isLoading {
                ProgressView().tint(MusicXTheme.blue).frame(maxWidth: .infinity).padding(.vertical, 28)
            } else if let errorMessage, songs.isEmpty {
                Text(errorMessage).font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if songs.isEmpty {
                Text("暂时没有找到曲目").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    let isCurrent = currentSong?.id == song.id
                    Button { onPlay(song) } label: {
                        HStack(spacing: 12) {
                            if isChartRoute {
                                Text(String(index + 1)).font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(isCurrent ? MusicXTheme.blue : (index < 3 ? MusicXTheme.blue : MusicXTheme.muted)).frame(width: 22)
                            }
                            songArtwork(song, index: index, isCurrent: isCurrent)
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(song.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(isCurrent ? MusicXTheme.blue : .white).lineLimit(1)
                                Text(song.artist).font(.system(size: 12)).foregroundStyle(isCurrent ? .white.opacity(0.78) : MusicXTheme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if isCurrent && isPlaying {
                                Image(systemName: "waveform").font(.system(size: 13, weight: .semibold)).foregroundStyle(MusicXTheme.blue)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(MusicXTheme.muted.opacity(0.7))
                        }
                         .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        .background(isCurrent ? MusicXTheme.blue.opacity(0.12) : Color.white.opacity(0.018), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isCurrent ? MusicXTheme.blue.opacity(0.30) : Color.white.opacity(0.045), lineWidth: 1))
                        .overlay(alignment: .leading) {
                            if isCurrent { Capsule().fill(MusicXTheme.blue).frame(width: 3).padding(.vertical, 8) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    @MainActor
    private func loadPlaylistCards(forMood: Bool, onlyCategory: String? = nil) async {
        let items: [(String, [String])] = forMood
            ? [
                ("开心愉悦", ["开心", "快乐", "愉悦", "好心情"]),
                ("温柔治愈", ["治愈", "温柔", "疗愈", "舒缓"]),
                ("放松舒缓", ["放松", "轻松", "休闲", "Relax"]),
                ("安静专注", ["专注", "学习", "工作", "纯音乐"]),
                ("释放情绪", ["摇滚", "热血", "燃", "释放情绪"]),
                ("夜晚助眠", ["助眠", "睡眠", "晚安", "轻音乐"])
            ]
            : [
                ("本周编辑精选", ["编辑精选", "本周精选", "编辑推荐"]),
                ("华语流行精选", ["华语流行", "华语"]),
                ("经典金曲精选", ["经典金曲", "经典", "怀旧"]),
                ("独立音乐精选", ["独立音乐", "独立", "Indie"]),
                ("影视原声精选", ["影视原声", "影视", "OST"]),
                ("通勤驾驶精选", ["通勤", "开车", "驾车", "驾驶"])
            ]

        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        }

        var updated = playlistCardResults
        var assignedPlaylistIDs = Set(updated.values.map { $0.id })
        for (category, keywords) in items where updated[category] == nil && (onlyCategory == nil || category == onlyCategory) {
            guard !Task.isCancelled else { return }
            var selected: MusicPlaylist?
            var lastError: String?
            for keyword in keywords {
                guard !Task.isCancelled else { return }
                do {
                    let results = try await service.searchPlaylists(keyword: keyword, count: 30)
                    guard !Task.isCancelled else { return }
                    let token = normalized(keyword)
                    let match = results
                        .filter { !assignedPlaylistIDs.contains($0.id) }
                        .map { playlist -> (MusicPlaylist, Int) in
                            let name = normalized(playlist.name)
                            let score = name == token ? 100
                                : (name.contains(token) ? 80 : 0)
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
        if case .featuredPick = route {
            songs = []
            isLoading = true
            errorMessage = nil
            await loadPlaylistCards(forMood: false, onlyCategory: "本周编辑精选")
            guard !Task.isCancelled else { isLoading = false; return }
            if let playlist = playlistCardResults["本周编辑精选"] {
                onOpenPlaylist(playlist)
            } else {
                errorMessage = "暂未匹配到真实的本周编辑精选歌单，请稍后重试"
            }
            isLoading = false
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
        defer { isLoading = false }
        do {
            var playlistLoadError: String?
            let result: [MusicSong]
            switch route {
            case .charts, .chart:
                result = []
            case .newReleases:
                result = try await service.toplist("新歌榜", count: 50)
            case .album(let albumTitle, let albumArtist):
                result = await searchAlbumTracks(title: albumTitle, artist: albumArtist)
            case .featuredPick:
                result = []
            case .playlist(let name):
                result = await searchEditorialTracks(name: name)
            case .playlistByID(let playlist):
                if playlist.source == .qq {
                    do {
                        result = try await service.playlistTracks(playlistID: playlist.sourceID, count: 50)
                    } catch {
                        if Task.isCancelled { return }
                        playlistLoadError = "真实歌单曲目加载失败：\(error.localizedDescription)"
                        result = []
                        MusicSourceDiagnostics.shared.record(
                            event: "playlist-tracks", source: playlist.source.rawValue,
                            provider: "qq-playlist-detail", duration: 0,
                            result: "failed", detail: "\(playlist.name): \(error.localizedDescription)"
                        )
                    }
                } else {
                    playlistLoadError = "暂不支持加载该音源的真实歌单曲目。"
                    result = []
                }
            default:
                result = try await service.search(keyword: query, source: .netease, count: 30)
            }
            guard !Task.isCancelled else { return }
            songs = result
            if !songs.isEmpty {
                onQueueChanged(songs)
            }
            if songs.isEmpty {
                errorMessage = playlistLoadError ?? "音源没有返回匹配的歌曲，请稍后重试"
            }
        } catch {
            if Task.isCancelled { return }
            errorMessage = error.localizedDescription
        }
    }

    private func searchEditorialTracks(name: String) async -> [MusicSong] {
        let normalizedName = name.lowercased()
        var keywords = [name]
        if name.contains("|") {
            keywords.append(contentsOf: name.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        if normalizedName.contains("indie") || name.contains("独立") {
            keywords.append(contentsOf: ["独立音乐", "Indie", "独立乐队"])
        }
        if name.contains("通勤") || name.contains("驾驶") || name.contains("开车") {
            keywords.append(contentsOf: ["通勤", "驾驶音乐", "开车音乐"])
        }
        if name.contains("治愈") { keywords.append(contentsOf: ["温柔治愈", "治愈系歌曲", "温柔华语"]) }
        if name.contains("放松") || name.contains("舒缓") { keywords.append(contentsOf: ["放松音乐", "轻音乐", "舒缓歌曲"]) }
        if name.contains("助眠") || name.contains("夜晚") { keywords.append(contentsOf: ["助眠音乐", "纯音乐", "轻音乐"]) }
        if name.contains("经典") { keywords.append(contentsOf: ["经典老歌", "华语金曲"]) }
        if name.contains("影视") { keywords.append(contentsOf: ["影视原声", "电影原声", "电视剧原声"]) }
        if name.contains("华语") { keywords.append(contentsOf: ["华语流行", "华语歌曲"]) }
        var seen = Set<String>()
        var collected: [MusicSong] = []
        for keyword in keywords where !keyword.isEmpty {
            for source in [MusicSource.netease, .qq, .kuwo, .kugou, .migu] {
                guard !Task.isCancelled else { return collected }
                do {
                    let found = try await service.search(keyword: keyword, source: source, count: 20)
                    for song in found {
                        let key = song.title.lowercased().filter { $0.isLetter || $0.isNumber }
                            + "|" + song.artist.lowercased().filter { $0.isLetter || $0.isNumber }
                        if seen.insert(key).inserted { collected.append(song) }
                    }
                } catch {
                    if Task.isCancelled { return collected }
                    MusicSourceDiagnostics.shared.record(event: "editorial-search", source: source.rawValue,
                        provider: "gdstudio-search", duration: 0, result: "failed",
                        detail: "\(keyword): \(error.localizedDescription)")
                }
            }
            if collected.count >= 30 { break }
        }
        return Array(collected.prefix(50))
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
                let rows = try await service.search(keyword: title, source: source, count: 50, albumOnly: true)
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
                    let rows = try await service.search(keyword: "\(title) \(artist)", source: source, count: 50)
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
            onQueueChanged(cached)
            return
        }
        isLoading = true
        errorMessage = nil
        defer {
            if chartLoadToken == requestToken { isLoading = false }
        }
        do {
            let result = try await service.toplist(name, count: 50)
            guard !Task.isCancelled, chartLoadToken == requestToken else { return }
            if !result.isEmpty {
                chartSongCache[name] = result
                songs = result
                errorMessage = nil
                onQueueChanged(result)
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
            onQueueChanged(cached)
            return
        }
        if showInitialLoading { isLoading = true }
        errorMessage = nil
        defer {
            if showInitialLoading, chartLoadToken == requestToken { isLoading = false }
        }
        do {
            let result = try await service.toplist(name, count: 50)
            guard !Task.isCancelled, chartLoadToken == requestToken else { return }
            if !result.isEmpty { chartSongCache[name] = result }
            songs = result
            if !result.isEmpty { onQueueChanged(result) }
            if result.isEmpty { errorMessage = "音源没有返回匹配的歌曲，请稍后重试" }
        } catch {
            guard !Task.isCancelled, chartLoadToken == requestToken else { return }
            errorMessage = error.localizedDescription
        }
    }
}
