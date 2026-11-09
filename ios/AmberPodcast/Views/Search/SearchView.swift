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

    // Discovery feed data (Apple Podcasts Style)
    @State private var featuredShows: [PodcastFeed] = []
    @State private var topChineseShows: [PodcastFeed] = []
    @State private var topGlobalShows: [PodcastFeed] = []
    @State private var isDiscoverLoading: Bool = false

    @AppStorage("amber_recent_searches_v1") private var recentSearchesRaw: String = ""
    @AppStorage("amber_cached_discover_json_v1") private var cachedDiscoverJson: String = ""
    @Environment(\.isDockCollapsed) private var isDockCollapsed: Binding<Bool>

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {
        if let raw = UserDefaults.standard.string(forKey: "amber_cached_discover_json_v1"),
           let data = raw.data(using: .utf8),
           let res = try? JSONDecoder().decode(AmberAPIClient.DiscoverFeedResponse.self, from: data) {
            self._featuredShows = State(initialValue: res.featured)
            self._topChineseShows = State(initialValue: res.topChinese)
            self._topGlobalShows = State(initialValue: res.topGlobal)
            self._isDiscoverLoading = State(initialValue: false)
        }
    }

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

                Group {
                    // Results or Apple Podcasts Discovery Feed
                    if isSearching {
                        VStack(spacing: 14) {
                            ProgressView()
                                .scaleEffect(1.1)
                            Text("正在检索 Apple 播客全网目录...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AmberTheme.labelSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if hasSearched && !query.isEmpty && searchResults.isEmpty {
                        noResultsView
                    } else if !searchResults.isEmpty && !query.isEmpty {
                        // Search Results List
                        searchResultsList
                    } else {
                        // Apple Podcasts Style Discovery Stream
                        discoveryStreamView
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    stickySearchGlassHeader
                }
            }
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                restoreDiscoverFromCache()
            }
            .task {
                await loadExistingSubscriptions()
                await loadDiscoverFeed()
            }
            .refreshable {
                await loadDiscoverFeed()
                await loadExistingSubscriptions()
            }
            .alert("提示", isPresented: $showErrorAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "操作完成")
            }
        }
    }

    // MARK: - Sticky Liquid Glass Search Header
    private var stickySearchGlassHeader: some View {
        VStack(spacing: 6) {
            searchBarHeader
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)

            if isUrlQuery {
                directUrlBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background(
            Rectangle()
                .fill(AmberTheme.background.opacity(0.82))
                .background(.ultraThinMaterial)
                .overlay(
                    Divider().background(AmberTheme.borderHairline.opacity(0.5)),
                    alignment: .bottom
                )
        )
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
        .liquidGlassCapsule()
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

    // MARK: - Search Results List
    private var searchResultsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(searchResults) { item in
                    let isSub = isItemSubscribed(item)
                    if let existing = subscribedFeeds.first(where: {
                        (!item.feedUrl.isEmpty && $0.feedUrl == item.feedUrl) || $0.id == item.id
                    }) {
                        NavigationLink(destination: FeedDetailView(feed: existing)) {
                            searchResultCard(item: item, isSubscribed: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: FeedDetailView(feed: item)) {
                            searchResultCard(item: item, isSubscribed: isSub)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 140)
            .trackScrollDirection(isCollapsed: isDockCollapsed)
        }
        .amberScrollSpace()
    }

    // MARK: - Apple Podcasts Style Discovery Stream
    private var discoveryStreamView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                // 1. Featured Editorial Banners Carousel
                if !featuredShows.isEmpty {
                    featuredCarouselSection
                }

                // 2. Search History (if available)
                if !recentSearches.isEmpty {
                    searchHistorySection
                }

                // 3. Top Chinese Podcasts Section
                if !topChineseShows.isEmpty {
                    topChineseSection
                }

                // 4. Top Global Dual-Track Section
                if !topGlobalShows.isEmpty {
                    topGlobalSection
                }

                // 5. Categorized Topic Chips
                categoryChipsSection

                Spacer(minLength: 120)
            }
            .padding(.top, 6)
            .trackScrollDirection(isCollapsed: isDockCollapsed)
        }
        .amberScrollSpace()
    }

    // MARK: - Section 1: Featured Carousel
    private var featuredCarouselSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AmberTheme.primaryAmber)
                Text("精彩聚焦")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelSecondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(featuredShows) { item in
                        NavigationLink(destination: FeedDetailView(feed: item)) {
                            featuredCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func featuredCard(item: PodcastFeed) -> some View {
        let isSub = isItemSubscribed(item)
        return VStack(alignment: .leading, spacing: 10) {
            // Tag Pill
            HStack {
                Text(item.editorialTag ?? "编辑精选")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.primaryAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AmberTheme.primaryAmber.opacity(0.12), in: Capsule())

                Spacer()

                // Subscribe Mini Button
                Button {
                    if !isSub {
                        subscribeItem(item)
                    }
                } label: {
                    if subscribingId == item.id {
                        ProgressView().scaleEffect(0.5).frame(width: 48, height: 22)
                    } else if isSub {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                            Text("已订阅").font(.system(size: 10.5, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(AmberTheme.accentElectric)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(AmberTheme.accentElectric.opacity(0.12), in: Capsule())
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                            Text("订阅").font(.system(size: 10.5, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Color.white, in: Capsule())
                    }
                }
                .buttonStyle(TactileButtonStyle(scale: 0.94))
                .disabled(subscribingId == item.id || isSub)
            }

            HStack(spacing: 12) {
                // Cover Artwork
                if let url = URL(string: item.proxiedCoverUrl), !item.proxiedCoverUrl.isEmpty {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                            .frame(width: 58, height: 58)
                            .amberMediaCard(radius: 12)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.15))
                            .frame(width: 58, height: 58)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .lineLimit(1)

                    Text(item.author)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AmberTheme.labelSecondary)
                        .lineLimit(1)

                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(AmberTheme.labelTertiary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
        .amberPlate(radius: 16)
        .contentShape(Rectangle())
    }

    // MARK: - Section 2: Search History
    private var searchHistorySection: some View {
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
            .padding(.horizontal, 20)

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
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Section 3: Top Chinese Shows
    private var topChineseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.orange)
                Text("中文热门精选")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(topChineseShows) { item in
                        NavigationLink(destination: FeedDetailView(feed: item)) {
                            posterCard(item: item, badge: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Section 4: Top Global Dual-Track Shows
    private var topGlobalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AmberTheme.accentElectric)
                Text("全球双语焦点")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Text("双轨译制")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.accentElectric)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AmberTheme.accentElectric.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(topGlobalShows) { item in
                        NavigationLink(destination: FeedDetailView(feed: item)) {
                            posterCard(item: item, badge: "双轨配音")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func posterCard(item: PodcastFeed, badge: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let url = URL(string: item.proxiedCoverUrl), !item.proxiedCoverUrl.isEmpty {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                            .frame(width: 120, height: 120)
                            .amberMediaCard(radius: 12)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.14))
                            .frame(width: 120, height: 120)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.14))
                        .frame(width: 120, height: 120)
                }

                if let b = badge {
                    Text(b)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(AmberTheme.primaryAmber, in: Capsule())
                        .padding(6)
                }
            }

            Text(item.title)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)
                .lineLimit(1)

            Text(item.author)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AmberTheme.labelTertiary)
                .lineLimit(1)
        }
        .frame(width: 120)
        .contentShape(Rectangle())
    }

    // MARK: - Section 5: Category Topic Chips
    private var categoryChipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("热门分类专题")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)
                .padding(.horizontal, 20)

            FlowLayout(spacing: 8) {
                topicPill("深度对谈", queryText: "声东击西")
                topicPill("科技前沿", queryText: "机核")
                topicPill("商业商业", queryText: "Acquired")
                topicPill("文学艺术", queryText: "跳岛 FM")
                topicPill("健康科学", queryText: "Huberman Lab")
                topicPill("人工智能", queryText: "Lex Fridman")
            }
            .padding(.horizontal, 20)
        }
    }

    private func topicPill(_ title: String, queryText: String) -> some View {
        Button {
            query = queryText
            performSearch()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AmberTheme.labelSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(AmberTheme.labelTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .amberPlate(radius: 8)
        }
        .buttonStyle(TactileButtonStyle(scale: 0.96))
    }

    // MARK: - Search Result Card
    private func searchResultCard(item: PodcastFeed, isSubscribed: Bool) -> some View {
        HStack(spacing: 12) {
            if let url = URL(string: item.proxiedCoverUrl), !item.proxiedCoverUrl.isEmpty {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
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

            Button {
                if !isSubscribed {
                    subscribeItem(item)
                }
            } label: {
                if subscribingId == item.id {
                    ProgressView().scaleEffect(0.60).frame(width: 54, height: 26)
                } else if isSubscribed {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        Text("已订阅").font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(AmberTheme.accentElectric)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(AmberTheme.accentElectric.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                        Text("订阅").font(.system(size: 11, weight: .medium, design: .rounded))
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
        .contentShape(Rectangle())
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
            }
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Actions
    private func isItemSubscribed(_ item: PodcastFeed) -> Bool {
        subscribedIds.contains(item.id) || (!item.feedUrl.isEmpty && subscribedFeedUrls.contains(item.feedUrl))
    }

    private func loadExistingSubscriptions() async {
        if let feeds = try? await AmberAPIClient.shared.listFeeds() {
            await MainActor.run {
                self.subscribedFeeds = feeds
                self.subscribedIds = Set(feeds.map { $0.id })
                self.subscribedFeedUrls = Set(feeds.map { $0.feedUrl })
            }
        }
    }

    private func restoreDiscoverFromCache() {
        guard featuredShows.isEmpty, !cachedDiscoverJson.isEmpty,
              let data = cachedDiscoverJson.data(using: .utf8),
              let res = try? JSONDecoder().decode(AmberAPIClient.DiscoverFeedResponse.self, from: data) else {
            return
        }
        self.featuredShows = res.featured
        self.topChineseShows = res.topChinese
        self.topGlobalShows = res.topGlobal
        self.isDiscoverLoading = false
    }

    private func saveDiscoverToCache(res: AmberAPIClient.DiscoverFeedResponse) {
        if let data = try? JSONEncoder().encode(res), let str = String(data: data, encoding: .utf8) {
            cachedDiscoverJson = str
        }
    }

    private func loadDiscoverFeed() async {
        if featuredShows.isEmpty {
            restoreDiscoverFromCache()
            if featuredShows.isEmpty {
                isDiscoverLoading = true
            }
        }

        do {
            let res = try await AmberAPIClient.shared.fetchDiscoverFeed()
            await MainActor.run {
                self.featuredShows = res.featured
                self.topChineseShows = res.topChinese
                self.topGlobalShows = res.topGlobal
                self.isDiscoverLoading = false
                self.saveDiscoverToCache(res: res)
            }
        } catch {
            await MainActor.run {
                if self.featuredShows.isEmpty {
                    self.restoreDiscoverFromCache()
                }
                self.isDiscoverLoading = false
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
