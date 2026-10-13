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
            VStack(spacing: 0) {
                // Search Input Header
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("搜索 Apple 播客全网目录...", text: $query)
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
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)

                // Results or Suggestions
                if isSearching {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在检索 Apple 播客目录...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty {
                    suggestionsOrEmptyView
                } else {
                    List {
                        ForEach(searchResults) { item in
                            searchResultRow(item: item)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("搜索与发现")
            .navigationBarTitleDisplayMode(.large)
            .padding(.bottom, 60) // MiniPlayer clearance
        }
    }

    // MARK: - Search Result Row
    private func searchResultRow(item: PodcastFeed) -> some View {
        HStack(spacing: 14) {
            // Artwork
            if let url = URL(string: item.coverUrl), !item.coverUrl.isEmpty {
                AsyncImage(url: url) { img in
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 58, height: 58)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.author)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Subscribe Button
            Button {
                subscribeItem(item)
            } label: {
                if subscribingId == item.id {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 54, height: 28)
                } else if subscribedIds.contains(item.id) {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 54, height: 28)
                } else {
                    Text("订阅")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(subscribingId == item.id || subscribedIds.contains(item.id))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty / Suggestions View
    private var suggestionsOrEmptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("输入播客名称或主播名字")
                .font(.title3.bold())

            Text("支持直连检索 Apple Podcasts 官方全网目录\n例如: Huberman Lab, Lex Fridman, NPR")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
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
