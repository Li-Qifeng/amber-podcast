import SwiftUI

public struct SearchView: View {
    @State private var query: String = ""
    @State private var searchResults: [PodcastFeed] = []
    @State private var isSearching: Bool = false
    @State private var subscribingId: String? = nil
    @State private var subscribedIds: Set<String> = []

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 1. Forward-Style Frosted Search Input Field
                    searchBarHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 14)

                    // 2. Results or Suggestions
                    if isSearching {
                        VStack(spacing: 14) {
                            ProgressView()
                                .scaleEffect(1.1)
                            Text("正在检索 Apple 播客全网目录...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AmberTheme.labelSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if searchResults.isEmpty {
                        suggestionsOrEmptyView
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 12) {
                                ForEach(searchResults) { item in
                                    searchResultCard(item: item)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 120) // Clearance for floating MiniPlayer
                        }
                    }
                }
            }
            .navigationTitle("发现播客")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Search Bar Header
    private var searchBarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AmberTheme.primaryAmber)

            TextField("搜索全网播客 (如 Huberman Lab / 商业 / 科技)...", text: $query)
                .font(.system(size: 14, weight: .regular))
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
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AmberTheme.cardSurfaceElevated)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AmberTheme.borderSpecular, lineWidth: 0.5))
        )
    }

    // MARK: - Forward / Rex Style Search Result Card
    private func searchResultCard(item: PodcastFeed) -> some View {
        HStack(spacing: 14) {
            // Squircle Cover Artwork with Drop Shadow
            if let url = URL(string: item.coverUrl), !item.coverUrl.isEmpty {
                AsyncImage(url: url) { img in
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 6, y: 3)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(white: 0.12))
                        .frame(width: 60, height: 60)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .lineLimit(1)

                Text(item.author)
                    .font(.system(size: 12, weight: .medium))
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

            // Subscribe Button Capsule
            Button {
                subscribeItem(item)
            } label: {
                if subscribingId == item.id {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 58, height: 28)
                } else if subscribedIds.contains(item.id) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("已订阅")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AmberTheme.accentElectric)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AmberTheme.accentElectric.opacity(0.12), in: Capsule())
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("订阅")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5.5)
                    .background(AmberTheme.primaryAmber, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(subscribingId == item.id || subscribedIds.contains(item.id))
            .amberPressable(scale: 0.94)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AmberTheme.cardSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
    }

    // MARK: - Suggestions or Empty View
    private var suggestionsOrEmptyView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AmberTheme.primaryAmber.opacity(0.1))
                    .frame(width: 76, height: 76)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AmberTheme.primaryAmber)
            }

            VStack(spacing: 6) {
                Text("直连 Apple 播客官方目录")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Text("输入节目名称或主播，一键订阅并享受双轨配音")
                    .font(.system(size: 13))
                    .foregroundStyle(AmberTheme.labelTertiary)
            }

            // Quick discovery suggestion chips
            VStack(spacing: 10) {
                Text("热门海外精选")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AmberTheme.labelTertiary)

                HStack(spacing: 8) {
                    suggestionChip("Huberman Lab")
                    suggestionChip("Lex Fridman")
                    suggestionChip("All-In")
                }

                HStack(spacing: 8) {
                    suggestionChip("The Daily")
                    suggestionChip("NPR News")
                    suggestionChip("Hard Fork")
                }
            }
            .padding(.top, 12)

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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07), in: Capsule())
                .overlay(Capsule().stroke(AmberTheme.borderSpecular, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .amberPressable(scale: 0.95)
    }

    // MARK: - Actions
    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }

        isSearching = true
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
                await MainActor.run {
                    self.subscribedIds.insert(item.id)
                    self.subscribingId = nil
                }
            } catch {
                await MainActor.run {
                    self.subscribingId = nil
                }
            }
        }
    }
}
