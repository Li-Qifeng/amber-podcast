import SwiftUI
import UIKit
import CoreGraphics

/// High-performance dominant color extractor & cache for podcast artwork.
/// Extracts representative vibrant hues, adjusted for safe dark-mode background contrast with white text.
public final class AmberColorPalette {
    public static let shared = AmberColorPalette()

    private let cache = NSCache<NSString, UIColor>()
    private let fallbackColor = UIColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)

    private init() {
        cache.countLimit = 500
    }

    /// Synchronously returns cached dominant color, or extracts from provided UIImage, or returns fallback.
    public func dominantColor(for image: UIImage?, key: String? = nil) -> Color {
        guard let image = image else {
            return Color(uiColor: fallbackColor)
        }

        let cacheKey = key as NSString?
        if let cacheKey = cacheKey, let cached = cache.object(forKey: cacheKey) {
            return Color(uiColor: cached)
        }

        let uiColor = extractDominantColor(from: image)
        if let cacheKey = cacheKey {
            cache.setObject(uiColor, forKey: cacheKey)
        }
        return Color(uiColor: uiColor)
    }

    /// Core extraction algorithm: downsample to 16x16 thumbnail, score pixels by saturation and luminance,
    /// pick the best representative chromatic tone, and clamp luminance to [0.10, 0.18] for dark-mode contrast.
    private func extractDominantColor(from image: UIImage) -> UIColor {
        let size = CGSize(width: 16, height: 16)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let thumb = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        guard let cgImage = thumb.cgImage,
              let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return fallbackColor
        }

        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        var bestColor: (r: CGFloat, g: CGFloat, b: CGFloat)? = nil
        var bestScore: CGFloat = -1.0

        for y in 0..<16 {
            for x in 0..<16 {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = CGFloat(ptr[offset]) / 255.0
                let g = CGFloat(ptr[offset + 1]) / 255.0
                let b = CGFloat(ptr[offset + 2]) / 255.0

                // Perceived luminance (ITU-R BT.709)
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

                // Filter out extreme highlights or dark shadows
                if lum > 0.90 || lum < 0.06 {
                    continue
                }

                // Calculate saturation (max - min) / max
                let maxC = max(r, max(g, b))
                let minC = min(r, min(g, b))
                let sat = maxC > 0 ? (maxC - minC) / maxC : 0.0

                // Score: prioritize rich saturation and moderate mid-luminance
                let score = sat * 1.6 + (1.0 - abs(lum - 0.35))
                if score > bestScore {
                    bestScore = score
                    bestColor = (r, g, b)
                }
            }
        }

        guard let chosen = bestColor else {
            return fallbackColor
        }

        // Clamp & scale luminance to target ~0.16 for luxurious deep background
        let curLum = 0.2126 * chosen.r + 0.7152 * chosen.g + 0.0722 * chosen.b
        let targetLum: CGFloat = 0.16
        let scale: CGFloat = curLum > targetLum ? (targetLum / curLum) : 1.0

        let finalR = max(0.08, min(1.0, chosen.r * scale))
        let finalG = max(0.08, min(1.0, chosen.g * scale))
        let finalB = max(0.08, min(1.0, chosen.b * scale))

        return UIColor(red: finalR, green: finalG, blue: finalB, alpha: 1.0)
    }
}
