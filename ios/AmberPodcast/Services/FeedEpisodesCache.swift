import Foundation

/// Persistent disk + memory cache for Feed episode lists to provide instant display
/// and seamless background updates with animated insertions.
public final class FeedEpisodesCache {
    public static let shared = FeedEpisodesCache()

    private let memoryCache = NSCache<NSString, NSArray>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let baseDir = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDirectory = baseDir.appendingPathComponent("AmberFeedCache", isDirectory: true)

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(for feedId: String) -> URL {
        let safeName = feedId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? feedId
        return cacheDirectory.appendingPathComponent("\(safeName).json")
    }

    public func getCachedEpisodes(feedId: String) -> [Episode]? {
        // 1. Try Memory Cache
        if let mem = memoryCache.object(forKey: feedId as NSString) as? [Episode] {
            return mem
        }

        // 2. Try Disk Cache
        let url = fileURL(for: feedId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let episodes = try? JSONDecoder().decode([Episode].self, from: data) else {
            return nil
        }

        // Populate Memory Cache
        memoryCache.setObject(episodes as NSArray, forKey: feedId as NSString)
        return episodes
    }

    public func saveEpisodes(_ episodes: [Episode], for feedId: String) {
        memoryCache.setObject(episodes as NSArray, forKey: feedId as NSString)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let url = self.fileURL(for: feedId)
            if let data = try? JSONEncoder().encode(episodes) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
