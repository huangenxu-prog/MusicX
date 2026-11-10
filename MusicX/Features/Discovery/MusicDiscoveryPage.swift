import SwiftUI

enum MusicDiscoveryRoute: Identifiable {
    case daily, playlists, charts
    case playlist(String)
    case album(MusicSong)
    var id: String {
        switch self {
        case .daily: "daily"
        case .playlists: "playlists"
        case .charts: "charts"
        case .playlist(let name): "playlist-\(name)"
        case .album(let song): "album-\(song.id)"
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

    @State private var songs: [MusicSong] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedChart = "热歌榜"
    private let service = GDStudioMusicSearchService()

    private var title: String {
        switch route {
        case .daily: "每日推荐"
        case .playlists: "精选歌单"
        case .charts: "排行榜"
        case .playlist(let name): name
        case .album(let song): song.album?.isEmpty == false ? song.album! : song.title
        }
    }
    private var query: String {
        switch route {
        case .daily: "陈奕迅"
        case .playlists: "周杰伦"
        case .charts:
            selectedChart == "新歌榜" ? "周杰伦" : selectedChart == "飙升榜" ? "薛之谦" : "陈奕迅"
        case .playlist(let name):
            name == "轻音乐" ? "纯音乐" : name == "华语流行" ? "周杰伦" : name
        case .album(let song): song.album?.isEmpty == false ? song.album! : song.title
        }
    }

    var body: some View {
        ZStack {
            MusicXTheme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    topBar
                    switch route {
                    case .daily: dailyHeader
                    case .playlists: playlistIntro
                    case .charts: chartIntro
                    case .playlist(let name): detailBanner(name, subtitle: "精选歌单")
                    case .album(let song): albumBanner(song)
                    }
                    if case .playlists = route {
                        playlistGrid
                    } else {
                        if case .charts = route { chartTabs }
                        if case .album = route { albumNote }
                        trackList
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            miniPlayerBar(song: currentSong)
        }
        .task(id: query) { await loadSongs() }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) { Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 40, height: 42, alignment: .leading) }
            Spacer()
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer()
            Image(systemName: "ellipsis").frame(width: 40, alignment: .trailing).foregroundStyle(.white.opacity(0.8))
        }.foregroundStyle(.white)
    }

    private var dailyHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(red: 0.20, green: 0.42, blue: 0.68), Color(red: 0.10, green: 0.16, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "sun.horizon.fill").font(.system(size: 110, weight: .ultraLight)).foregroundStyle(.white.opacity(0.16)).frame(maxWidth: .infinity, alignment: .trailing).padding(20)
                VStack(alignment: .leading, spacing: 7) {
                    Text("为你精选").font(.system(size: 27, weight: .bold))
                    Text("根据在线曲库整理 · 每日更新").font(.system(size: 13)).foregroundStyle(.white.opacity(0.72))
                }.padding(22)
            }.frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 24))
            playAllBar
        }
    }

    private var playlistIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按心情聆听").font(.system(size: 28, weight: .bold))
            Text("从在线曲库中发现适合此刻的音乐").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
        }
    }

    private var chartIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("排行榜").font(.system(size: 28, weight: .bold))
            Text("在线曲目 · 排序以音源返回结果为准").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
        }
    }

    private func detailBanner(_ name: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            artwork(title: name, subtitle: subtitle, colors: [Color(red: 0.40, green: 0.25, blue: 0.49), Color(red: 0.17, green: 0.14, blue: 0.30)], height: 190)
            playAllBar
        }
    }

    private func albumBanner(_ song: MusicSong) -> some View {
        HStack(spacing: 18) {
            artwork(title: song.album ?? song.title, subtitle: song.artist, colors: [Color(red: 0.20, green: 0.42, blue: 0.68), Color(red: 0.10, green: 0.16, blue: 0.30)], height: 176).frame(width: 176)
            VStack(alignment: .leading, spacing: 8) {
                Text(song.album ?? song.title).font(.system(size: 22, weight: .bold))
                Text(song.artist).font(.system(size: 14)).foregroundStyle(MusicXTheme.muted)
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
                Label("播放全部", systemImage: "play.fill").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 18).padding(.vertical, 11).background(MusicXTheme.blue, in: Capsule())
            }.buttonStyle(.plain)
            Spacer()
            Text("\(songs.count) 首 · 在线曲目").font(.system(size: 12)).foregroundStyle(MusicXTheme.muted)
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
        let items: [(String, String, [Color])] = [
            ("华语流行", "热门华语歌曲", [Color(red: 0.20, green: 0.42, blue: 0.68), Color(red: 0.10, green: 0.16, blue: 0.30)]),
            ("轻音乐", "放松与专注", [Color(red: 0.40, green: 0.25, blue: 0.49), Color(red: 0.17, green: 0.14, blue: 0.30)]),
            ("经典老歌", "熟悉的旋律", [Color(red: 0.48, green: 0.28, blue: 0.25), Color(red: 0.20, green: 0.14, blue: 0.17)]),
            ("纯音乐", "安静聆听", [Color(red: 0.16, green: 0.39, blue: 0.38), Color(red: 0.08, green: 0.20, blue: 0.23)]),
            ("摇滚", "节奏与力量", [Color(red: 0.43, green: 0.22, blue: 0.27), Color(red: 0.19, green: 0.13, blue: 0.22)]),
            ("周杰伦", "歌手精选", [Color(red: 0.27, green: 0.32, blue: 0.53), Color(red: 0.15, green: 0.17, blue: 0.30)])
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(items, id: \.0) { item in
                Button { onOpenPlaylist(item.0) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "music.note.list").font(.system(size: 25))
                        Spacer(minLength: 20)
                        Text(item.0).font(.system(size: 17, weight: .bold))
                        Text(item.1).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    }.foregroundStyle(.white).padding(16).frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
                        .background(LinearGradient(colors: item.2, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
            }
        }
    }

    private var chartTabs: some View {
        HStack(spacing: 8) {
            ForEach(["热歌榜", "新歌榜", "飙升榜"], id: \.self) { name in
                Button { selectedChart = name; songs = [] } label: {
                    Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(selectedChart == name ? .white : MusicXTheme.muted)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(selectedChart == name ? MusicXTheme.blue : MusicXTheme.surface, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    private var albumNote: some View {
        Text("曲目根据在线音源搜索结果整理，具体收录信息以音源返回为准。")
            .font(.system(size: 12)).foregroundStyle(MusicXTheme.muted)
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
                            if case .charts = route {
                                Text(String(index + 1)).font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(isCurrent ? MusicXTheme.blue : (index < 3 ? MusicXTheme.blue : MusicXTheme.muted)).frame(width: 22)
                            }
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(colors: index.isMultiple(of: 2) ? [Color(red: 0.20, green: 0.42, blue: 0.68), Color(red: 0.10, green: 0.16, blue: 0.30)] : [Color(red: 0.40, green: 0.25, blue: 0.49), Color(red: 0.17, green: 0.14, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 48, height: 48)
                                .overlay(Image(systemName: isCurrent && isPlaying ? "waveform" : "music.note").foregroundStyle(isCurrent ? MusicXTheme.blue : .white.opacity(0.8)))
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
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(isCurrent ? MusicXTheme.blue.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 14))
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
        do {
            let source: MusicSource
            if case .album(let albumSong) = route { source = albumSong.source } else { source = .netease }
            let result = try await service.search(keyword: query, source: source, count: 30)
            guard !Task.isCancelled else { return }
            if case .album(let albumSong) = route, let album = albumSong.album, !album.isEmpty {
                songs = result.filter { $0.album?.localizedCaseInsensitiveContains(album) ?? false }
            } else { songs = result }
            onQueueChanged(songs)
            if songs.isEmpty { errorMessage = "音源没有返回匹配的歌曲，请稍后重试" }
        } catch { errorMessage = error.localizedDescription }
    }
}
