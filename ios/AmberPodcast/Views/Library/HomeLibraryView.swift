import Foundation
import SwiftUI
import UIKit

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
    @State private var discoverFeed: AmberAPIClient.DiscoverFeedResponse? = nil
    @State private var isLoadingDiscover: Bool = false

    @AppStorage("amber_cached_library_json_v2") private var cachedLibraryJson: String = ""

    /// Fixed screen geometry. Read from UIScreen (not a live GeometryReader) so
    /// content never re-lays out when NavigationStack's large title collapses or
    /// the bottom accessory resizes.
    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    private var screenHeight: CGFloat { UIScreen.main.bounds.height }

    /// The hero only shows an episode published *after* its feed was subscribed,
    /// so a freshly added show never pushes its back-catalogue up top. The server
    /// picks that episode (`hero_episode`); when nothing new has dropped yet it is
    /// nil and the hero section collapses entirely. The artwork must still belong
    /// to the feed that owns the episode, never feeds.first.
    private static func heroPair(
        feeds: [PodcastFeed], heroEpisode: Episode?
    ) -> (PodcastFeed?, Episode?) {
        guard let ep = heroEpisode else { return (nil, nil) }
        return (feeds.first(where: { $0.id == ep.feedId }) ?? feeds.first, ep)
    }

    @ObservedObject var player = DualTrackAudioPlayer.shared
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {
        if let raw = UserDefaults.standard.string(forKey: "amber_cached_library_json_v1"),
           let data = raw.data(using: .utf8),
           let lib = try? JSONDecoder().decode(AmberAPIClient.LibraryResponse.self, from: data),
           !lib.feeds.isEmpty {
            self._feeds = State(initialValue: lib.feeds)
            self._recentEpisodes = State(initialValue: lib.recentEpisodes)
            let hero = Self.heroPair(feeds: lib.feeds, heroEpisode: lib.heroEpisode)
            self._heroFeed = State(initialValue: hero.0)
            self._heroEpisode = State(initialValue: hero.1)
            self._isLoading = State(initialValue: false)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Deep Graphite Canvas
                AmberTheme.background
                    .ignoresSafeArea()

                if isLoading && feeds.isEmpty {
                    loadingStateView
                } else if feeds.isEmpty {
                    emptyStateView
                } else {
                    // NOTE: no GeometryReader wrapping this ScrollView. Wrapping it
                    // detaches the scroll view from NavigationStack's large-title
                    // collapse tracking, so the nav bar + blur stuttered on the
                    // first upward scroll. Geometry now comes from a fixed screen
                    // size instead of a live proxy.
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            AmberScrollTopProbe()

                            // 1. 最新单集 (only when heroEpisode != nil)
                            if heroEpisode != nil {
                                latestEpisodesShelf()
                            }

                            // 2. 继续收听
                            continueListeningShelf()
                                .padding(.top, heroEpisode != nil ? 20 : 8)

                            // 3. 我的播客
                            subscribedChannelsShelf()
                                .padding(.top, 28)

                            // 4. 为你推荐
                            forYouShelf()
                                .padding(.top, 28)

                            // Bottom Clearance for floating Dock & MiniPlayer
                            Color.clear.frame(height: 168)
                        }
                    }
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .amberScrollObservable(tab: 0)
                }
            }
            .navigationTitle("首页")
            .toolbarTitleDisplayMode(.inlineLarge)
            .amberImmersiveTopEdge()
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

    // MARK: - 1. 最新单集 (Apple Podcasts card style)
    @ViewBuilder
    private func latestEpisodesShelf() -> some View {
        if let ep = heroEpisode, let feed = heroFeed {
            let cardWidth = screenWidth * 0.82

            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("最新单集")
                    .padding(.horizontal, AmberTheme.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: AmberTheme.cardGap) {
                        latestEpisodeCard(episode: ep, feed: feed, cardWidth: cardWidth)
                    }
                    .padding(.horizontal, AmberTheme.pageMargin)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
    }

    private func latestEpisodeCard(episode: Episode, feed: PodcastFeed, cardWidth: CGFloat) -> some View {
        // Apple "New Episodes" pattern: a self-contained dark container card —
        // wide artwork flush to the top edge, then date / title / synopsis and a
        // play capsule + ellipsis action bar.
        let isPlayingThis = player.currentEpisode?.id == episode.id
        let artworkHeight = cardWidth * 0.62
        let synopsis = stripHTML(episode.shownotes ?? "")

        return Button {
            playEpisode(episode, feed: feed)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Wide artwork flush to the container's top edge
                ZStack(alignment: .bottom) {
                    if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                        CachedAsyncImage(url: url) { img in
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(width: cardWidth, height: artworkHeight)
                                .clipped()
                        } placeholder: {
                            coverPlaceholder(width: cardWidth, height: artworkHeight, title: feed.title)
                        }
                    } else {
                        coverPlaceholder(width: cardWidth, height: artworkHeight, title: feed.title)
                    }

                    // Progress bar at artwork bottom (if played)
                    if episode.progress > 0 {
                        GeometryReader { pGeo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.12))
                                Rectangle()
                                    .fill(AmberTheme.primaryAmber)
                                    .frame(width: pGeo.size.width * CGFloat(Double(episode.progress) / 100.0))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .frame(width: cardWidth, height: artworkHeight)
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    // Published date
                    Text(episode.pubDate)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AmberTheme.labelTertiary)

                    // Episode title (fixed 2 lines)
                    Text(episode.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isPlayingThis ? AmberTheme.primaryAmber : AmberTheme.labelPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !synopsis.isEmpty {
                        Text(synopsis)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AmberTheme.labelSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    // Bottom action bar: play capsule + ellipsis placeholder
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(isPlayingThis ? "正在播放" : "立即播放")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.10), in: Capsule())

                        Spacer()

                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AmberTheme.labelTertiary)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(width: cardWidth)
            .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle(scale: 0.97))
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

    // MARK: - 2. 继续收听 (Apple "Continue Playing" row card style)
    @ViewBuilder
    private func continueListeningShelf() -> some View {
        let cardWidth = screenWidth * 0.78

        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("继续收听")

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
                            episodeCard(episode: ep, feed: feed, width: cardWidth)
                        }
                    }
                }
                .padding(.horizontal, AmberTheme.pageMargin)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    private func episodeCard(episode: Episode, feed: PodcastFeed, width: CGFloat) -> some View {
        // Apple "Continue Playing" pattern: horizontal row card — square artwork
        // on the left, show name / episode title / play capsule on the right.
        let isPlayingThis = player.currentEpisode?.id == episode.id
        let remaining = episode.progress > 0
            ? Double(episode.duration) * (1.0 - Double(episode.progress) / 100.0)
            : Double(episode.duration)

        return Button {
            playEpisode(episode, feed: feed)
        } label: {
            HStack(spacing: 12) {
                // Square artwork with progress bar overlay
                ZStack(alignment: .bottom) {
                    if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                        CachedAsyncImage(url: url) { img in
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(width: 76, height: 76)
                                .clipped()
                        } placeholder: {
                            coverPlaceholder(width: 76, height: 76, title: feed.title)
                        }
                    } else {
                        coverPlaceholder(width: 76, height: 76, title: feed.title)
                    }

                    // Progress bar at bottom
                    if episode.progress > 0 {
                        GeometryReader { pGeo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.12))
                                Rectangle()
                                    .fill(AmberTheme.primaryAmber)
                                    .frame(width: pGeo.size.width * CGFloat(Double(episode.progress) / 100.0))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Info & control stack
                VStack(alignment: .leading, spacing: 4) {
                    // Show name
                    Text(feed.title)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AmberTheme.labelTertiary)
                        .lineLimit(1)

                    // Episode title (fixed 2 lines, highlighted when playing)
                    Text(episode.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isPlayingThis ? AmberTheme.primaryAmber : AmberTheme.labelPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Play capsule with remaining time
                    HStack(spacing: 5) {
                        Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(formatDuration(remaining))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10), in: Capsule())
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(width: width)
        }
        .buttonStyle(TactileButtonStyle(scale: 0.97))
    }

    // MARK: - 3. 我的播客 (Apple square cover shelf)
    @ViewBuilder
    private func subscribedChannelsShelf() -> some View {
        let posterSize: CGFloat = 132.0

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("我的播客")

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
                                Group {
                                    if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                                        CachedAsyncImage(url: url) { img in
                                            img
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: posterSize, height: posterSize)
                                                .clipped()
                                        } placeholder: {
                                            coverPlaceholder(width: posterSize, height: posterSize, title: feed.title)
                                        }
                                    } else {
                                        coverPlaceholder(width: posterSize, height: posterSize, title: feed.title)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                // Apple order: show name first, then genre/author
                                Text(feed.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AmberTheme.labelPrimary)
                                    .lineLimit(1)
                                    .frame(width: posterSize, alignment: .leading)

                                Text(podcastSubtitle(feed))
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(AmberTheme.labelTertiary)
                                    .lineLimit(1)
                                    .frame(width: posterSize, alignment: .leading)
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
            .scrollClipDisabled()
        }
    }

    // MARK: - 4. 为你推荐 (subscribed-state personalised shelf)

    /// Genre-matched, not-yet-subscribed candidates across all discover lists.
    /// Pure logic (no ViewBuilder), so guard/return stays legal here.
    private var forYouRecommendations: [PodcastFeed] {
        guard !feeds.isEmpty, let discover = discoverFeed else { return [] }

        // Build genre set from subscribed feeds (skip nil genres)
        let subscribedGenres = Set(feeds.compactMap { $0.genre?.lowercased() })
        // Subscribed titles for exclusion
        let subscribedTitles = Set(feeds.map { $0.title.lowercased() })

        // Collect candidate items across all discover lists
        var allItems: [PodcastFeed] = []
        allItems += discover.featured
        allItems += discover.topChinese
        allItems += discover.topGlobal
        if let cats = discover.categories {
            for cat in cats { allItems += cat.items }
        }

        // Filter: genre match + not already subscribed, deduplicate by title
        var seen = Set<String>()
        var recommended: [PodcastFeed] = []
        for item in allItems {
            let key = item.title.lowercased()
            guard !seen.contains(key), !subscribedTitles.contains(key) else { continue }
            if subscribedGenres.isEmpty {
                seen.insert(key)
                recommended.append(item)
            } else if let g = item.genre, subscribedGenres.contains(g.lowercased()) {
                seen.insert(key)
                recommended.append(item)
            }
            if recommended.count >= 12 { break }
        }
        return recommended
    }

    @ViewBuilder
    private func forYouShelf() -> some View {
        let recommended = forYouRecommendations
        if !recommended.isEmpty {
            // Shelf title: use first subscribed feed with a non-nil genre.
            // Single expressions only — ViewBuilder turns if/else assignment
            // branches into Void, which does not conform to View.
            let firstGenreFeed = feeds.first(where: { $0.genre != nil && !($0.genre!.isEmpty) })
            let shelfTitle = firstGenreFeed.map { "因为你收听《\($0.title)》" } ?? "为你推荐"

            let cardSize: CGFloat = 132.0

            VStack(alignment: .leading, spacing: 16) {
                Text(shelfTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .padding(.horizontal, AmberTheme.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(recommended) { feed in
                            NavigationLink(destination: FeedDetailView(feed: feed)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Group {
                                        if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                                            CachedAsyncImage(url: url) { img in
                                                img
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: cardSize, height: cardSize)
                                                    .clipped()
                                            } placeholder: {
                                                coverPlaceholder(width: cardSize, height: cardSize, title: feed.title)
                                            }
                                        } else {
                                            coverPlaceholder(width: cardSize, height: cardSize, title: feed.title)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    // Apple order: show name first, then genre/author
                                    Text(feed.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                        .lineLimit(1)
                                        .frame(width: cardSize, alignment: .leading)

                                    Text(podcastSubtitle(feed))
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(AmberTheme.labelTertiary)
                                        .lineLimit(1)
                                        .frame(width: cardSize, alignment: .leading)
                                }
                            }
                            .buttonStyle(TactileButtonStyle(scale: 0.97))
                        }
                    }
                    .padding(.horizontal, AmberTheme.pageMargin)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Empty State: recommendation shelves
    //
    // With no subscriptions the hero has nothing to headline, so it is gone and
    // the screen becomes recommendation-first: square-poster shelves, two per
    // page, each with a "查看全部" entry into a category grid.
    private var emptyStateView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AmberScrollTopProbe()
                welcomeHeader

                if let discover = discoverFeed {
                    recommendationShelf(title: "编辑精选", items: discover.featured)
                        .padding(.top, 28)

                    if let categories = discover.categories, !categories.isEmpty {
                        ForEach(categories) { category in
                            recommendationShelf(title: category.name, items: category.items)
                                .padding(.top, 28)
                        }
                    } else {
                        // Older backend without genre shelves: fall back to the charts.
                        recommendationShelf(title: "热门中文", items: discover.topChinese)
                            .padding(.top, 28)
                        recommendationShelf(title: "热门全球", items: discover.topGlobal)
                            .padding(.top, 28)
                    }
                } else if isLoadingDiscover {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 64)
                }

                Color.clear.frame(height: 168)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No .ignoresSafeArea(edges: .top) here: the empty state has no
        // full-bleed hero, and letting the scroll view run under the status bar
        // made an upward overscroll flash the background above the content.
        // bounce only when the content actually overflows, so a short page
        // never rubber-bands past its own top edge.
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .amberScrollObservable(tab: 0)
        .task { await loadDiscover() }
    }

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("开始你的播客之旅")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)

            Text("订阅喜欢的节目，或从下面的推荐开始")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AmberTheme.labelSecondary)

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
            .padding(.top, 6)
        }
        .padding(.horizontal, AmberTheme.pageMargin)
        .padding(.top, 32)
    }

    /// A category shelf: square posters, two per page, with a "查看全部" entry.
    @ViewBuilder
    private func recommendationShelf(title: String, items: [PodcastFeed]) -> some View {
        let gap: CGFloat = 12
        let cardWidth = (screenWidth - AmberTheme.pageMargin * 2 - gap) / 2
        let cardHeight = cardWidth   // square artwork

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)

                    Spacer()

                    NavigationLink(destination: CategoryGridView(title: title, items: items)) {
                        HStack(spacing: 3) {
                            Text("查看全部")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(AmberTheme.labelSecondary)
                    }
                }
                .padding(.horizontal, AmberTheme.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: gap) {
                        ForEach(items) { feed in
                            NavigationLink(destination: FeedDetailView(feed: feed)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack(alignment: .bottomTrailing) {
                                        if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                                            CachedAsyncImage(url: url) { img in
                                                img
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: cardWidth, height: cardHeight)
                                                    .clipped()
                                            } placeholder: {
                                                coverPlaceholder(width: cardWidth, height: cardHeight, title: feed.title)
                                            }
                                        } else {
                                            coverPlaceholder(width: cardWidth, height: cardHeight, title: feed.title)
                                        }

                                        Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "Apple")
                                            .font(.system(size: 8.5, weight: .regular))
                                            .foregroundStyle(Color.white.opacity(0.85))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                                            .padding(6)
                                    }
                                    .frame(width: cardWidth, height: cardHeight)
                                    .amberMediaCard(radius: 20)

                                    Text(feed.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(width: cardWidth, alignment: .leading)

                                    Text(feed.author)
                                        .font(.system(size: 11.5, weight: .regular))
                                        .foregroundStyle(AmberTheme.labelTertiary)
                                        .lineLimit(1)
                                        .frame(width: cardWidth, alignment: .leading)
                                }
                            }
                            .buttonStyle(TactileButtonStyle(scale: 0.97))
                        }
                    }
                    .padding(.horizontal, AmberTheme.pageMargin)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
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
        let hero = Self.heroPair(feeds: lib.feeds, heroEpisode: lib.heroEpisode)
        self.heroFeed = hero.0
        self.heroEpisode = hero.1
        self.isLoading = false
    }

    private func saveToCache(feeds: [PodcastFeed], recentEpisodes: [Episode], heroEpisode: Episode?) {
        let lib = AmberAPIClient.LibraryResponse(feeds: feeds, recentEpisodes: recentEpisodes, heroEpisode: heroEpisode)
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

        // Kick off discover fetch for both subscribed and empty states (shared)
        await loadDiscover()

        do {
            let lib = try await AmberAPIClient.shared.fetchLibrary()
            await MainActor.run {
                if lib.feeds.isEmpty {
                    #if DEBUG
                    self.feeds = PodcastFeed.samples
                    self.recentEpisodes = Episode.samples
                    let hero = Self.heroPair(feeds: PodcastFeed.samples, heroEpisode: Episode.samples.first)
                    self.heroFeed = hero.0
                    self.heroEpisode = hero.1
                    #else
                    self.feeds = []
                    self.recentEpisodes = []
                    self.heroFeed = nil
                    self.heroEpisode = nil
                    #endif
                } else {
                    self.feeds = lib.feeds
                    self.recentEpisodes = lib.recentEpisodes
                    let hero = Self.heroPair(feeds: lib.feeds, heroEpisode: lib.heroEpisode)
                    self.heroFeed = hero.0
                    self.heroEpisode = hero.1
                    self.saveToCache(feeds: lib.feeds, recentEpisodes: lib.recentEpisodes, heroEpisode: lib.heroEpisode)
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

    /// Recommendation shelves for the empty state. Fetched once per appearance;
    /// failures are non-fatal — the header and subscribe button stay usable.
    private func loadDiscover() async {
        guard discoverFeed == nil, !isLoadingDiscover else { return }
        isLoadingDiscover = true
        do {
            let feed = try await AmberAPIClient.shared.fetchDiscoverFeed()
            await MainActor.run {
                self.discoverFeed = feed
                self.isLoadingDiscover = false
            }
        } catch {
            await MainActor.run { self.isLoadingDiscover = false }
        }
    }

    private func playEpisode(_ episode: Episode, feed: PodcastFeed) {
        impactFeedback.impactOccurred()
        if player.currentEpisode?.id == episode.id {
            if player.isPlaying {
                player.pause()
            } else if player.fullMapping.isEmpty {
                Task { await player.playNewEpisode(episode: episode, feed: feed) }
            } else {
                player.play()
            }
        } else {
            Task { await player.playNewEpisode(episode: episode, feed: feed) }
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

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes) min"
    }

    /// Apple "Title ›" section header language.
    private func sectionTitle(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AmberTheme.labelTertiary)
        }
    }

    private func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Apple card second line: genre when known, else the author, else nothing.
    private func podcastSubtitle(_ feed: PodcastFeed) -> String {
        if let g = feed.genre, !g.isEmpty { return g }
        return feed.author
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
