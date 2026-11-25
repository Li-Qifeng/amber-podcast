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
    private let legacyCacheKey = "amber_cached_library_json_v1"

    private init() {
        restoreFromCache()
    }

    private static func heroPair(
        feeds: [PodcastFeed], heroEpisode: Episode?
    ) -> (PodcastFeed?, Episode?) {
        guard let ep = heroEpisode else { return (nil, nil) }
        return (feeds.first(where: { $0.id == ep.feedId }) ?? feeds.first, ep)
    }

    public func restoreFromCache() {
        if let raw = UserDefaults.standard.string(forKey: cacheKey),
           let data = raw.data(using: .utf8),
           let lib = try? JSONDecoder().decode(AmberAPIClient.LibraryResponse.self, from: data),
           !lib.feeds.isEmpty {
            self.feeds = lib.feeds
            self.recentEpisodes = lib.recentEpisodes
            let hero = Self.heroPair(feeds: lib.feeds, heroEpisode: lib.heroEpisode)
            self.heroFeed = hero.0
            self.heroEpisode = hero.1
        }
    }

    public func refresh() async {
        await loadData()
    }

    public func clearCache() {
        UserDefaults.standard.removeObject(forKey: legacyCacheKey)
        UserDefaults.standard.removeObject(forKey: cacheKey)
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
                let hero = Self.heroPair(feeds: PodcastFeed.samples, heroEpisode: Episode.samples.first)
                self.heroFeed = hero.0
                self.heroEpisode = hero.1
                #else
                self.feeds = []
                self.recentEpisodes = []
                self.heroFeed = nil
                self.heroEpisode = nil
                #endif
            } else {
                self.feeds = lib.feeds
                self.recentEpisodes = lib.recentEpisodes
                let hero = Self.heroPair(feeds: lib.feeds, heroEpisode: lib.heroEpisode)
                self.heroFeed = hero.0
                self.heroEpisode = hero.1
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

    public func subscribe(url: String, autoTranslate: Bool) async throws -> PodcastFeed? {
        try await AmberAPIClient.shared.subscribe(url: url, autoTranslate: autoTranslate)
        await loadData()
        return self.feeds.first(where: { $0.feedUrl == url })
    }

    public func deleteFeed(id: String) async throws {
        try await AmberAPIClient.shared.deleteFeed(feedId: id)
        await loadData()
    }
}
