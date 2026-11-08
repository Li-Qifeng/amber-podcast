import Foundation
import SwiftUI

public struct LibraryView: View {
    @State private var feeds: [PodcastFeed] = []
    @State private var isLoading: Bool = true
    @State private var showSubscribeSheet: Bool = false
    @State private var newUrlInput: String = ""
    @State private var newAutoTranslate: Bool = false
    @State private var isSubscribing: Bool = false
    @State private var errorMessage: String? = nil

    @AppStorage("amber_cached_library_json_v2") private var cachedLibraryJson: String = ""
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {
        if let raw = UserDefaults.standard.string(forKey: "amber_cached_library_json_v2"),
           let data = raw.data(using: .utf8),
           let lib = try? JSONDecoder().decode(AmberAPIClient.LibraryResponse.self, from: data),
           !lib.feeds.isEmpty {
            self._feeds = State(initialValue: lib.feeds)
            self._isLoading = State(initialValue: false)
        }
    }

    public var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    AmberTheme.background.ignoresSafeArea()

                    if isLoading && feeds.isEmpty {
                        loadingStateView
                    } else if feeds.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 20) {
                                // Section Title & Stats
                                HStack(alignment: .firstTextBaseline) {
                                    Text("已订阅节目")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(AmberTheme.labelPrimary)

                                    Text("\(feeds.count) 个频道")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(AmberTheme.labelSecondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2.5)
                                        .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, max(geo.safeAreaInsets.top, 20) + 54)

                                // 2-Column Grid of Channels
                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 14),
                                        GridItem(.flexible(), spacing: 14)
                                    ],
                                    spacing: 16
                                ) {
                                    ForEach(feeds) { feed in
                                        NavigationLink(destination: FeedDetailView(feed: feed)) {
                                            channelGridCard(feed: feed)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)

                                // Bottom Clearance for floating Dock & MiniPlayer
                                Color.clear.frame(height: 168)
                            }
                        }
                    }

                    // Top Floating Header
                    topFloatingToolbar(geometry: geo)
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
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
            Text("载入资料库...")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AmberTheme.labelSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.fill")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(AmberTheme.labelTertiary)
                .padding(.top, 60)

            Text("资料库暂无播客")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)

            Text("轻触右上角「添加」粘贴 Apple 播客或小宇宙链接")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AmberTheme.labelTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top Floating Toolbar
    private func topFloatingToolbar(geometry: GeometryProxy) -> some View {
        let topSafeOffset = max(geometry.safeAreaInsets.top, 24)

        return VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("资料库")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Spacer()

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
                }
                .buttonStyle(AmberCapsuleNavigationButtonStyle())
            }
            .padding(.horizontal, AmberTheme.pageMargin)
            .padding(.top, topSafeOffset)

            Spacer()
        }
    }

    // MARK: - Channel Grid Card
    private func channelGridCard(feed: PodcastFeed) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let url = URL(string: feed.proxiedCoverUrl), !feed.proxiedCoverUrl.isEmpty {
                    AsyncImage(url: url) { img in
                        img
                            .resizable()
                            .scaledToFill()
                            .aspectRatio(1.0, contentMode: .fit)
                            .clipped()
                    } placeholder: {
                        coverPlaceholder(title: feed.title)
                    }
                } else {
                    coverPlaceholder(title: feed.title)
                }

                Text(feed.sourceType == "xiaoyuzhou" ? "小宇宙" : "Apple")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(6)
            }
            .aspectRatio(1.0, contentMode: .fit)
            .amberMediaCard(radius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .lineLimit(1)

                Text(feed.author.isEmpty ? "播客频道" : feed.author)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .lineLimit(1)
            }
        }
    }

    private func coverPlaceholder(title: String) -> some View {
        ZStack {
            Color(red: 0.10, green: 0.10, blue: 0.12)
            VStack(spacing: 6) {
                Image(systemName: "headphones")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AmberTheme.labelTertiary)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
        }
        .aspectRatio(1.0, contentMode: .fill)
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
                            .background(AmberTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(AmberTheme.danger)
                            .multilineTextAlignment(.leading)
                    }

                    Button {
                        subscribe()
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

    private func subscribe() {
        guard !newUrlInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSubscribing = true
        errorMessage = nil
        Task {
            do {
                _ = try await AmberAPIClient.shared.subscribeFeed(url: newUrlInput.trimmingCharacters(in: .whitespaces), autoTranslate: newAutoTranslate)
                await MainActor.run {
                    self.isSubscribing = false
                    self.showSubscribeSheet = false
                    self.newUrlInput = ""
                }
                await loadData()
            } catch {
                await MainActor.run {
                    self.isSubscribing = false
                    self.errorMessage = "订阅失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadData() async {
        do {
            let res = try await AmberAPIClient.shared.fetchLibrary()
            await MainActor.run {
                self.feeds = res.feeds
                self.isLoading = false
                let lib = AmberAPIClient.LibraryResponse(feeds: res.feeds, recentEpisodes: res.recentEpisodes)
                if let data = try? JSONEncoder().encode(lib), let str = String(data: data, encoding: .utf8) {
                    cachedLibraryJson = str
                }
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}
