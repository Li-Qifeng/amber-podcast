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

                            // 3. 你可能错过了 (Apple "You May Have Missed" paged group)
                            youMayHaveMissedShelf()
                                .padding(.top, 28)

                            // 4. 我的播客
                            subscribedChannelsShelf()
                                .padding(.top, 28)

                            // 5. 新节目推荐 (Apple "New Shows for You" adaptive tint card)
                            newShowsForYouShelf()
                                .padding(.top, 28)

                            // 6. 试试这些频道 (Apple "Channels to Try" tall card)
                            channelsToTryShelf()
                                .padding(.top, 28)

                            // 7. 探索更多 (Apple "More to Discover" dual-row grid)
                            moreToDiscoverShelf()
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
            let cardWidth = screenWidth * 0.76

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

    // MARK: - Unified Apple-Pattern Hero Card (Shared by 最新单集 / 新节目推荐 / 试试这些频道)
    /// A single self-contained dark container card. Passes `episode` for a dynamic
    /// Apple expanding play capsule with sound wave and progress bar, or `nil` for a "查看节目" affordance.
    private func unifiedHeroCard(
        feed: PodcastFeed,
        episode: Episode? = nil,
        badgeText: String? = nil,
        cardWidth: CGFloat
    ) -> some View {
        let artworkHeight = cardWidth * 0.68
        let isCurrent = episode.map { player.currentEpisode?.id == $0.id } ?? false
        let isPlayingThis = isCurrent && player.isPlaying
        let liveProgress = isCurrent && player.duration > 0
            ? (player.currentTime / player.duration)
            : (episode.map { Double($0.progress) / 100.0 } ?? 0.0)
        let titleText = episode?.title ?? feed.title
        let synopsis = episode.map { stripHTML($0.shownotes) } ?? stripHTML(feed.description)
        let badge = badgeText ?? (episode != nil ? "最新单集" : (feed.id.isEmpty ? "" : "节目"))

        return VStack(alignment: .leading, spacing: 0) {
            // Wide artwork flush to the container's top edge
            NavigationLink(destination: FeedDetailView(feed: feed)) {
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

                    // Live progress bar along the artwork's bottom edge
                    if liveProgress > 0 {
                        GeometryReader { pGeo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.12))
                                Rectangle()
                                    .fill(AmberTheme.primaryAmber)
                                    .frame(width: pGeo.size.width * CGFloat(liveProgress))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .frame(width: cardWidth, height: artworkHeight)
                .clipped()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                // Section badge
                if !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AmberTheme.primaryAmber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(AmberTheme.primaryAmber.opacity(0.12), in: Capsule())
                }

                NavigationLink(destination: FeedDetailView(feed: feed)) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Card title
                        Text(titleText)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(isCurrent ? AmberTheme.primaryAmber : AmberTheme.labelPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if !synopsis.isEmpty {
                            Text(synopsis)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AmberTheme.labelSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                // Bottom action capsule: Apple expanding play capsule for episodes, view for shows
                HStack {
                    if let ep = episode {
                        AppleExpandingPlayCapsule(
                            isPlaying: isPlayingThis,
                            isCurrent: isCurrent,
                            progress: liveProgress,
                            durationText: formatDuration(Double(ep.duration)),
                            tintColor: AmberTheme.primaryAmber
                        ) {
                            playEpisode(ep, feed: feed)
                        }
                    } else {
                        NavigationLink(destination: FeedDetailView(feed: feed)) {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                Text("查看节目")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(AmberNavCapsuleButtonStyle())
                    }

                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(width: cardWidth)
        .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func latestEpisodeCard(episode: Episode, feed: PodcastFeed, cardWidth: CGFloat) -> some View {
        unifiedHeroCard(feed: feed, episode: episode, badgeText: "最新单集", cardWidth: cardWidth)
    }

    private func coverPlaceholder(width: CGFloat, height: CGFloat, title: String) -> some View {
        // Soft brand-grey "loading" plate — a near-black block reads as a
        // missing image on tinted pages, so keep it light and quiet.
        ZStack {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AmberTheme.surfaceRaised, AmberTheme.surfaceRaised.opacity(0.72)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            VStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: min(width, height) * 0.22, weight: .light))
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

    // MARK: - 2. 继续收听 (same transparent row language as 你可能错过了)
    @ViewBuilder
    private func continueListeningShelf() -> some View {
        let rows = recentEpisodes
        if !rows.isEmpty {
            let pageWidth = screenWidth * 0.86

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    sectionTitle("继续收听")

                    Spacer()

                    Text("最新 \(rows.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
                .padding(.horizontal, AmberTheme.pageMargin)

                // One row per page, horizontally paged — same row component
                // and peek behaviour as the "You May Have Missed" group.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(rows) { ep in
                            missedRow(episode: ep)
                                .frame(width: pageWidth)
                        }
                    }
                    .padding(.horizontal, AmberTheme.pageMargin)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .frame(height: 100)
            }
        }
    }

    // MARK: - 3. 我的播客 (Apple square cover shelf: 2 full columns + hairline peek of 3rd)
    @ViewBuilder
    private func subscribedChannelsShelf() -> some View {
        let peekWidth: CGFloat = 22.0
        let spacing: CGFloat = 12.0
        let margin: CGFloat = AmberTheme.pageMargin
        let posterSize: CGFloat = round((screenWidth - margin - 2 * spacing - peekWidth) / 2.0)

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
                LazyHStack(spacing: spacing) {
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
                                .frame(width: posterSize, height: posterSize)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

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

    /// Apple "You May Have Missed": followed shows, not yet finished.
    private var missedEpisodes: [Episode] {
        Array(recentEpisodes.filter { $0.progress < 100 }.prefix(15))
    }

    /// Apple "New Shows for You": the head of the genre-matched pool.
    private var newShowsForYou: [PodcastFeed] {
        Array(forYouRecommendations.prefix(6))
    }

    /// Apple "More to Discover": the rest of the pool (dual-row grid).
    private var moreToDiscover: [PodcastFeed] {
        Array(forYouRecommendations.dropFirst(6).prefix(12))
    }

    /// Apple "Channels to Try": editorial features not yet subscribed. The
    /// featured pool is tiny (4), so top_global and top_chinese top up the mix
    /// — otherwise the shelf can end up empty (or coverless) for active users.
    private var channelsToTry: [PodcastFeed] {
        guard let discover = discoverFeed else { return [] }
        let subscribedTitles = Set(feeds.map { $0.title.lowercased() })
        var seen = Set<String>()
        var result: [PodcastFeed] = []
        for item in discover.featured + discover.topGlobal + discover.topChinese {
            let key = item.title.lowercased()
            if seen.contains(key) || subscribedTitles.contains(key) { continue }
            seen.insert(key)
            result.append(item)
            if result.count >= 8 { break }
        }
        return result
    }

    // MARK: - 3. 你可能错过了 (Apple "You May Have Missed" paged group)
    @ViewBuilder
    private func youMayHaveMissedShelf() -> some View {
        let missed = missedEpisodes
        if !missed.isEmpty {
            let pages = stride(from: 0, to: missed.count, by: 3).map {
                Array(missed[$0..<min($0 + 3, missed.count)])
            }
            // Page slightly narrower than the viewport so the next column peeks
            // in and advertises the horizontal swipe.
            let pageWidth = screenWidth * 0.86

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    sectionTitle("你可能错过了")
                    Text("来自你关注的节目")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
                .padding(.horizontal, AmberTheme.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(pages.indices, id: \.self) { pi in
                            VStack(spacing: 0) {
                                ForEach(pages[pi].indices, id: \.self) { ei in
                                    missedRow(episode: pages[pi][ei])
                                    if ei < pages[pi].count - 1 {
                                        Divider()
                                            .background(Color.white.opacity(0.10))
                                            .padding(.leading, 104)
                                    }
                                }
                            }
                            .frame(width: pageWidth)
                        }
                    }
                    .padding(.horizontal, AmberTheme.pageMargin)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .frame(height: 3 * 100)
            }
        }
    }

    private func missedRowLeftContent(episode: Episode, feed: PodcastFeed?, isCurrent: Bool) -> some View {
        HStack(spacing: 14) {
            // Square artwork
            ZStack(alignment: .bottom) {
                if let f = feed, let url = URL(string: f.proxiedCoverUrl), !f.proxiedCoverUrl.isEmpty {
                    CachedAsyncImage(url: url) { img in
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipped()
                    } placeholder: {
                        coverPlaceholder(width: 80, height: 80, title: f.title)
                    }
                } else {
                    coverPlaceholder(width: 80, height: 80, title: feed?.title ?? "")
                }

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
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                // Localized date line (e.g. 11月12日)
                Text(Self.localizedDate(episode.pubDate))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AmberTheme.labelTertiary)

                // Episode title (fixed 2 lines)
                Text(episode.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isCurrent ? AmberTheme.primaryAmber : AmberTheme.labelPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private func missedRow(episode: Episode) -> some View {
        let feed = feeds.first(where: { $0.id == episode.feedId })
        let isCurrent = player.currentEpisode?.id == episode.id
        let isPlayingThis = isCurrent && player.isPlaying
        let liveProgress = isCurrent && player.duration > 0
            ? (player.currentTime / player.duration)
            : Double(episode.progress) / 100.0
        let remaining = episode.progress > 0
            ? Double(episode.duration) * (1.0 - Double(episode.progress) / 100.0)
            : Double(episode.duration)

        return HStack(spacing: 12) {
            // Tapping artwork or title navigates to channel
            Group {
                if let f = feed {
                    NavigationLink(destination: FeedDetailView(feed: f)) {
                        missedRowLeftContent(episode: episode, feed: f, isCurrent: isCurrent)
                    }
                    .buttonStyle(.plain)
                } else {
                    missedRowLeftContent(episode: episode, feed: nil, isCurrent: isCurrent)
                }
            }

            // Right action column: independent tactile play capsule with equalizer & progress bar + menu
            VStack(alignment: .trailing, spacing: 6) {
                AppleExpandingPlayCapsule(
                    isPlaying: isPlayingThis,
                    isCurrent: isCurrent,
                    progress: liveProgress,
                    durationText: formatDuration(remaining),
                    tintColor: AmberTheme.primaryAmber
                ) {
                    if let f = feed {
                        playEpisode(episode, feed: f)
                    }
                }

                Menu {
                    Button {
                        if let f = feed { UIPasteboard.general.string = f.feedUrl }
                    } label: {
                        Label("复制节目链接", systemImage: "link")
                    }
                    ShareLink(item: episode.audioUrl) {
                        Label("分享单集音频", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AmberTheme.labelTertiary)
                        .frame(width: 30, height: 26)
                        .contentShape(Rectangle())
                }
            }
        }
        .frame(height: 100)
    }

    // MARK: - 5. 新节目推荐 (Apple Large Control - Unified Hero Card)
    @ViewBuilder
    private func newShowsForYouShelf() -> some View {
        let shows = newShowsForYou
        if !shows.isEmpty {
            let cardWidth = screenWidth * 0.76

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    sectionTitle("新节目推荐")
                    Text("根据你的收听偏好")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
                .padding(.horizontal, AmberTheme.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: AmberTheme.cardGap) {
                        ForEach(shows) { feed in
                            unifiedHeroCard(feed: feed, episode: nil, badgeText: "新节目推荐", cardWidth: cardWidth)
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

    // MARK: - 6. 试试这些频道 (Apple Large Control - Unified Hero Card)
    @ViewBuilder
    private func channelsToTryShelf() -> some View {
        let channels = channelsToTry
        if !channels.isEmpty {
            let cardWidth = screenWidth * 0.76

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    sectionTitle("试试这些频道")
                    Text("编辑精选")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
                .padding(.horizontal, AmberTheme.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: AmberTheme.cardGap) {
                        ForEach(channels) { feed in
                            unifiedHeroCard(feed: feed, episode: nil, badgeText: "推荐频道", cardWidth: cardWidth)
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

    // MARK: - 7. 探索更多 (Apple "More to Discover" grid — same row language as 你可能错过了)
    @ViewBuilder
    private func moreToDiscoverShelf() -> some View {
        let items = moreToDiscover
        if items.count >= 3 {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    sectionTitle("探索更多")
                    Text("根据你的收听偏好")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
                .padding(.horizontal, AmberTheme.pageMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: [
                        GridItem(.fixed(70), spacing: 10),
                        GridItem(.fixed(70), spacing: 10),
                        GridItem(.fixed(70)),
                    ], spacing: 12) {
                        ForEach(items) { feed in
                            miniPodcastRow(feed: feed)
                        }
                    }
                    .padding(.horizontal, AmberTheme.pageMargin)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .frame(height: 3 * 70 + 20)
            }
        }
    }

    private func miniPodcastRow(feed: PodcastFeed) -> some View {
        NavigationLink(destination: FeedDetailView(feed: feed)) {
            HStack(spacing: 14) {
                if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                    CachedAsyncImage(url: url) { img in
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipped()
                    } placeholder: {
                        coverPlaceholder(width: 56, height: 56, title: feed.title)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    coverPlaceholder(width: 56, height: 56, title: feed.title)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(feed.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(podcastSubtitle(feed))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AmberTheme.labelTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button {
                        UIPasteboard.general.string = feed.feedUrl
                    } label: {
                        Label("复制节目链接", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AmberTheme.labelTertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }
            .frame(width: 240, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle(scale: 0.97))
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

    /// "2026-11-12" → "11月12日" (locale-following via date template).
    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func localizedDate(_ s: String) -> String {
        guard let d = isoDayFormatter.date(from: s) else { return s }
        let out = DateFormatter()
        out.setLocalizedDateFormatFromTemplate("MMMd")
        out.locale = Locale(identifier: "zh_CN")
        return out.string(from: d)
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
