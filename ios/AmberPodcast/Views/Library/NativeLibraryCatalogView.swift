import SwiftUI

public struct NativeLibraryCatalogView: View {
    @ObservedObject private var store = LibraryStore.shared
    @ObservedObject private var player = DualTrackAudioPlayer.shared
    @State private var showSubscribeSheet = false
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        AmberScrollTopProbe()

                        // Quick Action Sections
                        VStack(spacing: 0) {
                            NavigationLink {
                                FeedListView()
                            } label: {
                                HStack {
                                    Label {
                                        Text("节目")
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(AmberTheme.labelPrimary)
                                    } icon: {
                                        Image(systemName: "square.stack.fill")
                                            .foregroundStyle(AmberTheme.primaryAmber)
                                    }
                                    Spacer()
                                    Text("\(store.feeds.count)")
                                        .font(.system(size: 15))
                                        .foregroundStyle(AmberTheme.labelSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AmberTheme.labelTertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }

                            Divider().background(AmberTheme.borderHairline).padding(.leading, 50)

                            NavigationLink {
                                LatestEpisodesListView(episodes: store.recentEpisodes, feeds: store.feeds)
                            } label: {
                                HStack {
                                    Label {
                                        Text("最新单集")
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(AmberTheme.labelPrimary)
                                    } icon: {
                                        Image(systemName: "sparkles")
                                            .foregroundStyle(AmberTheme.primaryAmber)
                                    }
                                    Spacer()
                                    Text("\(store.recentEpisodes.count)")
                                        .font(.system(size: 15))
                                        .foregroundStyle(AmberTheme.labelSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AmberTheme.labelTertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }

                            Divider().background(AmberTheme.borderHairline).padding(.leading, 50)

                            NavigationLink {
                                DownloadedEpisodesListView()
                            } label: {
                                HStack {
                                    Label {
                                        Text("已下载")
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(AmberTheme.labelPrimary)
                                    } icon: {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(AmberTheme.primaryAmber)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AmberTheme.labelTertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                        }
                        .background(AmberTheme.surfaceCard.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)

                        // Downloaded & Followed Channels
                        if !store.feeds.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("关注的播客")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AmberTheme.labelSecondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 20)

                                VStack(spacing: 0) {
                                    ForEach(Array(store.feeds.enumerated()), id: \.element.id) { index, feed in
                                        NavigationLink {
                                            FeedDetailView(feed: feed)
                                        } label: {
                                            HStack(spacing: 12) {
                                                if !feed.proxiedCoverUrl.isEmpty, let url = URL(string: feed.proxiedCoverUrl) {
                                                    CachedAsyncImage(url: url) { image in
                                                        image.resizable().aspectRatio(contentMode: .fill)
                                                    } placeholder: {
                                                        Color(white: 0.15)
                                                    }
                                                    .frame(width: 44, height: 44)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                } else {
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(Color(white: 0.15))
                                                        .frame(width: 44, height: 44)
                                                        .overlay(
                                                            Image(systemName: "waveform")
                                                                .foregroundColor(AmberTheme.labelTertiary)
                                                        )
                                                }

                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(feed.title)
                                                        .font(.system(size: 15, weight: .semibold))
                                                        .foregroundStyle(AmberTheme.labelPrimary)
                                                        .lineLimit(1)

                                                    Text(feed.author)
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(AmberTheme.labelSecondary)
                                                        .lineLimit(1)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(AmberTheme.labelTertiary)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                        }

                                        if index < store.feeds.count - 1 {
                                            Divider().background(AmberTheme.borderHairline).padding(.leading, 72)
                                        }
                                    }
                                }
                                .background(AmberTheme.surfaceCard.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(.horizontal, 16)
                            }
                        }

                        // Bottom clearance for Dock
                        Color.clear.frame(height: 140)
                    }
                    .padding(.top, 12)
                }
                .scrollBounceBehavior(.always, axes: .vertical)
                .amberScrollObservable(tab: 1)
            }
            .navigationTitle("资料库")
            .navigationBarTitleDisplayMode(.large)
            .amberImmersiveTopEdge()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CircularLiquidGlassAddButton {
                        showSubscribeSheet = true
                    }
                }
            }
            .sheet(isPresented: $showSubscribeSheet) {
                SubscribeSheet(onSubscribed: { _ in
                    Task { await store.loadData() }
                })
            }
            .task {
                await store.loadData()
            }
        }
    }
}

// MARK: - Subscribed Feeds List
public struct FeedListView: View {
    @ObservedObject private var store = LibraryStore.shared

    public init() {}

    public var body: some View {
        ZStack {
            AmberTheme.background.ignoresSafeArea()
            if store.feeds.isEmpty {
                Text("暂无订阅节目")
                    .foregroundColor(AmberTheme.labelTertiary)
            } else {
                List(store.feeds) { feed in
                    NavigationLink {
                        FeedDetailView(feed: feed)
                    } label: {
                        HStack(spacing: 12) {
                            if !feed.proxiedCoverUrl.isEmpty, let url = URL(string: feed.proxiedCoverUrl) {
                                CachedAsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color(white: 0.15)
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(white: 0.15))
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Image(systemName: "waveform")
                                            .foregroundColor(AmberTheme.labelTertiary)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(feed.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AmberTheme.labelPrimary)
                                    .lineLimit(1)

                                Text(feed.author)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AmberTheme.labelSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("节目")
    }
}

// MARK: - Latest Episodes List
public struct LatestEpisodesListView: View {
    public let episodes: [Episode]
    public let feeds: [PodcastFeed]
    @ObservedObject private var player = DualTrackAudioPlayer.shared

    public init(episodes: [Episode], feeds: [PodcastFeed]) {
        self.episodes = episodes
        self.feeds = feeds
    }

    public var body: some View {
        ZStack {
            AmberTheme.background.ignoresSafeArea()
            if episodes.isEmpty {
                Text("暂无新单集")
                    .foregroundColor(AmberTheme.labelTertiary)
            } else {
                List(episodes) { ep in
                    episodeRow(ep)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("最新单集")
    }

    @ViewBuilder
    private func episodeRow(_ ep: Episode) -> some View {
        let f = feeds.first(where: { $0.id == ep.feedId })
        let podcastTitle = f?.title ?? "未知"
        Button {
            if let f = f {
                Task { await player.playNewEpisode(episode: ep, feed: f) }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ep.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .lineLimit(2)
                    Text("\(podcastTitle) · \(ep.formattedDuration)")
                        .font(.system(size: 12))
                        .foregroundStyle(AmberTheme.labelSecondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AmberTheme.primaryAmber)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Downloaded Episodes List
public struct DownloadedEpisodesListView: View {
    public init() {}

    public var body: some View {
        ZStack {
            AmberTheme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AmberTheme.labelTertiary)
                Text("暂无下载内容")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
                Text("已下载供离线收听的单集将显示在这里")
                    .font(.system(size: 13))
                    .foregroundStyle(AmberTheme.labelTertiary)
            }
        }
        .navigationTitle("已下载")
    }
}
