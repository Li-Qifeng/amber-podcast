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
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                feedHeader

                Divider()
                    .padding(.horizontal, 20)

                // Episode List
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("单集列表")
                            .font(.title3.bold())
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("\(episodes.count) 集")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)

                    LazyVStack(spacing: 0) {
                        ForEach(episodes) { ep in
                            EpisodeRowView(episode: ep, feed: feed)
                                .padding(.horizontal, 20)
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
            }
            .padding(.bottom, 120) // Leave clearance for floating mini player
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadEpisodes()
        }
        .refreshable {
            await loadEpisodes()
        }
    }

    // MARK: - Feed Header
    private var feedHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                // Cover Artwork
                if let url = URL(string: feed.coverUrl), !feed.coverUrl.isEmpty {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 104, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 104, height: 104)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.title)
                        .font(.title3.bold())
                        .lineLimit(2)

                    Text(feed.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "Apple 播客")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())

                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Description
            if !feed.description.isEmpty {
                Text(feed.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 20)
            }
        }
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
