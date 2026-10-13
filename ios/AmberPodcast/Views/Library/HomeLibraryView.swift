import SwiftUI

public struct HomeLibraryView: View {
    @State private var feeds: [PodcastFeed] = []
    @State private var isLoading: Bool = true
    @State private var showSubscribeSheet: Bool = false
    @State private var newUrlInput: String = ""
    @State private var newAutoTranslate: Bool = false
    @State private var isSubscribing: Bool = false
    @State private var errorMessage: String? = nil

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 180), spacing: 18)
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if isLoading && feeds.isEmpty {
                            VStack(spacing: 14) {
                                ProgressView()
                                    .scaleEffect(1.1)
                                Text("正在同步云端播客库...")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AmberTheme.labelSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 90)
                        } else if feeds.isEmpty {
                            emptyStateView
                        } else {
                            // Section Title with Count Badge
                            HStack(alignment: .firstTextBaseline) {
                                Text("订阅库")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(AmberTheme.labelPrimary)

                                Text("\(feeds.count)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(AmberTheme.primaryAmber)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(AmberTheme.primaryAmber.opacity(0.15), in: Capsule())

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                            // Podcast Squircle Grid
                            LazyVGrid(columns: columns, spacing: 22) {
                                ForEach(feeds) { feed in
                                    NavigationLink(destination: FeedDetailView(feed: feed)) {
                                        feedCard(feed: feed)
                                    }
                                    .buttonStyle(.plain)
                                    .amberPressable(scale: 0.95)
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
                        }
                    }
                    .padding(.bottom, 120) // Space for floating mini player
                }
            }
            .navigationTitle("Amber 播客")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        impactFeedback.impactOccurred()
                        showSubscribeSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1), in: Circle())
                            .overlay(Circle().stroke(AmberTheme.borderSpecular, lineWidth: 0.5))
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
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Forward / Rex Style Feed Card
    private func feedCard(feed: PodcastFeed) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                // Squircle Artwork with Ambient Drop Shadow
                if let url = URL(string: feed.coverUrl), !feed.coverUrl.isEmpty {
                    AsyncImage(url: url) { img in
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 156, minHeight: 156)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(white: 0.12))
                            .aspectRatio(1, contentMode: .fit)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(white: 0.12))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(Image(systemName: "headphones").font(.title).foregroundStyle(AmberTheme.labelSecondary))
                }

                // Frosted Source Badge
                Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "Apple 播客")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                    .padding(8)
            }

            Text(feed.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(AmberTheme.labelPrimary)

            Text(feed.author)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(AmberTheme.labelTertiary)
        }
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AmberTheme.primaryAmber.opacity(0.12))
                    .frame(width: 88, height: 88)

                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(AmberTheme.primaryAmber)
            }
            .padding(.top, 40)

            Text("订阅库空空如也")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)

            Text("轻触右上角 ＋ 粘贴 Apple Podcasts 或小宇宙链接，或前往发现页搜索全网节目")
                .font(.system(size: 13.5))
                .foregroundStyle(AmberTheme.labelTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showSubscribeSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("添加首个播客")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(AmberTheme.primaryAmber, in: Capsule())
                .foregroundStyle(Color.black)
                .shadow(color: AmberTheme.primaryAmber.opacity(0.25), radius: 8, y: 3)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Subscribe Sheet
    private var subscribeSheet: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("播客 RSS / 链接")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AmberTheme.labelTertiary)

                        TextField("粘贴 RSS 订阅源或小宇宙单集/播客链接", text: $newUrlInput)
                            .font(.system(size: 14))
                            .padding(14)
                            .background(AmberTheme.cardSurfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AmberTheme.borderSpecular, lineWidth: 0.5))
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Toggle(isOn: $newAutoTranslate) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动 AI 双轨转译")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(AmberTheme.labelPrimary)
                            Text("新单集入库后自动生成中文配音、逐词字幕与精读笔记")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AmberTheme.labelTertiary)
                        }
                    }
                    .tint(AmberTheme.primaryAmber)
                    .padding(14)
                    .background(AmberTheme.cardSurfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AmberTheme.borderSpecular, lineWidth: 0.5))

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()

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
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(AmberTheme.primaryAmber, in: Capsule())
                        .foregroundStyle(Color.black)
                    }
                    .disabled(newUrlInput.trimmingCharacters(in: .whitespaces).isEmpty || isSubscribing)
                    .opacity(newUrlInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
                }
                .padding(20)
            }
            .navigationTitle("添加播客")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showSubscribeSheet = false
                        errorMessage = nil
                    }
                    .foregroundStyle(AmberTheme.labelSecondary)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
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
