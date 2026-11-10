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

struct ContentView: View {
    @State private var selectedTab: MainTab = .home
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            MusicXTheme.background.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .home: homePage
                case .search: placeholderPage(title: "搜索", subtitle: "寻找你喜欢的音乐", symbol: "magnifyingglass")
                case .library: placeholderPage(title: "音乐库", subtitle: "收藏与最近播放都在这里", symbol: "square.stack")
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
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.25, blue: 0.43), Color(red: 0.08, green: 0.12, blue: 0.23), MusicXTheme.background],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            RadialGradient(colors: [MusicXTheme.blue.opacity(0.35), .clear], center: .topTrailing, startRadius: 5, endRadius: 260)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button {} label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.09), in: Circle())
                    }
                }
                Spacer()
                Text("发现音乐")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("好音乐，总在这里")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 30)
        }
        .frame(height: 285)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, MusicXTheme.background.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .frame(height: 48)
                .allowsHitTesting(false)
        }
    }

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("为你推荐", detail: "每日精选")
            HStack(spacing: 14) {
                recommendationCard(title: "每日推荐", subtitle: "发现今天的好音乐", colors: [.init(red: 0.18, green: 0.38, blue: 0.61), .init(red: 0.13, green: 0.18, blue: 0.35)], icon: "sparkles")
                recommendationCard(title: "精选歌单", subtitle: "按心情聆听", colors: [.init(red: 0.39, green: 0.25, blue: 0.48), .init(red: 0.18, green: 0.15, blue: 0.31)], icon: "square.stack.fill")
            }
        }
        .padding(.horizontal, 20)
    }

    private func recommendationCard(title: String, subtitle: String, colors: [Color], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 12)
            Text(title).font(.system(size: 19, weight: .bold))
            Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
    }

    private var newMusicSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("新歌速递", detail: "全部")
            songRow(number: "01", title: "夜色之间", artist: "精选推荐", color: Color(red: 0.22, green: 0.38, blue: 0.56))
            songRow(number: "02", title: "慢慢喜欢你", artist: "每日新歌", color: Color(red: 0.48, green: 0.29, blue: 0.35))
            songRow(number: "03", title: "远方来信", artist: "本周上新", color: Color(red: 0.29, green: 0.43, blue: 0.38))
        }
        .padding(.horizontal, 20)
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("热门专辑", detail: "更多")
            HStack(spacing: 14) {
                albumTile(title: "蓝色时刻", artist: "精选专辑", color: Color(red: 0.20, green: 0.34, blue: 0.53))
                albumTile(title: "日落以后", artist: "独立音乐", color: Color(red: 0.53, green: 0.31, blue: 0.22))
                albumTile(title: "留白", artist: "氛围音乐", color: Color(red: 0.34, green: 0.31, blue: 0.49))
            }
        }
        .padding(.horizontal, 20)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("排行榜", detail: "来自当前音源")
            HStack(spacing: 12) {
                chartTile("热歌榜", subtitle: "热门歌曲", icon: "flame.fill", color: .orange)
                chartTile("新歌榜", subtitle: "最新发行", icon: "sparkles", color: MusicXTheme.blue)
                chartTile("飙升榜", subtitle: "正在上升", icon: "chart.line.uptrend.xyaxis", color: .mint)
            }
        }
        .padding(.horizontal, 20)
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 23, weight: .bold))
            Spacer()
            Text(detail).font(.system(size: 12, weight: .medium)).foregroundStyle(MusicXTheme.muted)
        }
    }

    private func songRow(number: String, title: String, artist: String, color: Color) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [color, color.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 54, height: 54)
                .overlay(Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.8)))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(artist).font(.system(size: 12)).foregroundStyle(MusicXTheme.muted)
            }
            Spacer()
            Image(systemName: "ellipsis").foregroundStyle(MusicXTheme.muted)
        }
    }

    private func albumTile(title: String, artist: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [color, color.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .aspectRatio(1, contentMode: .fit)
                .overlay(Image(systemName: "waveform").font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.75)))
            Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text(artist).font(.system(size: 11)).foregroundStyle(MusicXTheme.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartTile(_ title: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.system(size: 21)).foregroundStyle(color)
            Text(title).font(.system(size: 15, weight: .bold))
            Text(subtitle).font(.system(size: 10)).foregroundStyle(MusicXTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(MusicXTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var miniPlayer: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [MusicXTheme.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: "music.note").foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("尚未播放").font(.system(size: 14, weight: .semibold))
                Text("选择一首歌曲开始聆听").font(.system(size: 11)).foregroundStyle(MusicXTheme.muted)
            }
            Spacer()
            Button { isPlaying.toggle() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .disabled(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(MusicXTheme.surface.opacity(0.92))
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
                    .frame(maxWidth: .infinity)
                    .padding(.top, 9)
                    .padding(.bottom, 5)
                }
            }
        }
        .padding(.horizontal, 12)
        .background(MusicXTheme.background.opacity(0.98))
    }

    private func placeholderPage(title: String, subtitle: String, symbol: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 38)).foregroundStyle(MusicXTheme.blue)
            Text(title).font(.system(size: 30, weight: .bold))
            Text(subtitle).font(.system(size: 15)).foregroundStyle(MusicXTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
