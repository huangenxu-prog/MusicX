import SwiftUI

enum MusicDiscoveryRoute: Identifiable {
    case daily, playlists, featuredPlaylists, albums, charts, newReleases
    case chart(String)
    case playlist(String)
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
        case .playlist(let name): "playlist-\(name)"
        case .album(let title, let artist): "album-\(title)-\(artist)"
        }
    }
}

struct MusicDiscoveryPage: View {
    @Environment(\.dismiss) private var dismiss

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
    let onOpenPlaylist: (String) -> Void
    let onOpenAlbum: (String, String) -> Void
    let onSelectChart: (String) -> Void

    @State private var songs: [MusicSong] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedChartOverride: String?
    @State private var chartSongCache: [String: [MusicSong]] = [:]
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
        dismiss()
    }

    private func playlistSubtitle(for name: String) -> String {
        let moodNames: Set<String> = ["开心愉悦", "温柔治愈", "放松舒缓", "安静专注", "释放情绪", "夜晚助眠"]
        return moodNames.contains(name) ? "心情歌单" : "精选歌单"
    }

    private var title: String {
        switch route {
        case .daily: "每日推荐"
        case .playlists: "心情歌单"
        case .featuredPlaylists: "精选歌单"
        case .albums: "热门专辑"
        case .charts, .chart: "排行榜"
        case .newReleases: "新歌速递"
        case .playlist(let name): name
        case .album(let title, _): title
        }
    }
    private var query: String {
        switch route {
        case .daily: "陈奕迅"
        case .playlists: "华语歌手"
        case .featuredPlaylists, .albums: ""
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
                    case .albums: albumsIntro
                    case .charts, .chart: chartIntro
                    case .newReleases: newReleasesHeader
                    case .playlist(let name): detailBanner(name, subtitle: playlistSubtitle(for: name))
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
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 36)
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
    }

    private var topBar: some View {
        HStack {
            Button(action: closePage) {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                    .frame(width: 48, height: 46, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).zIndex(10)
            Spacer()
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 42)
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
        VStack(alignment: .leading, spacing: 7) {
            Text("按心情聆听").font(.system(size: 27, weight: .bold, design: .rounded))
            Text("从在线曲库中发现适合此刻的音乐").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.66))
        }.padding(.top, 4)
    }

    private var featuredPlaylistsIntro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("编辑精选").font(.system(size: 27, weight: .bold, design: .rounded))
            Text("从不同风格与场景中，发现值得收藏的歌单").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.66))
        }.padding(.top, 4)
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
                    Text("为你精选 · 在线曲目").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.48)).padding(.top, 5)
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
            Text("\(songs.count) 首 · 在线曲目").font(.system(size: 12, weight: .medium)).foregroundStyle(MusicXTheme.muted)
        }
    }

    private func miniPlayerBar(song: MusicSong?) -> some View {
        HStack(spacing: 9) {
            Button(action: onOpenPlayer) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(LinearGradient(colors: [MusicXTheme.blue, Color(red: 0.20, green: 0.16, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        if let url = song?.artworkURL {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { Image(systemName: "music.note").foregroundStyle(.white) }
                            }.clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        } else { Image(systemName: "music.note").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white) }
                    }.frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(song?.title ?? "尚未播放").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(song?.artist ?? "选择一首歌曲开始聆听").font(.system(size: 11)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: onPrevious) { Image(systemName: "backward.end.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.92)).frame(width: 28, height: 44) }.buttonStyle(.plain).disabled(song == nil)
            Button(action: onTogglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(.white.opacity(0.22), in: Circle()).overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 1))
            }.buttonStyle(.plain).disabled(song == nil)
            Button(action: onNext) { Image(systemName: "forward.end.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.92)).frame(width: 28, height: 44) }.buttonStyle(.plain).disabled(song == nil)
            Button(action: onOpenQueue) { Image(systemName: "list.bullet").font(.system(size: 19, weight: .semibold)).foregroundStyle(.white.opacity(0.92)).frame(width: 28, height: 44) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 13).frame(height: 76)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.10, green: 0.12, blue: 0.27).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.40, green: 0.31, blue: 0.66).opacity(0.34), Color(red: 0.08, green: 0.11, blue: 0.25).opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6).padding(.horizontal, 12)
    }

    private var progressFraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(currentTime / duration, 0), 1))
    }

    private var playlistGrid: some View {
        let items: [(String, String, String)] = [
            ("开心愉悦", "明亮轻快，让好心情延续", "category_chinese_pop"),
            ("温柔治愈", "温暖柔和，给情绪一点空间", "playlist_relax"),
            ("放松舒缓", "舒缓节奏，放松身心", "category_light"),
            ("安静专注", "纯音乐与轻旋律，适合专注", "category_instrumental"),
            ("释放情绪", "用更有力量的节奏释放压力", "category_rock"),
            ("夜晚助眠", "安静氛围，适合睡前聆听", "playlist_night")
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
            ForEach(items, id: \.0) { item in
                Button { onOpenPlaylist(item.0) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(item.2).resizable().scaledToFill()
                            .frame(height: 126).frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
                        Text(item.0).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(item.1).font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
    }

    private var featuredPlaylistGrid: some View {
        let items: [(String, String, String)] = [
            ("本周编辑精选", "近期值得收藏的好歌", "featured_playlist"),
            ("华语流行精选", "熟悉的声音与新鲜旋律", "category_chinese_pop"),
            ("经典金曲精选", "历久弥新的经典作品", "category_classic"),
            ("独立音乐精选", "发现不一样的音乐表达", "category_singers"),
            ("影视原声精选", "从电影与剧集中寻找旋律", "category_instrumental"),
            ("通勤驾驶精选", "陪伴每一段路程", "playlist_drive")
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(items, id: \.0) { item in
                Button { onOpenPlaylist(item.0) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(item.2).resizable().scaledToFill()
                            .frame(height: 118).frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.8))
                        Text(item.0).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(item.1).font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
    }

    private var albumGrid: some View {
        let items: [(String, String, String)] = [
            ("DUO", "陈奕迅", "album_01"),
            ("最伟大的作品", "周杰伦", "album_02"),
            ("宇宙的有趣", "告五人", "album_03"),
            ("A-Lin", "LINK", "album_04"),
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

    private func songArtwork(_ song: MusicSong, index: Int, isCurrent: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: index.isMultiple(of: 2)
                    ? [Color(red: 0.20, green: 0.42, blue: 0.68), Color(red: 0.10, green: 0.16, blue: 0.30)]
                    : [Color(red: 0.40, green: 0.25, blue: 0.49), Color(red: 0.17, green: 0.14, blue: 0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            if let url = song.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: isCurrent ? "waveform" : "music.note").font(.system(size: 20, weight: .medium)).foregroundStyle(.white.opacity(0.78)) }
                }
            } else {
                Image(systemName: isCurrent ? "waveform" : "music.note").font(.system(size: 20, weight: .medium)).foregroundStyle(.white.opacity(0.78))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isCurrent && isPlaying {
                Image(systemName: "waveform").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(5).background(MusicXTheme.blue, in: Circle()).padding(4)
            }
        }
        .clipped()
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
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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
    private func loadSongs() async {
        if case .playlists = route { songs = []; return }
        if case .featuredPlaylists = route { songs = []; return }
        if case .albums = route { songs = []; return }
        if isChartRoute { await loadChart(selectedChart, showInitialLoading: true); return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: [MusicSong]
            switch route {
            case .charts, .chart:
                result = []
            case .newReleases:
                result = try await service.toplist("新歌榜", count: 50)
            case .album:
                result = try await service.search(keyword: query, source: .netease, count: 50, albumOnly: true)
            case .playlist:
                result = try await service.playlistTracks(keyword: query, count: 50)
            default:
                result = try await service.search(keyword: query, source: .netease, count: 30)
            }
            guard !Task.isCancelled else { return }
            songs = result
            onQueueChanged(songs)
            if songs.isEmpty { errorMessage = "音源没有返回匹配的歌曲，请稍后重试" }
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func selectChart(_ name: String) async {
        guard name != selectedChart else { return }
        selectedChartOverride = name
        if let cached = chartSongCache[name] {
            songs = cached
            errorMessage = cached.isEmpty ? "音源没有返回匹配的歌曲，请稍后重试" : nil
            onQueueChanged(cached)
            return
        }
        do {
            let result = try await service.toplist(name, count: 50)
            chartSongCache[name] = result
            songs = result
            errorMessage = result.isEmpty ? "音源没有返回匹配的歌曲，请稍后重试" : nil
            onQueueChanged(result)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func loadChart(_ name: String, showInitialLoading: Bool) async {
        if let cached = chartSongCache[name] {
            songs = cached
            onQueueChanged(cached)
            return
        }
        if showInitialLoading { isLoading = true }
        errorMessage = nil
        defer { if showInitialLoading { isLoading = false } }
        do {
            let result = try await service.toplist(name, count: 50)
            guard !Task.isCancelled else { return }
            chartSongCache[name] = result
            songs = result
            onQueueChanged(result)
            if result.isEmpty { errorMessage = "音源没有返回匹配的歌曲，请稍后重试" }
        } catch { errorMessage = error.localizedDescription }
    }
}
