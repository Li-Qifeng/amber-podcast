import Foundation

public final class FeedEpisodesCache {
    private static let memCache = NSCache<NSString, NSArray>()
    private static let fileManager = FileManager.default

    private static var cacheDirectory: URL {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("FeedEpisodesCache", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(for feedId: String) -> URL {
        let safeKey = feedId.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDirectory.appendingPathComponent("\(safeKey).json")
    }

    public static func get(feedId: String) -> [Episode]? {
        let key = feedId as NSString
        if let cached = memCache.object(forKey: key) as? [Episode] {
            return cached
        }
        let url = fileURL(for: feedId)
        guard let data = try? Data(contentsOf: url),
              let episodes = try? JSONDecoder().decode([Episode].self, from: data) else {
            return nil
        }
        memCache.setObject(episodes as NSArray, forKey: key)
        return episodes
    }

    public static func set(feedId: String, episodes: [Episode]) {
        let key = feedId as NSString
        memCache.setObject(episodes as NSArray, forKey: key)
        DispatchQueue.global(qos: .background).async {
            let url = fileURL(for: feedId)
            if let data = try? JSONEncoder().encode(episodes) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
