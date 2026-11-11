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
            AmberTheme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    AmberScrollTopProbe()

                    // 1. Forward-style Hero Banner
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
                        LazyVStack(spacing: 12) {
                            ForEach(episodes) { ep in
                                EpisodeRowView(episode: ep, feed: feed)
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
            }
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

    // MARK: - Forward / Rex Style Feed Header
    private var feedHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                // Large Squircle Cover Artwork with Drop Shadow
                if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 104, height: 104)
                            .amberMediaCard(radius: AmberTheme.radiusCoverHero)
                    } placeholder: {
                        coverPlaceholder(width: 104, height: 104)
                    }
                } else {
                    coverPlaceholder(width: 104, height: 104)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(feed.title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .lineLimit(2)

                    Text(feed.author)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AmberTheme.labelSecondary)
                        .lineLimit(1)

                    if !isSubscribed {
                        Button {
                            impactFeedback.impactOccurred()
                            subscribeCurrentFeed()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13))
                                Text("一键订阅与全量转译")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AmberTheme.primaryAmber, in: Capsule())
                        }
                        .padding(.top, 4)
                        .disabled(isSubscribing)
                    } else {
                        HStack(spacing: 6) {
                            Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "Apple 播客")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(AmberTheme.primaryAmber)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(AmberTheme.primaryAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                            if autoTranslate {
                                Text("已开启自动双轨")
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(AmberTheme.accentElectric)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(AmberTheme.accentElectric.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Feed Description
            if !feed.description.isEmpty {
                Text(feed.description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 6)
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
