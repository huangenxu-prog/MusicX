import SwiftUI

enum MusicDiscoveryRoute: Identifiable {
    case daily, playlists, charts, newReleases
    case chart(String)
    case playlist(String)
    case album(title: String, artist: String)
    var id: String {
        switch self {
        case .daily: "daily"
        case .playlists: "playlists"
        case .charts: "charts"
        case .newReleases: "new-releases"
        case .chart(let name): "chart-\(name)"
        case .playlist(let name): "playlist-\(name)"
        case .album(let title, let artist): "album-\(title)-\(artist)"
        }
    }
}

struct MusicDiscoveryPage: View {
    let route: MusicDiscoveryRoute
    let onClose: () -> Void
    let onPlay: (MusicSong) -> Void
    let currentSong: MusicSong?
    let isPlaying: Bool
    let onTogglePlayback: () -> Void
    let onOpenPlayer: () -> Void
    let onQueueChanged: ([MusicSong]) -> Void
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onOpenPlaylist: (String) -> Void
    let onSelectChart: (String) -> Void

    @State private var songs: [MusicSong] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private var selectedChart: String {
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

    private var title: String {
        switch route {
        case .daily: "每日推荐"
        case .playlists: "精选歌单"
        case .charts, .chart: "排行榜"
        case .newReleases: "新歌速递"
        case .playlist(let name): name
        case .album(let title, _): title
        }
    }
    private var query: String {
        switch route {
        case .daily: "陈奕迅"
        case .playlists: "周杰伦"
        case .charts: "陈奕迅"
        case .chart(let name): name == "新歌榜" ? "新歌" : name == "飙升榜" ? "飙升" : "热歌"
        case .newReleases: "新歌"
        case .playlist(let name):
            switch name {
            case "轻音乐": "轻音乐"
            case "华语流行": "华语流行"
            case "午后放松": "午后放松"
            case "深夜独白": "深夜"
            case "车载必听": "车载"
            default: name
            }
        case .album(let title, let artist): "\(title) \(artist)"
        }
    }

    var body: some View {
        ZStack {
            ZStack {
                MusicXTheme.background
                RadialGradient(colors: [MusicXTheme.blue.opacity(0.16), .clear], center: .top, startRadius: 12, endRadius: 520)
                RadialGradient(colors: [Color.purple.opacity(0.08), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 420)
            }.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    topBar
                    switch route {
                    case .daily: dailyHeader
                    case .playlists: playlistIntro
                    case .charts, .chart: chartIntro
                    case .newReleases: newReleasesHeader
                    case .playlist(let name): detailBanner(name, subtitle: "精选歌单")
                    case .album(let title, let artist): albumBanner(title: title, artist: artist)
                    }
                    if case .playlists = route {
                        playlistGrid
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
        .task(id: route.id) { await loadSongs() }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42, alignment: .leading).contentShape(Rectangle())
            }
            Spacer()
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold))
                .frame(width: 42, alignment: .trailing).foregroundStyle(.white.opacity(0.75))
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
            Text("网易云音乐 · 实时新歌榜").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
        }
    }

    private var playlistIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按心情聆听").font(.system(size: 28, weight: .bold))
            Text("从在线曲库中发现适合此刻的音乐").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
        }
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
        case "华语流行": "category_chinese_pop"
        case "经典老歌": "category_classic"
        case "轻音乐": "category_light"
        case "纯音乐": "category_instrumental"
        case "摇滚": "category_rock"
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
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                Button(action: onOpenPlayer) {
                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(LinearGradient(colors: [MusicXTheme.blue, MusicXTheme.blue.opacity(0.42)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                            .overlay(Image(systemName: song == nil ? "music.note" : "waveform").foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(song?.title ?? "尚未播放").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(song?.artist ?? "选择一首歌曲开始聆听").font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: onTogglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 42, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(song == nil)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule().fill(MusicXTheme.blue).frame(width: geometry.size.width * progressFraction)
                }
            }
            .frame(height: 2)
        }
        .padding(.horizontal, 16).padding(.top, 7).padding(.bottom, 5)
        .background(MusicXTheme.background.opacity(0.98))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5) }
    }

    private var progressFraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(currentTime / duration, 0), 1))
    }

    private var playlistGrid: some View {
        let items: [(String, String, [Color], String)] = [
            ("华语流行", "热门华语歌曲", [Color(red: 0.20, green: 0.42, blue: 0.68), Color(red: 0.10, green: 0.16, blue: 0.30)], "category_chinese_pop"),
            ("轻音乐", "放松与专注", [Color(red: 0.40, green: 0.25, blue: 0.49), Color(red: 0.17, green: 0.14, blue: 0.30)], "category_light"),
            ("经典老歌", "熟悉的旋律", [Color(red: 0.48, green: 0.28, blue: 0.25), Color(red: 0.20, green: 0.14, blue: 0.17)], "category_classic"),
            ("纯音乐", "安静聆听", [Color(red: 0.16, green: 0.39, blue: 0.38), Color(red: 0.08, green: 0.20, blue: 0.23)], "category_instrumental"),
            ("摇滚", "节奏与力量", [Color(red: 0.43, green: 0.22, blue: 0.27), Color(red: 0.19, green: 0.13, blue: 0.22)], "category_rock"),
            ("周杰伦", "歌手精选", [Color(red: 0.27, green: 0.32, blue: 0.53), Color(red: 0.15, green: 0.17, blue: 0.30)], "category_singers")
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(items, id: \.0) { item in
                Button { onOpenPlaylist(item.0) } label: {
                    GeometryReader { geometry in
                        ZStack(alignment: .bottomLeading) {
                            Image(item.3)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                            LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.0).font(.system(size: 17, weight: .bold))
                                Text(item.1).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.82))
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
                    }
                    .frame(height: 148)
                }.buttonStyle(.plain)
            }
        }
    }

    private var chartTabs: some View {
        HStack(spacing: 8) {
            ForEach(["热歌榜", "新歌榜", "飙升榜"], id: \.self) { name in
                Button { onSelectChart(name) } label: {
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        if case .playlists = route {
            songs = []
            return
        }
        do {
            let result: [MusicSong]
            switch route {
            case .charts:
                result = try await service.toplist("热歌榜", count: 50)
            case .chart(let name):
                result = try await service.toplist(name, count: 50)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
