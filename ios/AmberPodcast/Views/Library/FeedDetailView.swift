import SwiftUI

public struct FeedDetailView: View {
    public let feed: PodcastFeed
    @State private var episodes: [Episode] = []
    @State private var isLoading: Bool = true
    @State private var autoTranslate: Bool
    @State private var showDeleteConfirm: Bool = false
    @State private var isDeleting: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(feed: PodcastFeed) {
        self.feed = feed
        self._autoTranslate = State(initialValue: feed.autoTranslate == 1)
    }

    public var body: some View {
        ZStack {
            AmberTheme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    // 1. Forward-style Hero Banner
                    feedHeader

                    // 2. Section Header: Episodes Count
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
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(AmberTheme.labelSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(AmberTheme.borderHairline, lineWidth: 0.5)
                                )
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)

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
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("取消订阅此播客", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(AmberTheme.labelSecondary)
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
                        dismiss()
                    }
                }
            }
            Button("保留订阅", role: .cancel) {}
        } message: {
            Text("确定要取消订阅《\(feed.title)》吗？已转译的音频资源将不再保留。")
        }
        .task {
            await loadEpisodes()
        }
        .refreshable {
            await loadEpisodes()
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Forward / Rex Style Feed Header
    private var feedHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                // Large Squircle Cover Artwork with Drop Shadow
                if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 108, height: 108)
                            .amberMediaCard(radius: AmberTheme.radiusCoverHero)
                    } placeholder: {
                        coverPlaceholder(width: 108, height: 108)
                    }
                } else {
                    coverPlaceholder(width: 108, height: 108)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(feed.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .lineLimit(2)

                    Text(feed.author)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AmberTheme.labelSecondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "Apple 播客")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(AmberTheme.primaryAmber)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AmberTheme.primaryAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(AmberTheme.primaryAmber.opacity(0.25), lineWidth: 0.5)
                            )

                        if autoTranslate {
                            Text("已开启自动双轨")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(AmberTheme.accentElectric)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(AmberTheme.accentElectric.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(AmberTheme.accentElectric.opacity(0.25), lineWidth: 0.5)
                                )
                        }

                        Spacer()
                    }
                    .padding(.top, 4)
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
        .padding(.vertical, 8)
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

    private func loadEpisodes() async {
        isLoading = true
        do {
            let fetched = try await AmberAPIClient.shared.listEpisodes(feedId: feed.id)
            await MainActor.run {
                self.episodes = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}
