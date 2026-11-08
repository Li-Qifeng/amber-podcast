import Foundation
import SwiftUI

public struct HomeView: View {
    @State private var feeds: [PodcastFeed] = []
    @State private var recentEpisodes: [Episode] = []
    @State private var heroFeed: PodcastFeed? = nil
    @State private var heroEpisode: Episode? = nil
    @State private var isLoading: Bool = true

    @AppStorage("amber_cached_library_json_v2") private var cachedLibraryJson: String = ""
    @ObservedObject var player = DualTrackAudioPlayer.shared
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {
        if let raw = UserDefaults.standard.string(forKey: "amber_cached_library_json_v2"),
           let data = raw.data(using: .utf8),
           let lib = try? JSONDecoder().decode(AmberAPIClient.LibraryResponse.self, from: data),
           !lib.feeds.isEmpty {
            self._feeds = State(initialValue: lib.feeds)
            self._recentEpisodes = State(initialValue: lib.recentEpisodes)
            self._heroFeed = State(initialValue: lib.feeds.first)
            self._heroEpisode = State(initialValue: lib.recentEpisodes.first)
            self._isLoading = State(initialValue: false)
        }
    }

    public var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    AmberTheme.background.ignoresSafeArea()

                    if isLoading && feeds.isEmpty {
                        loadingStateView
                    } else if feeds.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                // 1. Quiet Acoustic Hero Banner
                                heroBannerSection(geometry: geo)

                                // 2. Shelf: "继续收听"
                                if !recentEpisodes.isEmpty {
                                    continueListeningShelf(geometry: geo)
                                        .padding(.top, 20)
                                }

                                // 3. Latest Episodes Stream
                                latestEpisodesSection(geometry: geo)
                                    .padding(.top, 28)

                                // Bottom Clearance for floating Dock & MiniPlayer
                                Color.clear.frame(height: 168)
                            }
                        }
                        .ignoresSafeArea(edges: .top)
                    }

                    // Top Minimalist Header
                    topFloatingToolbar(geometry: geo)
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
        }
    }

    // MARK: - Loading State
    private var loadingStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.0)
            Text("载入中")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AmberTheme.labelSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "headphones")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(AmberTheme.labelTertiary)
                .padding(.top, 60)

            Text("欢迎收听 Amber 播客")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)

            Text("前往「发现」探索全网精彩节目，或在「资料库」中添加您的 RSS 源")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AmberTheme.labelTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top Floating Toolbar
    private func topFloatingToolbar(geometry: GeometryProxy) -> some View {
        let topSafeOffset = max(geometry.safeAreaInsets.top, 24)

        return VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("首页")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Spacer()
            }
            .padding(.horizontal, AmberTheme.pageMargin)
            .padding(.top, topSafeOffset)

            Spacer()
        }
    }

    // MARK: - Hero Banner
    @ViewBuilder
    private func heroBannerSection(geometry: GeometryProxy) -> some View {
        let heroHeight = geometry.size.height * AmberTheme.heroBannerRatio

        ZStack(alignment: .bottomLeading) {
            if let coverUrl = heroFeed?.proxiedCoverUrl, let url = URL(string: coverUrl), !coverUrl.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: heroHeight)
                            .clipped()
                    default:
                        ambientHeroArtworkPlaceholder(width: geometry.size.width, height: heroHeight)
                    }
                }
            } else {
                ambientHeroArtworkPlaceholder(width: geometry.size.width, height: heroHeight)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.04), location: 0.0),
                    .init(color: .black.opacity(0.20), location: 0.40),
                    .init(color: .black.opacity(0.80), location: 0.72),
                    .init(color: AmberTheme.background, location: 0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: geometry.size.width, height: heroHeight)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("精选聚焦")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AmberTheme.primaryAmber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AmberTheme.primaryAmber.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                    if let feed = heroFeed {
                        Text(feed.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AmberTheme.labelSecondary)
                            .lineLimit(1)
                    }
                }

                if let ep = heroEpisode {
                    Text(ep.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .lineLimit(2)
                        .lineSpacing(2)
                }

                HStack(spacing: 12) {
                    if let ep = heroEpisode, let feed = heroFeed {
                        Button {
                            playEpisode(ep, feed: feed)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: isHeroPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text(isHeroPlaying ? "暂停收听" : "立即播放")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8.5)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(TactileButtonStyle(scale: 0.96))

                        if let feed = heroFeed {
                            NavigationLink(destination: FeedDetailView(feed: feed)) {
                                Text("查看节目")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AmberTheme.labelPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8.5)
                                    .liquidGlassCapsule()
                            }
                            .buttonStyle(AmberCapsuleNavigationButtonStyle())
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, AmberTheme.pageMargin)
            .padding(.bottom, 24)
        }
        .frame(width: geometry.size.width, height: heroHeight)
    }

    private func ambientHeroArtworkPlaceholder(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color(red: 0.12, green: 0.12, blue: 0.14)
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<28, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.11))
                        .frame(width: 3, height: barHeight(for: index, in: height))
                }
            }
            .frame(width: width * 0.78)
        }
        .frame(width: width, height: height)
    }

    private func barHeight(for index: Int, in height: CGFloat) -> CGFloat {
        let envelope = sin(Double(index) / 27.0 * .pi)
        let detail = abs(sin(Double(index) * 1.7))
        return height * (0.05 + 0.30 * envelope * (0.45 + 0.55 * detail))
    }

    private var isHeroPlaying: Bool {
        player.currentEpisode?.id == heroEpisode?.id && player.isPlaying
    }

    // MARK: - Continue Listening Shelf
    @ViewBuilder
    private func continueListeningShelf(geometry: GeometryProxy) -> some View {
        let cardWidth = geometry.size.width * AmberTheme.cardShelfWidthRatio
        let cardHeight = cardWidth / AmberTheme.cardShelfAspectRatio

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("继续收听")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Spacer()

                Text("最新 \(recentEpisodes.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AmberTheme.labelTertiary)
            }
            .padding(.horizontal, AmberTheme.pageMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AmberTheme.cardGap) {
                    ForEach(recentEpisodes) { ep in
                        if let feed = feeds.first(where: { $0.id == ep.feedId }) ?? heroFeed {
                            landscapeCard(episode: ep, feed: feed, width: cardWidth, height: cardHeight)
                        }
                    }
                }
                .padding(.horizontal, AmberTheme.pageMargin)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func landscapeCard(episode: Episode, feed: PodcastFeed, width: CGFloat, height: CGFloat) -> some View {
        let isPlayingThis = player.currentEpisode?.id == episode.id

        return Button {
            playEpisode(episode, feed: feed)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: width, height: height)
                                    .clipped()
                            default:
                                coverPlaceholder(width: width, height: height, title: feed.title)
                            }
                        }
                    } else {
                        coverPlaceholder(width: width, height: height, title: feed.title)
                    }

                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)

                    HStack(spacing: 3) {
                        Text(formatDuration(Double(episode.duration)))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(AmberTheme.labelPrimary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(8)

                    if episode.progress > 0 {
                        GeometryReader { pGeo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.12))
                                Rectangle()
                                    .fill(AmberTheme.primaryAmber)
                                    .frame(width: pGeo.size.width * CGFloat(Double(episode.progress) / 100.0))
                            }
                        }
                        .frame(height: 2)
                    }
                }
                .frame(width: width, height: height)
                .amberMediaCard(radius: AmberTheme.radiusCardShelf)

                Text(episode.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(isPlayingThis ? AmberTheme.primaryAmber : AmberTheme.labelPrimary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)

                Text(feed.title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(TactileButtonStyle(scale: 0.97))
    }

    // MARK: - Latest Episodes Stream
    @ViewBuilder
    private func latestEpisodesSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("最新单集")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Spacer()
            }
            .padding(.horizontal, AmberTheme.pageMargin)

            LazyVStack(spacing: 12) {
                ForEach(recentEpisodes.prefix(10)) { ep in
                    EpisodeRowView(episode: ep, feed: feedForEpisode(ep))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func feedForEpisode(_ episode: Episode) -> PodcastFeed {
        if let f = feeds.first(where: { $0.id == episode.feedId }) {
            return f
        }
        if let hf = heroFeed {
            return hf
        }
        return PodcastFeed(
            id: episode.feedId,
            sourceType: "apple_rss",
            title: "未知播客",
            author: "",
            feedUrl: "",
            coverUrl: "",
            description: "",
            autoTranslate: 0
        )
    }

    private func coverPlaceholder(width: CGFloat, height: CGFloat, title: String) -> some View {
        ZStack {
            Color(red: 0.10, green: 0.10, blue: 0.12)
            VStack(spacing: 6) {
                Image(systemName: "headphones")
                    .font(.system(size: min(width, height) * 0.24, weight: .light))
                    .foregroundStyle(AmberTheme.labelTertiary)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: width, height: height)
    }

    private func playEpisode(_ episode: Episode, feed: PodcastFeed) {
        impactFeedback.impactOccurred()
        Task {
            var artifacts: EpisodeArtifacts? = nil
            if episode.status == "ready" {
                artifacts = try? await AmberAPIClient.shared.fetchArtifacts(episodeId: episode.id)
            }
            await MainActor.run {
                if player.currentEpisode?.id == episode.id {
                    if !player.isPlaying {
                        if player.fullMapping.isEmpty && episode.status == "ready" {
                            player.loadEpisode(episode: episode, feed: feed, artifacts: artifacts, autoPlay: true)
                        } else {
                            player.play()
                        }
                    } else {
                        player.pause()
                    }
                } else {
                    player.loadEpisode(episode: episode, feed: feed, artifacts: artifacts, autoPlay: true)
                }
            }
        }
    }

    private func loadData() async {
        do {
            let res = try await AmberAPIClient.shared.fetchLibrary()
            await MainActor.run {
                self.feeds = res.feeds
                self.recentEpisodes = res.recentEpisodes
                self.heroFeed = res.feeds.first
                self.heroEpisode = res.recentEpisodes.first
                self.isLoading = false
                let lib = AmberAPIClient.LibraryResponse(feeds: res.feeds, recentEpisodes: res.recentEpisodes)
                if let data = try? JSONEncoder().encode(lib), let str = String(data: data, encoding: .utf8) {
                    cachedLibraryJson = str
                }
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
