import Foundation
import SwiftUI

@MainActor
public final class LibraryStore: ObservableObject {
    public static let shared = LibraryStore()

    @Published public var feeds: [PodcastFeed] = []
    @Published public var recentEpisodes: [Episode] = []
    @Published public var heroFeed: PodcastFeed? = nil
    @Published public var heroEpisode: Episode? = nil
    @Published public var isLoading: Bool = false

    private let cacheKey = "amber_cached_library_json_v2"

    private init() {
        restoreFromCache()
    }

    public func restoreFromCache() {
        if let raw = UserDefaults.standard.string(forKey: cacheKey),
           let data = raw.data(using: .utf8),
           let lib = try? JSONDecoder().decode(AmberAPIClient.LibraryResponse.self, from: data),
           !lib.feeds.isEmpty {
            self.feeds = lib.feeds
            self.recentEpisodes = lib.recentEpisodes
            self.heroFeed = lib.feeds.first
            self.heroEpisode = lib.recentEpisodes.first
        }
    }

    public func loadData() async {
        if feeds.isEmpty {
            restoreFromCache()
            if feeds.isEmpty {
                isLoading = true
            }
        }

        do {
            let lib = try await AmberAPIClient.shared.fetchLibrary()
            if lib.feeds.isEmpty {
                #if DEBUG
                self.feeds = PodcastFeed.samples
                self.recentEpisodes = Episode.samples
                self.heroFeed = PodcastFeed.samples.first
                self.heroEpisode = Episode.samples.first
                #else
                self.feeds = []
                self.recentEpisodes = []
                self.heroFeed = nil
                self.heroEpisode = nil
                #endif
            } else {
                self.feeds = lib.feeds
                self.recentEpisodes = lib.recentEpisodes
                self.heroFeed = lib.feeds.first
                self.heroEpisode = lib.recentEpisodes.first
                if let data = try? JSONEncoder().encode(lib), let str = String(data: data, encoding: .utf8) {
                    UserDefaults.standard.set(str, forKey: cacheKey)
                }
            }
            self.isLoading = false
        } catch {
            if self.feeds.isEmpty {
                self.restoreFromCache()
            }
            self.isLoading = false
        }
    }

    public func subscribe(url: String, autoTranslate: Bool) async throws -> PodcastFeed {
        let feed = try await AmberAPIClient.shared.subscribe(url: url, autoTranslate: autoTranslate)
        await loadData()
        return feed
    }

    public func deleteFeed(id: String) async throws {
        try await AmberAPIClient.shared.deleteFeed(feedId: id)
        await loadData()
    }
}
