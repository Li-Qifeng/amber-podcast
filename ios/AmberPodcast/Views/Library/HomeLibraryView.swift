import SwiftUI

public struct HomeLibraryView: View {
    @State private var feeds: [PodcastFeed] = []
    @State private var recentEpisodes: [Episode] = []
    @State private var heroFeed: PodcastFeed? = nil
    @State private var heroEpisode: Episode? = nil
    @State private var isLoading: Bool = true
    @State private var showSubscribeSheet: Bool = false
    @State private var newUrlInput: String = ""
    @State private var newAutoTranslate: Bool = false
    @State private var isSubscribing: Bool = false
    @State private var errorMessage: String? = nil

    @ObservedObject var player = DualTrackAudioPlayer.shared
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init() {}

    public var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    AmberTheme.background.ignoresSafeArea()

                    if isLoading && feeds.isEmpty {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("正在载入流媒体库...")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AmberTheme.labelSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if feeds.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                // 1. Forward-style 61.8% Hero Banner
                                heroBannerSection(geometry: geo)

                                // 2. Shelf: "继续收听" (16:9 Landscape Carousel with Peek)
                                continueListeningShelf(geometry: geo)
                                    .padding(.top, 24)

                                // 3. Shelf: "订阅频道" (2:3 Portrait Carousel)
                                subscribedChannelsShelf(geometry: geo)
                                    .padding(.top, 30)

                                Color.clear.frame(height: 120) // Clearance for floating liquid glass Dock
                            }
                        }
                        .ignoresSafeArea(edges: .top)
                    }

                    // Top Floating Minimalist Bar (Channels Switcher & Add Button)
                    topFloatingToolbar(geometry: geo)
                }
            }
            .sheet(isPresented: $showSubscribeSheet) {
                subscribeSheet
            }
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - 1. 61.8% Hero Banner
    @ViewBuilder
    private func heroBannerSection(geometry: GeometryProxy) -> some View {
        let heroHeight = geometry.size.height * AmberTheme.heroBannerRatio

        ZStack(alignment: .bottomLeading) {
            // Ambient Backdrop Artwork
            if let coverUrl = heroFeed?.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { img in
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: heroHeight)
                        .clipped()
                } placeholder: {
                    Rectangle().fill(Color(white: 0.08))
                }
            } else {
                Rectangle().fill(Color(white: 0.08))
            }

            // Dual Falloff Linear Gradient (0% clear -> 35% falloff start -> 65% dark -> 98% pure OLED black)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.15), location: 0.0),
                    .init(color: .black.opacity(0.20), location: 0.35),
                    .init(color: .black.opacity(0.85), location: 0.65),
                    .init(color: AmberTheme.background, location: 0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: geometry.size.width, height: heroHeight)

            // Hero Metadata Overlay (Floating on Gradient)
            VStack(alignment: .leading, spacing: 10) {
                // Category & Badges Line
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text("AI 旗舰双轨")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(AmberTheme.primaryAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .liquidGlassCapsule(tint: AmberTheme.primaryAmber)

                    Text(heroFeed?.sourceType == "xiaoyuzhou" ? "小宇宙精选" : "Apple 播客")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .liquidGlassCapsule()
                }

                // L1 Hero Title (~24pt Bold)
                Text(heroEpisode?.title ?? (heroFeed?.title ?? "精选播客"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .lineLimit(2)
                    .shadow(color: Color.black.opacity(0.6), radius: 8, y: 4)

                // L4 Synopsis (2 lines max)
                if let shownotes = heroEpisode?.shownotes, !shownotes.isEmpty {
                    Text(cleanSnippet(shownotes))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AmberTheme.labelSecondary)
                        .lineSpacing(3)
                        .lineLimit(2)
                        .shadow(color: Color.black.opacity(0.5), radius: 4, y: 2)
                }

                // Direct Play Hero CTA Pill
                Button {
                    if let ep = heroEpisode, let f = heroFeed {
                        playEpisode(ep, feed: f)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isHeroPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.black)

                        Text(isHeroPlaying ? "正在播放" : "立即收听双轨")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                    .shadow(color: Color.white.opacity(0.25), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .tactilePress(scale: 0.94)
                .padding(.top, 4)
            }
            .padding(.horizontal, AmberTheme.pageMargin)
            .padding(.bottom, 20)
        }
        .frame(width: geometry.size.width, height: heroHeight)
    }

    private var isHeroPlaying: Bool {
        player.currentEpisode?.id == heroEpisode?.id && player.isPlaying
    }

    // MARK: - 2. "继续收听" (16:9 Landscape Carousel with Peek 35%)
    @ViewBuilder
    private func continueListeningShelf(geometry: GeometryProxy) -> some View {
        let cardWidth = geometry.size.width * AmberTheme.cardShelfWidthRatio
        let cardHeight = cardWidth / AmberTheme.cardShelfAspectRatio

        VStack(alignment: .leading, spacing: 14) {
            // L2 Section Header
            HStack(alignment: .firstTextBaseline) {
                Text("继续收听")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Spacer()

                Text("最新 \(recentEpisodes.count)")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AmberTheme.labelTertiary)
            }
            .padding(.horizontal, AmberTheme.pageMargin)

            // Horizontal Scroll Carousel with Peek
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AmberTheme.cardGap) {
                    ForEach(recentEpisodes) { ep in
                        if let feed = feeds.first(where: { $0.id == ep.feedId }) ?? heroFeed {
                            landscapeCard(episode: ep, feed: feed, width: cardWidth, height: cardHeight)
                        }
                    }
                }
                .padding(.horizontal, AmberTheme.pageMargin)
            }
        }
    }

    private func landscapeCard(episode: Episode, feed: PodcastFeed, width: CGFloat, height: CGFloat) -> some View {
        let isPlayingThis = player.currentEpisode?.id == episode.id
        return VStack(alignment: .leading, spacing: 6) {
            // 16:9 Liquid Glass Cover with Micro Time Badge
            ZStack(alignment: .bottomLeading) {
                if let url = URL(string: feed.coverUrl), !feed.coverUrl.isEmpty {
                    AsyncImage(url: url) { img in
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(width: width, height: height)
                            .clipped()
                    } placeholder: {
                        Rectangle().fill(Color(white: 0.12))
                    }
                } else {
                    Rectangle().fill(Color(white: 0.12))
                }

                // Dark Gradient Rim
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)

                // Bottom Left Liquid Glass Timecode Capsule
                HStack(spacing: 4) {
                    Circle()
                        .fill(isPlayingThis ? AmberTheme.primaryAmber : Color.white)
                        .frame(width: 5, height: 5)

                    Text(formatDuration(Double(episode.duration)))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(AmberTheme.labelPrimary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .liquidGlassCapsule()
                .padding(8)

                // Hairline Progress Bar along card bottom edge
                if episode.progress > 0 {
                    GeometryReader { pGeo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.15))
                            Rectangle()
                                .fill(AmberTheme.primaryAmber)
                                .frame(width: pGeo.size.width * CGFloat(Double(episode.progress) / 100.0))
                        }
                    }
                    .frame(height: 2.5)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: AmberTheme.radiusCardShelf, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AmberTheme.radiusCardShelf, style: .continuous)
                    .strokeBorder(
                        isPlayingThis ?
                        LinearGradient(colors: [AmberTheme.primaryAmber, AmberTheme.primaryAmber.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)

            // L3 Card Title (13.5pt Semibold)
            Text(episode.title)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(isPlayingThis ? AmberTheme.primaryAmber : AmberTheme.labelPrimary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)

            // L5 Subtitle
            Text(feed.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AmberTheme.labelTertiary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .tactilePress(scale: 0.96) {
            playEpisode(episode, feed: feed)
        }
    }

    // MARK: - 3. "订阅频道" (2:3 Portrait Carousel)
    @ViewBuilder
    private func subscribedChannelsShelf(geometry: GeometryProxy) -> some View {
        let posterWidth: CGFloat = 114.0
        let posterHeight = posterWidth * 1.45

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("订阅频道")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Spacer()

                NavigationLink(destination: AllChannelsListView(feeds: feeds)) {
                    Text("查看全部 >")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AmberTheme.primaryAmber)
                }
            }
            .padding(.horizontal, AmberTheme.pageMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(feeds) { feed in
                        NavigationLink(destination: FeedDetailView(feed: feed)) {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .bottomTrailing) {
                                    if let url = URL(string: feed.coverUrl), !feed.coverUrl.isEmpty {
                                        AsyncImage(url: url) { img in
                                            img
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: posterWidth, height: posterHeight)
                                                .clipped()
                                        } placeholder: {
                                            Rectangle().fill(Color(white: 0.12))
                                        }
                                    } else {
                                        Rectangle().fill(Color(white: 0.12))
                                    }

                                    // Source Tag
                                    Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "Apple")
                                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .liquidGlassCapsule()
                                        .padding(6)
                                }
                                .frame(width: posterWidth, height: posterHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                                )
                                .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)

                                Text(feed.title)
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AmberTheme.labelPrimary)
                                    .lineLimit(1)
                                    .frame(width: posterWidth, alignment: .leading)

                                Text(feed.author)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AmberTheme.labelTertiary)
                                    .lineLimit(1)
                                    .frame(width: posterWidth, alignment: .leading)
                            }
                            .tactilePress(scale: 0.95)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AmberTheme.pageMargin)
            }
        }
    }

    // MARK: - Top Floating Toolbar (Glass Capsule)
    private func topFloatingToolbar(geometry: GeometryProxy) -> some View {
        VStack {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "headphones")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AmberTheme.primaryAmber)

                    Text("AMBER PODCAST")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .liquidGlassCapsule()

                Spacer()

                Button {
                    impactFeedback.impactOccurred()
                    showSubscribeSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .frame(width: 34, height: 34)
                        .liquidGlassCapsule()
                }
                .buttonStyle(.plain)
                .tactilePress(scale: 0.90)
            }
            .padding(.horizontal, AmberTheme.pageMargin)
            .padding(.top, geometry.safeAreaInsets.top > 0 ? geometry.safeAreaInsets.top + 2 : 12)

            Spacer()
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AmberTheme.primaryAmber.opacity(0.12))
                    .frame(width: 84, height: 84)

                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 38))
                    .foregroundStyle(AmberTheme.primaryAmber)
            }
            .ambientGlow()
            .padding(.top, 60)

            Text("流媒体资料库暂无播客")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)

            Text("轻触右上角 ＋ 粘贴 Apple Podcasts 或小宇宙链接，或前往发现页搜索")
                .font(.system(size: 13))
                .foregroundStyle(AmberTheme.labelTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showSubscribeSheet = true
            } label: {
                Text("订阅首个播客")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(AmberTheme.primaryAmber, in: Capsule())
            }
            .tactilePress()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subscribe Sheet
    private var subscribeSheet: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RSS 订阅源或播客 URL")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AmberTheme.labelTertiary)

                        TextField("粘贴 Apple Podcasts / 小宇宙链接", text: $newUrlInput)
                            .font(.system(size: 14))
                            .padding(14)
                            .liquidGlassCard(cornerRadius: 14)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Toggle(isOn: $newAutoTranslate) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动 AI 双轨转译")
                                .font(.system(size: 14, weight: .semibold))
                            Text("新单集入库后自动生成中文配音与对齐字幕")
                                .font(.system(size: 11))
                                .foregroundStyle(AmberTheme.labelTertiary)
                        }
                    }
                    .tint(AmberTheme.primaryAmber)
                    .padding(14)
                    .liquidGlassCard(cornerRadius: 14)

                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundStyle(Color.red)
                    }

                    Spacer()

                    Button {
                        submitSubscription()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubscribing { ProgressView().padding(.trailing, 6) }
                            Text(isSubscribing ? "正在解析添加..." : "确认订阅")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black)
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(AmberTheme.primaryAmber, in: Capsule())
                    }
                    .disabled(newUrlInput.trimmingCharacters(in: .whitespaces).isEmpty || isSubscribing)
                }
                .padding(20)
            }
            .navigationTitle("添加播客")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showSubscribeSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers
    private func loadData() async {
        isLoading = true
        do {
            let fetchedFeeds = try await AmberAPIClient.shared.listFeeds()
            var allEps: [Episode] = []
            for f in fetchedFeeds {
                let eps = (try? await AmberAPIClient.shared.listEpisodes(feedId: f.id)) ?? []
                allEps.append(contentsOf: eps)
            }
            await MainActor.run {
                self.feeds = fetchedFeeds
                self.recentEpisodes = allEps
                self.heroFeed = fetchedFeeds.first
                self.heroEpisode = allEps.first
                self.isLoading = false
            }
        } catch {
            await MainActor.run { self.isLoading = false }
        }
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
                    player.togglePlayPause()
                } else {
                    player.loadEpisode(episode: episode, feed: feed, artifacts: artifacts, autoPlay: true)
                }
            }
        }
    }

    private func submitSubscription() {
        let url = newUrlInput.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        isSubscribing = true
        Task {
            do {
                try await AmberAPIClient.shared.subscribe(url: url, autoTranslate: newAutoTranslate)
                await loadData()
                await MainActor.run {
                    self.isSubscribing = false
                    self.showSubscribeSheet = false
                    self.newUrlInput = ""
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "订阅失败: \(error.localizedDescription)"
                    self.isSubscribing = false
                }
            }
        }
    }

    private func cleanSnippet(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes) min"
    }
}

// Simple view for "查看全部"
public struct AllChannelsListView: View {
    public let feeds: [PodcastFeed]

    public var body: some View {
        ZStack {
            AmberTheme.background.ignoresSafeArea()
            List(feeds) { f in
                NavigationLink(destination: FeedDetailView(feed: f)) {
                    HStack(spacing: 12) {
                        if let url = URL(string: f.coverUrl), !f.coverUrl.isEmpty {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                            } placeholder: {
                                Rectangle().fill(Color(white: 0.12)).frame(width: 44, height: 44)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(AmberTheme.labelPrimary)
                            Text(f.author).font(.system(size: 12)).foregroundStyle(AmberTheme.labelTertiary)
                        }
                    }
                }
                .listRowBackground(AmberTheme.glassSurface)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("全部频道")
        .preferredColorScheme(.dark)
    }
}
