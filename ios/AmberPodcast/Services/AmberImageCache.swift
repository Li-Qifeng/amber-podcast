import SwiftUI
import UIKit
import CommonCrypto

/// High-performance two-tier image cache (L1 Memory NSCache + L2 Sandbox Disk Cache)
public final class AmberImageCache {
    public static let shared = AmberImageCache()

    private let memCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let diskCacheDir: URL

    private init() {
        memCache.countLimit = 300 // up to 300 images in memory
        memCache.totalCostLimit = 80 * 1024 * 1024 // 80 MB memory budget

        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        diskCacheDir = paths[0].appendingPathComponent("AmberImageCache", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    private func diskKey(for url: URL) -> String {
        let str = url.absoluteString
        guard let data = str.data(using: .utf8) else { return "\(str.hash).jpg" }
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ = data.withUnsafeBytes {
            CC_MD5($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    public func image(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        // 1. Check L1 Memory (0ms Instant Hit)
        if let memImg = memCache.object(forKey: key) {
            return memImg
        }

        // 2. Check L2 Disk Persistent Cache (<5ms)
        let filePath = diskCacheDir.appendingPathComponent(diskKey(for: url))
        if let data = try? Data(contentsOf: filePath), let diskImg = UIImage(data: data) {
            memCache.setObject(diskImg, forKey: key, cost: data.count)
            return diskImg
        }

        return nil
    }

    public func store(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        guard let data = image.jpegData(compressionQuality: 0.90) else { return }

        // Store to L1 Memory
        memCache.setObject(image, forKey: key, cost: data.count)

        // Store to L2 Sandbox Disk asynchronously
        let filePath = diskCacheDir.appendingPathComponent(diskKey(for: url))
        DispatchQueue.global(qos: .background).async {
            try? data.write(to: filePath, options: .atomic)
        }
    }

    public func clearAll() {
        memCache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheDir)
        try? fileManager.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }
}

/// SwiftUI drop-in replacement for AsyncImage with persistent memory & disk caching
public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage? = nil
    @State private var isLoading: Bool = false

    public init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        if let u = url, let cached = AmberImageCache.shared.image(for: u) {
            _uiImage = State(initialValue: cached)
        }
    }

    public var body: some View {
        Group {
            if let img = uiImage {
                content(Image(uiImage: img))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url else { return }
        if let cached = AmberImageCache.shared.image(for: url) {
            self.uiImage = cached
            return
        }

        guard !isLoading else { return }
        isLoading = true

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let fetched = UIImage(data: data) {
                AmberImageCache.shared.store(fetched, for: url)
                await MainActor.run {
                    self.uiImage = fetched
                    self.isLoading = false
                }
            } else {
                await MainActor.run { self.isLoading = false }
            }
        } catch {
            await MainActor.run { self.isLoading = false }
        }
    }
}
