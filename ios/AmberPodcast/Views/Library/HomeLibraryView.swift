import Foundation
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

    @AppStorage("amber_cached_library_json_v2") private var cachedLibraryJson: String = ""

    @ObservedObject var player = DualTrackAudioPlayer.shared
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {
        if let raw = UserDefaults.standard.string(forKey: "amber_cached_library_json_v1"),
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
                    // Deep Graphite Canvas
                    AmberTheme.background
                        .ignoresSafeArea()

                    if isLoading && feeds.isEmpty {
                        loadingStateView
                    } else if feeds.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                AmberScrollTopProbe()

                                // 1. Quiet Acoustic Hero Banner (58% Balanced Proportion)
                                heroBannerSection(geometry: geo)

                                // 2. Shelf: "继续收听" (16:9 Precision Carousel)
                                continueListeningShelf(geometry: geo)
                                    .padding(.top, 20)

                                // 3. Shelf: "订阅频道" (2:3 Portrait Carousel)
                                subscribedChannelsShelf(geometry: geo)
                                    .padding(.top, 28)

                                // Bottom Clearance for floating Dock & MiniPlayer
                                Color.clear.frame(height: 168)
                            }
                        }
                        .amberScrollObservable(tab: 0)
                        .ignoresSafeArea(edges: .top)
                    }
                }
            }
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CircularLiquidGlassAddButton {
                        showSubscribeSheet = true
                    }
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

    // MARK: - 1. Acoustic Hero Banner
    @ViewBuilder
    private func heroBannerSection(geometry: GeometryProxy) -> some View {
        let heroHeight = geometry.size.height * AmberTheme.heroBannerRatio

        ZStack(alignment: .bottomLeading) {
            // Layer 1: High-Resolution Artwork Layer
            if let coverUrl = heroFeed?.proxiedCoverUrl, let url = URL(string: coverUrl), !coverUrl.isEmpty {
                CachedAsyncImage(url: url) { img in
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: heroHeight)
                        .clipped()
                } placeholder: {
                    ambientHeroArtworkPlaceholder(width: geometry.size.width, height: heroHeight)
                }
            } else {
                ambientHeroArtworkPlaceholder(width: geometry.size.width, height: heroHeight)
            }

            // Layer 2: Transition Scrim (Smooth gradient falloff isolating artwork from text, fading into background)
            VStack(spacing: 0) {
                // Top Protection Scrim: Ensures status bar and navigation bar items have consistent contrast
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.55), location: 0.0),
                        .init(color: Color.black.opacity(0.20), location: 0.50),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 110)

                Spacer()

                // Bottom Transition Scrim
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.black.opacity(0.35), location: 0.35),
                        .init(color: AmberTheme.background.opacity(0.85), location: 0.70),
                        .init(color: AmberTheme.background, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: heroHeight * 0.70)
            }
            .frame(width: geometry.size.width, height: heroHeight)

            // Layer 3: Independent Crystal-Clear Typography & CTA Layer (Always on top of scrim, never blurred)
            VStack(alignment: .leading, spacing: 8) {
                // Honest Technical Badges (No Sparkle Slop)
                HStack(spacing: 6) {
                    Text("双轨同传")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AmberTheme.primaryAmber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AmberTheme.primaryAmber.opacity(0.16), in: RoundedRectangle(cornerRadius: AmberTheme.radiusBadge, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AmberTheme.radiusBadge, style: .continuous)
                                .strokeBorder(AmberTheme.primaryAmber.opacity(0.30), lineWidth: 0.5)
                        )

                    Text(heroFeed?.sourceType == "xiaoyuzhou" ? "小宇宙精选" : "Apple 播客")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(AmberTheme.labelSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: AmberTheme.radiusBadge, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AmberTheme.radiusBadge, style: .continuous)
                                .strokeBorder(AmberTheme.borderHairline, lineWidth: 0.5)
                        )
                }

                // L1 Hero Title (Crisp, High Contrast, San Francisco 24pt Bold)
                Text(heroEpisode?.title ?? (heroFeed?.title ?? "精选播客"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .shadow(color: Color.black.opacity(0.85), radius: 6, y: 2)

                // L4 Synopsis (Clean, calm reading snippet)
                if let shownotes = heroEpisode?.shownotes, !shownotes.isEmpty {
                    Text(cleanSnippet(shownotes))
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineSpacing(3)
                        .lineLimit(2)
                        .shadow(color: Color.black.opacity(0.70), radius: 4, y: 1)
                }

                // Primary CTA (Solid White, Nested Radius)
                Button {
                    if let ep = heroEpisode, let f = heroFeed {
                        playEpisode(ep, feed: f)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isHeroPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))

                        Text(isHeroPlaying ? "正在播放" : (heroEpisode?.status == "ready" ? "收听双轨" : "立即播放"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
                }
                .buttonStyle(TactileButtonStyle(scale: 0.96))
                .padding(.top, 4)
            }
            .padding(.horizontal, AmberTheme.pageMargin)
            .padding(.bottom, 16)
        }
        .frame(width: geometry.size.width, height: heroHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            if let ep = heroEpisode, let f = heroFeed {
                playEpisode(ep, feed: f)
            }
        }
    }

    /// Missing-artwork hero. Rex answers this with `BoardMissingArtworkView` +
    /// `AtmosphereView`: a metallic gradient carrying a geometric texture, so an
    /// absent cover still reads as artwork instead of an empty well.
    private func ambientHeroArtworkPlaceholder(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.15, blue: 0.14),
                    Color(red: 0.07, green: 0.07, blue: 0.08),
                    Color(red: 0.02, green: 0.02, blue: 0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Static acoustic spectrum: deterministic heights, no animation.
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

    // MARK: - 2. "继续收听" (16:9 Landscape Carousel)
    @ViewBuilder
    private func continueListeningShelf(geometry: GeometryProxy) -> some View {
        let cardWidth = geometry.size.width * AmberTheme.cardShelfWidthRatio
        let cardHeight = cardWidth / AmberTheme.cardShelfAspectRatio

        VStack(alignment: .leading, spacing: 12) {
            // L2 Section Header
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

            // Horizontal Scroll Carousel with Magnetic Snapping
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
                // 16:9 Card Artwork
                ZStack(alignment: .bottomLeading) {
                    if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                        CachedAsyncImage(url: url) { img in
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(width: width, height: height)
                                .clipped()
                        } placeholder: {
                            coverPlaceholder(width: width, height: height, title: feed.title)
                        }
                    } else {
                        coverPlaceholder(width: width, height: height, title: feed.title)
                    }

                    // Subtle Bottom Vignette
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)

                    // Minimal Acoustic Timecode Tag (No Floating Pill Slop)
                    HStack(spacing: 3) {
                        Text(formatDuration(Double(episode.duration)))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(AmberTheme.labelPrimary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
                    .padding(8)

                    // Hairline Progress Bar
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

                // L3 Title (13pt, Medium weight)
                Text(episode.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(isPlayingThis ? AmberTheme.primaryAmber : AmberTheme.labelPrimary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)

                // L5 Subtitle (11pt, Muted)
                Text(feed.title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(TactileButtonStyle(scale: 0.97))
    }

    // MARK: - 3. "订阅频道" (2:3 Portrait Carousel)
    @ViewBuilder
    private func subscribedChannelsShelf(geometry: GeometryProxy) -> some View {
        let posterWidth: CGFloat = 110.0
        let posterHeight = posterWidth * 1.45

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("订阅频道")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Spacer()

                NavigationLink(destination: AllChannelsListView(feeds: feeds)) {
                    Text("全部")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AmberTheme.labelSecondary)
                }
            }
            .padding(.horizontal, AmberTheme.pageMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(feeds) { feed in
                        NavigationLink(destination: FeedDetailView(feed: feed)) {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .bottomTrailing) {
                                    if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                                        CachedAsyncImage(url: url) { img in
                                            img
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: posterWidth, height: posterHeight)
                                                .clipped()
                                        } placeholder: {
                                            coverPlaceholder(width: posterWidth, height: posterHeight, title: feed.title)
                                        }
                                    } else {
                                        coverPlaceholder(width: posterWidth, height: posterHeight, title: feed.title)
                                    }

                                    // Quiet Source Tag
                                    Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "Apple")
                                        .font(.system(size: 8.5, weight: .regular))
                                        .foregroundStyle(Color.white.opacity(0.85))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                                        .padding(5)
                                }
                                .frame(width: posterWidth, height: posterHeight)
                                .amberMediaCard(radius: 10)

                                Text(feed.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AmberTheme.labelPrimary)
                                    .lineLimit(1)
                                    .frame(width: posterWidth, alignment: .leading)

                                Text(feed.author)
                                    .font(.system(size: 10.5, weight: .regular))
                                    .foregroundStyle(AmberTheme.labelTertiary)
                                    .lineLimit(1)
                                    .frame(width: posterWidth, alignment: .leading)
                            }
                        }
                        .buttonStyle(TactileButtonStyle(scale: 0.97))
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    try? await AmberAPIClient.shared.deleteFeed(feedId: feed.id)
                                    await loadData()
                                }
                                impactFeedback.impactOccurred()
                            } label: {
                                Label("取消订阅", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, AmberTheme.pageMargin)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    // MARK: - Empty State (Quiet & Clear)
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "headphones")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(AmberTheme.labelTertiary)
                .padding(.top, 60)

            Text("资料库暂无播客")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)

            Text("轻触右上角 ＋ 粘贴 Apple Podcasts 或小宇宙链接")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AmberTheme.labelTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showSubscribeSheet = true
            } label: {
                Text("订阅播客")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(TactileButtonStyle(scale: 0.96))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subscribe Sheet
    private var subscribeSheet: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RSS 订阅源或播客 URL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AmberTheme.labelSecondary)

                        TextField("粘贴 Apple Podcasts / 小宇宙链接", text: $newUrlInput)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(AmberTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(AmberTheme.borderHairline, lineWidth: 0.5)
                            )
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Toggle(isOn: $newAutoTranslate) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动双轨转译")
                                .font(.system(size: 14, weight: .medium))
                            Text("新单集入库后生成中文配音与对齐字幕")
                                .font(.system(size: 11))
                                .foregroundStyle(AmberTheme.labelTertiary)
                        }
                    }
                    .tint(AmberTheme.primaryAmber)
                    .padding(12)
                    .background(AmberTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AmberTheme.borderHairline, lineWidth: 0.5)
                    )

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
                            Text(isSubscribing ? "正在解析..." : "确认订阅")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    }

    // MARK: - Helpers
    private func restoreFromCache() {
        guard feeds.isEmpty, !cachedLibraryJson.isEmpty,
              let data = cachedLibraryJson.data(using: .utf8),
              let lib = try? JSONDecoder().decode(AmberAPIClient.LibraryResponse.self, from: data),
              !lib.feeds.isEmpty else {
            return
        }
        self.feeds = lib.feeds
        self.recentEpisodes = lib.recentEpisodes
        self.heroFeed = lib.feeds.first
        self.heroEpisode = lib.recentEpisodes.first
        self.isLoading = false
    }

    private func saveToCache(feeds: [PodcastFeed], recentEpisodes: [Episode]) {
        let lib = AmberAPIClient.LibraryResponse(feeds: feeds, recentEpisodes: recentEpisodes)
        if let data = try? JSONEncoder().encode(lib), let str = String(data: data, encoding: .utf8) {
            cachedLibraryJson = str
        }
    }

    private func loadData() async {
        // Instant restore from cache if memory is empty
        if feeds.isEmpty {
            restoreFromCache()
            if feeds.isEmpty {
                isLoading = true
            }
        }

        do {
            let lib = try await AmberAPIClient.shared.fetchLibrary()
            await MainActor.run {
                if lib.feeds.isEmpty {
                    #if DEBUG
                    self.feeds = PodcastFeed.samples
                    self.recentEpisodes = Episode.samples
                    self.heroFeed = PodcastFeed.samples.first
                    self.heroEpisode = Episode.samples.first
                    #else
                    self.feeds = []
                    self.recentEpisodes = []
                    self.heroFeed = nil
                    self.heroEpisode = nil
                    #endif
                } else {
                    self.feeds = lib.feeds
                    self.recentEpisodes = lib.recentEpisodes
                    self.heroFeed = lib.feeds.first
                    self.heroEpisode = lib.recentEpisodes.first
                    self.saveToCache(feeds: lib.feeds, recentEpisodes: lib.recentEpisodes)
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                if self.feeds.isEmpty {
                    self.restoreFromCache()
                }
                self.isLoading = false
            }
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

            if feeds.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(AmberTheme.labelTertiary)
                    Text("暂无订阅频道")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)
                    Text("前往「发现」页面搜索并订阅您感兴趣的播客。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AmberTheme.labelTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(feeds) { f in
                        NavigationLink(destination: FeedDetailView(feed: f)) {
                            HStack(spacing: 14) {
                                channelCover(feed: f)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(f.title)
                                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                        .lineLimit(1)
                                    Text(f.author.isEmpty ? "播客主" : f.author)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AmberTheme.labelTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .listRowBackground(AmberTheme.surfaceCard)
                    }

                    Color.clear
                        .frame(height: 140)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("全部频道")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func channelCover(feed: PodcastFeed) -> some View {
        Group {
            if let url = URL(string: feed.coverUrl), !feed.coverUrl.isEmpty {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    coverPlaceholder
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 46, height: 46)
        .amberMediaCard(radius: 8)
    }

    private var coverPlaceholder: some View {
        ZStack {
            Color(red: 0.12, green: 0.12, blue: 0.14)
            Image(systemName: "headphones")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(AmberTheme.labelTertiary)
        }
        .frame(width: 46, height: 46)
    }
}
