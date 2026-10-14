import SwiftUI

public struct FeedDetailView: View {
    public let feed: PodcastFeed
    @State private var episodes: [Episode] = []
    @State private var isLoading: Bool = true
    @State private var autoTranslate: Bool

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
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(AmberTheme.primaryAmber)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(AmberTheme.primaryAmber.opacity(0.15), in: Capsule())
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    // 3. Episode Cards Stack
                    LazyVStack(spacing: 12) {
                        ForEach(episodes) { ep in
                            EpisodeRowView(episode: ep, feed: feed)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 120) // Clearance for floating mini player
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
                if let url = URL(string: feed.coverUrl), !feed.coverUrl.isEmpty {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 108, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: AmberTheme.radiusCoverHero, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AmberTheme.radiusCoverHero, style: .continuous)
                                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(white: 0.12))
                            .frame(width: 108, height: 108)
                    }
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
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(AmberTheme.primaryAmber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .liquidGlassCapsule(tint: AmberTheme.primaryAmber)

                        if autoTranslate {
                            Text("已开启自动双轨")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(AmberTheme.accentElectric)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .liquidGlassCapsule(tint: AmberTheme.accentElectric)
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
