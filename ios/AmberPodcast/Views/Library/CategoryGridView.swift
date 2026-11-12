import SwiftUI

/// Full listing for one recommendation shelf — reached from the "查看全部"
/// button on the home empty state. Square posters in a two-column grid.
public struct CategoryGridView: View {
    let title: String
    let items: [PodcastFeed]

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    public init(title: String, items: [PodcastFeed]) {
        self.title = title
        self.items = items
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(items) { feed in
                    NavigationLink(destination: FeedDetailView(feed: feed)) {
                        posterCell(feed)
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.97))
                }
            }
            .padding(.horizontal, AmberTheme.pageMargin)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(AmberTheme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func posterCell(_ feed: PodcastFeed) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                            CachedAsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                fallback(feed)
                            }
                        } else {
                            fallback(feed)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "Apple")
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(6)
            }

            Text(feed.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AmberTheme.labelPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(feed.author)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AmberTheme.labelTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fallback(_ feed: PodcastFeed) -> some View {
        ZStack {
            AmberTheme.surfaceCard
            Text(String(feed.title.prefix(1)))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AmberTheme.labelTertiary)
        }
    }
}
