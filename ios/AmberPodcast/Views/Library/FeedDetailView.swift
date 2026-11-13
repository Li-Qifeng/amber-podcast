import SwiftUI

public struct FeedDetailView: View {
    public let feed: PodcastFeed
    @State private var episodes: [Episode] = []
    @State private var isLoading: Bool = true
    @State private var autoTranslate: Bool
    @State private var showDeleteConfirm: Bool = false
    @State private var isDeleting: Bool = false
    @State private var isSubscribed: Bool = false
    @State private var isSubscribing: Bool = false
    @State private var newEpisodesCount: Int = 0
    @State private var pendingEpisodes: [Episode]? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = DualTrackAudioPlayer.shared
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(feed: PodcastFeed) {
        self.feed = feed
        self._autoTranslate = State(initialValue: feed.autoTranslate == 1)
        if let cached = FeedEpisodesCache.get(feedId: feed.id), !cached.isEmpty {
            self._episodes = State(initialValue: cached)
            self._isLoading = State(initialValue: false)
        }
    }

    public var body: some View {
        ZStack {
            // Apple channel-page tint: the show's own artwork, blurred, fills
            // the whole page. A scrim keeps label contrast in both modes.
            feedTintBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    AmberScrollTopProbe()

                    // 1. Apple channel-style header: centred artwork, title,
                    //    action bar and metadata over the tinted canvas.
                    feedHeader

                    // 2. Section Header: Episodes Count & Action
                    HStack(alignment: .firstTextBaseline) {
                        Text("全部单集")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AmberTheme.labelPrimary)

                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .padding(.leading, 6)
                        } else {
                            Text("\(episodes.count) 集")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(AmberTheme.labelSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    if newEpisodesCount > 0 {
                        Button {
                            applyNewEpisodes()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AmberTheme.primaryAmber)
                                Text("发现 \(newEpisodesCount) 条新单集，轻触查看")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AmberTheme.labelPrimary)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(AmberTheme.labelSecondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .liquidGlassCapsule()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 20)
                    }

                    // 3. Episode Cards Stack or Empty State
                    if episodes.isEmpty && !isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(AmberTheme.labelTertiary)
                            Text("暂无可播放单集")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AmberTheme.labelSecondary)
                            Text("服务端可能正在抓取中，请稍后下拉刷新")
                                .font(.system(size: 12))
                                .foregroundStyle(AmberTheme.labelTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 50)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(episodes) { ep in
                                EpisodeRowView(episode: ep, feed: feed, showsPlate: false)
                                if ep.id != episodes.last?.id {
                                    Divider()
                                        .background(AmberTheme.labelTertiary.opacity(0.25))
                                        .padding(.leading, 100)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 140) // Clearance for floating mini player & dock
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .amberScrollObservable()
        }
        .navigationBarTitleDisplayMode(.inline)
        // Custom back button: the parent tab uses an empty system title, so the
        // default back label would collapse into a "..." placeholder.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSubscribed {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("取消订阅此播客", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .label))
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                } else {
                    Button {
                        impactFeedback.impactOccurred()
                        subscribeCurrentFeed()
                    } label: {
                        if isSubscribing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 32, height: 32)
                        } else {
                            // Match home's CircularLiquidGlassAddButton: 32pt circle,
                            // same glyph size and tint. The toolbar supplies the glass.
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .label))
                                .frame(width: 32, height: 32)
                                .contentShape(Circle())
                        }
                    }
                    .disabled(isSubscribing)
                }
            }
        }
        .confirmationDialog("取消订阅", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("取消订阅并移除", role: .destructive) {
                Task {
                    isDeleting = true
                    try? await AmberAPIClient.shared.deleteFeed(feedId: feed.id)
                    await MainActor.run {
                        isDeleting = false
                        isSubscribed = false
                        dismiss()
                    }
                }
            }
            Button("保留订阅", role: .cancel) {}
        } message: {
            Text("确定要取消订阅《\(feed.title)》吗？已转译的音频资源将不再保留。")
        }
        .task {
            await checkSubscriptionStatus()
            await loadEpisodes()
        }
        .refreshable {
            await loadEpisodes()
        }
    }

    // MARK: - Subscription Check
    private func checkSubscriptionStatus() async {
        if let feeds = try? await AmberAPIClient.shared.listFeeds() {
            await MainActor.run {
                self.isSubscribed = feeds.contains { $0.id == feed.id || (!feed.feedUrl.isEmpty && $0.feedUrl == feed.feedUrl) }
            }
        }
    }

    private func subscribeCurrentFeed() {
        guard !feed.feedUrl.isEmpty else { return }
        isSubscribing = true
        Task {
            do {
                try await AmberAPIClient.shared.subscribe(url: feed.feedUrl, autoTranslate: autoTranslate)
                await MainActor.run {
                    self.isSubscribed = true
                    self.isSubscribing = false
                }
            } catch {
                await MainActor.run {
                    self.isSubscribing = false
                }
            }
        }
    }

    // MARK: - Apple Channel-Style Feed Header
    /// Whole-page tint from the show's artwork, scrimmed for legibility.
    private var feedTintBackground: some View {
        Group {
            if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .blur(radius: 60)
                        .clipped()
                } placeholder: {
                    AmberTheme.background
                }
            } else {
                AmberTheme.background
            }
        }
        .overlay(
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0, green: 0, blue: 0, alpha: 0.52)
                    : UIColor(red: 1, green: 1, blue: 1, alpha: 0.62)
            })
        )
        .animation(.easeInOut(duration: 0.35), value: feed.id)
    }

    private var feedHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Centred hero artwork, no card frame — merges into the tint
            Group {
                if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 210, height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: .black.opacity(0.30), radius: 18, y: 8)
                    } placeholder: {
                        coverPlaceholder(width: 210, height: 210)
                    }
                } else {
                    coverPlaceholder(width: 210, height: 210)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 10) {
                Text(feed.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .lineLimit(2)

                // Action bar: play-latest capsule + subscription state
                HStack(spacing: 10) {
                    Button {
                        impactFeedback.impactOccurred()
                        if let first = episodes.first {
                            // Same semantics as the row's play button: toggle
                            // pause/resume for the current episode, otherwise start.
                            if player.currentEpisode?.id == first.id {
                                if player.isPlaying {
                                    player.pause()
                                } else if player.fullMapping.isEmpty {
                                    Task { await player.playNewEpisode(episode: first, feed: feed) }
                                } else {
                                    player.play()
                                }
                            } else {
                                Task { await player.playNewEpisode(episode: first, feed: feed) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: player.currentEpisode?.id == episodes.first?.id && player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("最新单集")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.82), in: Capsule())
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.95))
                    .disabled(episodes.isEmpty)

                    if isSubscribed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.22), in: Circle())
                    } else {
                        Button {
                            impactFeedback.impactOccurred()
                            subscribeCurrentFeed()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AmberTheme.labelPrimary)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.22), in: Circle())
                        }
                        .buttonStyle(TactileButtonStyle(scale: 0.92))
                        .disabled(isSubscribing)
                    }
                }

                // Metadata line: genre · episode count · source · auto-translate
                HStack(spacing: 6) {
                    if let g = feed.genre, !g.isEmpty {
                        Text(g)
                        metaDot
                    }
                    Text(isLoading ? "…" : "\(episodes.count) 集")
                    metaDot
                    Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "Apple 播客")
                    if autoTranslate {
                        metaDot
                        Text("双轨")
                    }
                }
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(AmberTheme.labelSecondary)

                if !feed.description.isEmpty {
                    Text(feed.description)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AmberTheme.labelSecondary)
                        .lineSpacing(4)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 6)
    }

    private var metaDot: some View {
        Text("·")
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(AmberTheme.labelTertiary)
    }

    private func coverPlaceholder(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color(red: 0.10, green: 0.10, blue: 0.12)
            Image(systemName: "headphones")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AmberTheme.labelTertiary)
        }
        .frame(width: width, height: height)
        .amberMediaCard(radius: AmberTheme.radiusCoverHero)
    }

    private func applyNewEpisodes() {
        guard let p = pendingEpisodes else { return }
        impactFeedback.impactOccurred()
        withAnimation(ForwardMotion.touchUp) {
            self.episodes = p
            FeedEpisodesCache.set(feedId: self.feed.id, episodes: p)
            self.newEpisodesCount = 0
            self.pendingEpisodes = nil
        }
    }

    private func loadEpisodes() async {
        if episodes.isEmpty {
            isLoading = true
        }
        do {
            let fetched = try await AmberAPIClient.shared.listEpisodes(feedId: feed.id, feedUrl: feed.feedUrl)
            await MainActor.run {
                if self.episodes.isEmpty {
                    self.episodes = fetched
                    FeedEpisodesCache.set(feedId: self.feed.id, episodes: fetched)
                } else {
                    let newOnes = fetched.filter { f in !self.episodes.contains(where: { $0.id == f.id }) }
                    if !newOnes.isEmpty {
                        withAnimation(ForwardMotion.touchUp) {
                            self.newEpisodesCount = newOnes.count
                            self.pendingEpisodes = fetched
                        }
                    } else {
                        FeedEpisodesCache.set(feedId: self.feed.id, episodes: fetched)
                    }
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}
