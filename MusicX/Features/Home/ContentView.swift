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

private struct DemoSong: Identifiable, Equatable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let tint: Color
}

private enum LibraryFilter: String, CaseIterable {
    case favorites = "收藏"
    case recent = "最近播放"
    case downloads = "下载"
}

struct ContentView: View {
    @State private var selectedTab: MainTab = .home
    @State private var searchText = ""
    @State private var libraryFilter: LibraryFilter = .favorites
    @State private var currentSong: DemoSong?
    @State private var isPlaying = false
    @State private var favorites: Set<Int> = [1, 3]

    private let songs: [DemoSong] = [
        DemoSong(id: 1, title: "夜色之间", artist: "演示歌手 · Demo", album: "蓝色时刻", tint: Color(red: 0.22, green: 0.38, blue: 0.56)),
        DemoSong(id: 2, title: "慢慢喜欢你", artist: "演示歌手 · Demo", album: "日落以后", tint: Color(red: 0.48, green: 0.29, blue: 0.35)),
        DemoSong(id: 3, title: "远方来信", artist: "演示歌手 · Demo", album: "留白", tint: Color(red: 0.29, green: 0.43, blue: 0.38)),
        DemoSong(id: 4, title: "蓝色时刻", artist: "演示歌手 · Demo", album: "蓝色时刻", tint: Color(red: 0.25, green: 0.34, blue: 0.53)),
        DemoSong(id: 5, title: "日落以后", artist: "演示歌手 · Demo", album: "日落以后", tint: Color(red: 0.53, green: 0.31, blue: 0.22))
    ]

    private var filteredSongs: [DemoSong] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return songs }
        return songs.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) || $0.album.localizedCaseInsensitiveContains(query) }
    }

    private var librarySongs: [DemoSong] {
        switch libraryFilter {
        case .favorites: songs.filter { favorites.contains($0.id) }
        case .recent: currentSong.map { [$0] } ?? []
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                miniPlayer
                tabBar
            }
            .background(.ultraThinMaterial)
        }
        .preferredColorScheme(.dark)
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
                recommendationCard(title: "每日推荐", subtitle: "发现今天的好音乐", colors: [Color(red: 0.18, green: 0.38, blue: 0.61), Color(red: 0.13, green: 0.18, blue: 0.35)], icon: "sparkles")
                recommendationCard(title: "精选歌单", subtitle: "按心情聆听", colors: [Color(red: 0.39, green: 0.25, blue: 0.48), Color(red: 0.18, green: 0.15, blue: 0.31)], icon: "square.stack.fill")
            }
        }.padding(.horizontal, 20)
    }

    private func recommendationCard(title: String, subtitle: String, colors: [Color], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 12)
            Text(title).font(.system(size: 19, weight: .bold))
            Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
    }

    private var newMusicSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("新歌速递", detail: "演示数据")
            ForEach(songs.prefix(3)) { song in
                songRow(song)
            }
        }.padding(.horizontal, 20)
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("热门专辑", detail: "演示内容")
            HStack(spacing: 14) {
                albumTile(title: "蓝色时刻", artist: "演示专辑", color: Color(red: 0.20, green: 0.34, blue: 0.53))
                albumTile(title: "日落以后", artist: "演示专辑", color: Color(red: 0.53, green: 0.31, blue: 0.22))
                albumTile(title: "留白", artist: "演示专辑", color: Color(red: 0.34, green: 0.31, blue: 0.49))
            }
        }.padding(.horizontal, 20)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("排行榜", detail: "接入音源后显示")
            HStack(spacing: 12) {
                chartTile("热歌榜", subtitle: "热门歌曲", icon: "flame.fill", color: .orange)
                chartTile("新歌榜", subtitle: "最新发行", icon: "sparkles", color: MusicXTheme.blue)
                chartTile("飙升榜", subtitle: "正在上升", icon: "chart.line.uptrend.xyaxis", color: .mint)
            }
        }.padding(.horizontal, 20)
    }

    private var searchPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader("搜索", subtitle: "搜索歌曲、歌手或专辑")
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(MusicXTheme.muted)
                TextField("输入歌曲、歌手或专辑", text: $searchText)
                    .font(.system(size: 16))
                    .tint(MusicXTheme.blue)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
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
                    Spacer()
                    Text("\(filteredSongs.count) 首").font(.system(size: 13)).foregroundStyle(MusicXTheme.muted)
                }
                if filteredSongs.isEmpty {
                    emptyState(icon: "music.note.list", title: "没有找到相关内容", detail: "试试其他关键词")
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 17) {
                            ForEach(filteredSongs) { song in songRow(song) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.top, 28)
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

    private func songRow(_ song: DemoSong, number: String? = nil) -> some View {
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
                Image(systemName: currentSong?.id == song.id && isPlaying ? "pause.circle.fill" : "play.circle")
                    .font(.system(size: 25)).foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private func albumTile(title: String, artist: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [color, color.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .aspectRatio(1, contentMode: .fit)
                .overlay(Image(systemName: "waveform").font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.75)))
            Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text(artist).font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartTile(_ title: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.system(size: 21)).foregroundStyle(color)
            Text(title).font(.system(size: 15, weight: .bold))
            Text(subtitle).font(.system(size: 10)).foregroundStyle(MusicXTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12).background(MusicXTheme.surface, in: RoundedRectangle(cornerRadius: 16))
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
            Button { if currentSong != nil { isPlaying.toggle() } } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
            }
            .disabled(currentSong == nil)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(MusicXTheme.surface.opacity(0.96))
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

    private func select(_ song: DemoSong) {
        if currentSong?.id == song.id {
            isPlaying.toggle()
        } else {
            currentSong = song
            isPlaying = true
        }
    }

    private func toggleFavorite(_ song: DemoSong) {
        if favorites.contains(song.id) { favorites.remove(song.id) }
        else { favorites.insert(song.id) }
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
