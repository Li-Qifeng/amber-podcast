import SwiftUI

public struct HomeLibraryView: View {
    @State private var feeds: [PodcastFeed] = []
    @State private var isLoading: Bool = true
    @State private var showSubscribeSheet: Bool = false
    @State private var newUrlInput: String = ""
    @State private var newAutoTranslate: Bool = false
    @State private var isSubscribing: Bool = false
    @State private var errorMessage: String? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 180), spacing: 16)
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading && feeds.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("正在同步资料库...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else if feeds.isEmpty {
                        emptyStateView
                    } else {
                        // Podcast Grid
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(feeds) { feed in
                                NavigationLink(destination: FeedDetailView(feed: feed)) {
                                    feedCard(feed: feed)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteFeed(feed)
                                    } label: {
                                        Label("取消订阅", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                }
                .padding(.bottom, 120) // Space for floating mini player
            }
            .navigationTitle("资料库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSubscribeSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                    }
                }
            }
            .sheet(isPresented: $showSubscribeSheet) {
                subscribeSheet
            }
            .task {
                await loadFeeds()
            }
            .refreshable {
                await loadFeeds()
            }
        }
    }

    // MARK: - Feed Card
    private func feedCard(feed: PodcastFeed) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let url = URL(string: feed.coverUrl), !feed.coverUrl.isEmpty {
                    AsyncImage(url: url) { img in
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 156, minHeight: 156)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(1, contentMode: .fit)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(Image(systemName: "mic.fill").font(.title).foregroundStyle(.white))
                }

                // Source badge
                Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "RSS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .padding(8)
            }

            Text(feed.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Text(feed.author)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "headphones.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("资料库暂无播客")
                .font(.title3.bold())

            Text("点击右上角 ＋ 粘贴 Apple Podcasts 或小宇宙链接，或前往发现页搜索订阅")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button {
                showSubscribeSheet = true
            } label: {
                Text("添加首个播客")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Subscribe Sheet
    private var subscribeSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("播客链接")) {
                    TextField("粘贴 RSS 订阅源或小宇宙单集/播客链接", text: $newUrlInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Toggle("自动 AI 双轨转译新单集", isOn: $newAutoTranslate)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        submitSubscription()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubscribing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isSubscribing ? "正在解析添加..." : "确认订阅")
                                .bold()
                            Spacer()
                        }
                    }
                    .disabled(newUrlInput.trimmingCharacters(in: .whitespaces).isEmpty || isSubscribing)
                }
            }
            .navigationTitle("添加播客")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showSubscribeSheet = false
                        errorMessage = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Network Operations
    private func loadFeeds() async {
        isLoading = true
        do {
            let fetched = try await AmberAPIClient.shared.listFeeds()
            await MainActor.run {
                self.feeds = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func submitSubscription() {
        let url = newUrlInput.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }

        isSubscribing = true
        errorMessage = nil

        Task {
            do {
                try await AmberAPIClient.shared.subscribe(url: url, autoTranslate: newAutoTranslate)
                await loadFeeds()
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

    private func deleteFeed(_ feed: PodcastFeed) {
        Task {
            try? await AmberAPIClient.shared.deleteFeed(feedId: feed.id)
            await loadFeeds()
        }
    }
}
