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

                List {
                    // Quick Action Sections
                    Section {
                        NavigationLink {
                            FeedListView()
                        } label: {
                            Label {
                                HStack {
                                    Text("节目")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                    Spacer()
                                    Text("\(store.feeds.count)")
                                        .font(.system(size: 15))
                                        .foregroundStyle(AmberTheme.labelSecondary)
                                }
                            } icon: {
                                Image(systemName: "square.stack.fill")
                                    .foregroundStyle(AmberTheme.primaryAmber)
                            }
                        }

                        NavigationLink {
                            LatestEpisodesListView(episodes: store.recentEpisodes, feeds: store.feeds)
                        } label: {
                            Label {
                                HStack {
                                    Text("最新单集")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                    Spacer()
                                    Text("\(store.recentEpisodes.count)")
                                        .font(.system(size: 15))
                                        .foregroundStyle(AmberTheme.labelSecondary)
                                }
                            } icon: {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(AmberTheme.primaryAmber)
                            }
                        }

                        NavigationLink {
                            DownloadedEpisodesListView()
                        } label: {
                            Label {
                                Text("已下载")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(AmberTheme.labelPrimary)
                            } icon: {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(AmberTheme.primaryAmber)
                            }
                        }
                    }
                    .listRowBackground(AmberTheme.surfaceDark.opacity(0.85))

                    // Downloaded & Followed Channels
                    if !store.feeds.isEmpty {
                        Section("关注的播客") {
                            ForEach(store.feeds) { feed in
                                NavigationLink {
                                    FeedDetailView(feed: feed)
                                } label: {
                                    HStack(spacing: 12) {
                                        if let coverUrl = feed.coverUrl, let url = URL(string: coverUrl) {
                                            AsyncImage(url: url) { phase in
                                                if let image = phase.image {
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } else {
                                                    Color(white: 0.15)
                                                }
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
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .listRowBackground(AmberTheme.surfaceDark.opacity(0.85))
                    }

                    // Bottom clearance for Dock
                    Color.clear
                        .frame(height: 120)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("资料库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSubscribeSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text("添加")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .liquidGlassCapsule()
                    }
                    .buttonStyle(AmberNavCapsuleButtonStyle())
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

// Sub-list views for Library sections
public struct LatestEpisodesListView: View {
    public let episodes: [Episode]
    public let feeds: [PodcastFeed]
    @ObservedObject private var player = DualTrackAudioPlayer.shared

    public var body: some View {
        ZStack {
            AmberTheme.background.ignoresSafeArea()
            if episodes.isEmpty {
                Text("暂无新单集")
                    .foregroundColor(AmberTheme.labelTertiary)
            } else {
                List(episodes) { ep in
                    let f = feeds.first(where: { $0.id == ep.feedId })
                    Button {
                        if let f = f {
                            player.loadEpisode(episode: ep, feed: f, autoPlay: true)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ep.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(AmberTheme.labelPrimary)
                                    .lineLimit(2)
                                let podcastTitle = f?.title ?? "未知"
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
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("最新单集")
    }
}

public struct DownloadedEpisodesListView: View {
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
