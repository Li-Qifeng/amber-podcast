import SwiftUI

public struct SearchView: View {
    @State private var query: String = ""
    @State private var searchResults: [PodcastFeed] = []
    @State private var isSearching: Bool = false
    @State private var hasSearched: Bool = false
    @State private var subscribingId: String? = nil
    @State private var isSubscribingUrl: Bool = false
    @State private var subscribedFeeds: [PodcastFeed] = []
    @State private var subscribedIds: Set<String> = []
    @State private var subscribedFeedUrls: Set<String> = []
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false

    @AppStorage("amber_recent_searches_v1") private var recentSearchesRaw: String = ""

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    private var isUrlQuery: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    private var recentSearches: [String] {
        recentSearchesRaw
            .split(separator: "|||")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 1. Search Input Field
                    searchBarHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                    // 2. Direct Link Banner (when URL pasted)
                    if isUrlQuery {
                        directUrlBanner
                    }

                    // 3. Results or Suggestions
                    if isSearching {
                        VStack(spacing: 14) {
                            ProgressView()
                                .scaleEffect(1.1)
                            Text("正在检索 Apple 播客全网目录...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AmberTheme.labelSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if hasSearched && searchResults.isEmpty {
                        noResultsView
                    } else if searchResults.isEmpty {
                        suggestionsOrEmptyView
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 12) {
                                ForEach(searchResults) { item in
                                    if let existing = subscribedFeeds.first(where: {
                                        (!item.feedUrl.isEmpty && $0.feedUrl == item.feedUrl) || $0.id == item.id
                                    }) {
                                        NavigationLink(destination: FeedDetailView(feed: existing)) {
                                            searchResultCard(item: item, isSubscribed: true)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        searchResultCard(item: item, isSubscribed: false)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 140) // Clearance for floating MiniPlayer
                        }
                    }
                }
            }
            .navigationTitle("发现播客")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadExistingSubscriptions()
            }
            .alert("提示", isPresented: $showErrorAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "操作完成")
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Search Bar Header
    private var searchBarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AmberTheme.primaryAmber)

            TextField("搜索全网播客、主播或粘贴 RSS / 小宇宙链接...", text: $query)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(AmberTheme.labelPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    performSearch()
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    searchResults = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .amberPlate(radius: 10)
    }

    // MARK: - Direct URL Banner
    private var directUrlBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AmberTheme.primaryAmber)

            VStack(alignment: .leading, spacing: 2) {
                Text("识别到播客订阅链接")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Text(query.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                subscribeDirectUrl(query.trimmingCharacters(in: .whitespaces))
            } label: {
                if isSubscribingUrl {
                    ProgressView().scaleEffect(0.6)
                        .frame(width: 58, height: 26)
                } else {
                    Text("直接订阅")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .buttonStyle(TactileButtonStyle(scale: 0.96))
            .disabled(isSubscribingUrl)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .amberPlate(radius: 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Search Result Card
    private func searchResultCard(item: PodcastFeed, isSubscribed: Bool) -> some View {
        HStack(spacing: 12) {
            // Squircle Cover Artwork
            if let url = URL(string: item.coverUrl), !item.coverUrl.isEmpty {
                AsyncImage(url: url) { img in
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .amberMediaCard(radius: 10)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(white: 0.12))
                        .frame(width: 52, height: 52)
                }
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.12))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(AmberTheme.labelTertiary)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .lineLimit(1)

                Text(item.author)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(AmberTheme.labelSecondary)
                    .lineLimit(1)

                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AmberTheme.labelTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Subscribe Button
            Button {
                if !isSubscribed {
                    subscribeItem(item)
                }
            } label: {
                if subscribingId == item.id {
                    ProgressView()
                        .scaleEffect(0.60)
                        .frame(width: 54, height: 26)
                } else if isSubscribed {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("已订阅")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(AmberTheme.accentElectric)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(AmberTheme.accentElectric.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("订阅")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4.5)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .buttonStyle(TactileButtonStyle(scale: 0.96))
            .disabled(subscribingId == item.id || isSubscribed)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .amberPlate(radius: 12)
    }

    // MARK: - Suggestions or Empty View
    private var suggestionsOrEmptyView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                // Recent Searches (if any)
                if !recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("搜索历史")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AmberTheme.labelSecondary)
                            Spacer()
                            Button {
                                clearRecentSearches()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AmberTheme.labelTertiary)
                            }
                        }

                        FlowLayout(spacing: 8) {
                            ForEach(recentSearches, id: \.self) { term in
                                Button {
                                    query = term
                                    performSearch()
                                } label: {
                                    Text(term)
                                        .font(.system(size: 11.5, weight: .regular))
                                        .foregroundStyle(AmberTheme.labelSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(TactileButtonStyle(scale: 0.96))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                // Curated Categories & Shows
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("直连 Apple 播客全网目录")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AmberTheme.labelPrimary)

                        Text("输入节目名称或主播，一键订阅并享受双轨译音")
                            .font(.system(size: 12))
                            .foregroundStyle(AmberTheme.labelTertiary)
                    }

                    // Discovery suggestion chips (Bilingual)
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("深度对话 · 叙事")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AmberTheme.labelTertiary)
                            HStack(spacing: 8) {
                                suggestionChip("声东击西")
                                suggestionChip("忽左忽右")
                                suggestionChip("跳岛 FM")
                                suggestionChip("Huberman Lab")
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("科技 · AI · 商业")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AmberTheme.labelTertiary)
                            HStack(spacing: 8) {
                                suggestionChip("机核")
                                suggestionChip("硅谷高徒")
                                suggestionChip("All-In")
                                suggestionChip("Lex Fridman")
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("商业观察 · 国际新闻")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AmberTheme.labelTertiary)
                            HStack(spacing: 8) {
                                suggestionChip("商业就是这样")
                                suggestionChip("The Daily")
                                suggestionChip("Hard Fork")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, recentSearches.isEmpty ? 24 : 8)

                Spacer(minLength: 120)
            }
        }
    }

    // MARK: - No Results View
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AmberTheme.labelTertiary)

            VStack(spacing: 6) {
                Text("未找到相关播客")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Text("请尝试更换搜索关键词，或检查拼写")
                    .font(.system(size: 13))
                    .foregroundStyle(AmberTheme.labelTertiary)
            }

            Button {
                query = ""
                hasSearched = false
            } label: {
                Text("清空重试")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(AmberTheme.primaryAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(AmberTheme.borderHairline, lineWidth: 0.5)
                    )
            }
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            query = text
            performSearch()
        } label: {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AmberTheme.labelSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5.5)
                .amberPlate(radius: 6)
        }
        .buttonStyle(TactileButtonStyle(scale: 0.96))
    }

    // MARK: - Actions
    private func loadExistingSubscriptions() async {
        if let feeds = try? await AmberAPIClient.shared.listFeeds() {
            await MainActor.run {
                self.subscribedFeeds = feeds
                self.subscribedIds = Set(feeds.map { $0.id })
                self.subscribedFeedUrls = Set(feeds.map { $0.feedUrl })
            }
        }
    }

    private func saveRecentSearch(_ term: String) {
        let clean = term.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !isUrlQuery else { return }
        var current = recentSearches.filter { $0.lowercased() != clean.lowercased() }
        current.insert(clean, at: 0)
        if current.count > 8 {
            current = Array(current.prefix(8))
        }
        recentSearchesRaw = current.joined(separator: "|||")
    }

    private func clearRecentSearches() {
        recentSearchesRaw = ""
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }

        if isUrlQuery {
            subscribeDirectUrl(q)
            return
        }

        saveRecentSearch(q)
        isSearching = true
        hasSearched = true
        searchResults = []
        impactFeedback.impactOccurred()

        Task {
            do {
                let results = try await AmberAPIClient.shared.searchPodcasts(query: q)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.isSearching = false
                    self.errorMessage = "检索失败，请检查网关连接或网络配置"
                    self.showErrorAlert = true
                }
            }
        }
    }

    private func subscribeItem(_ item: PodcastFeed) {
        subscribingId = item.id
        impactFeedback.impactOccurred()

        Task {
            do {
                try await AmberAPIClient.shared.subscribe(url: item.feedUrl, autoTranslate: false)
                await loadExistingSubscriptions()
                await MainActor.run {
                    self.subscribedIds.insert(item.id)
                    self.subscribedFeedUrls.insert(item.feedUrl)
                    self.subscribingId = nil
                }
            } catch {
                await MainActor.run {
                    self.subscribingId = nil
                    self.errorMessage = "订阅失败: \(error.localizedDescription)"
                    self.showErrorAlert = true
                }
            }
        }
    }

    private func subscribeDirectUrl(_ url: String) {
        guard !url.isEmpty else { return }
        isSubscribingUrl = true
        impactFeedback.impactOccurred()

        Task {
            do {
                try await AmberAPIClient.shared.subscribe(url: url, autoTranslate: false)
                await loadExistingSubscriptions()
                await MainActor.run {
                    self.isSubscribingUrl = false
                    self.query = ""
                    self.errorMessage = "订阅成功！已同步至媒体库。"
                    self.showErrorAlert = true
                }
            } catch {
                await MainActor.run {
                    self.isSubscribingUrl = false
                    self.errorMessage = "订阅失败: \(error.localizedDescription)"
                    self.showErrorAlert = true
                }
            }
        }
    }
}

// Simple FlowLayout helper for tags
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowMaxH: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowMaxH + spacing
                rowMaxH = 0
            }
            x += size.width + spacing
            rowMaxH = max(rowMaxH, size.height)
        }
        height = y + rowMaxH
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowMaxH: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowMaxH + spacing
                rowMaxH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowMaxH = max(rowMaxH, size.height)
        }
    }
}
