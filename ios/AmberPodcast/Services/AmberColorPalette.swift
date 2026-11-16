import SwiftUI
import UIKit
import CoreGraphics

/// High-performance dominant color extractor & cache for podcast artwork.
/// Extracts representative vibrant hues, adjusts luminance for luxury dark backgrounds,
/// and caches results in NSCache to guarantee 0ms overhead on re-renders.
public final class AmberColorPalette: @unchecked Sendable {
    public static let shared = AmberColorPalette()

    private let cache = NSCache<NSString, UIColor>()

    private init() {
        cache.countLimit = 150
    }

    public func dominantColor(for image: UIImage?, key: String? = nil) -> Color {
        guard let image = image else {
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        }

        if let key = key as NSString?, let cached = cache.object(forKey: key) {
            return Color(uiColor: cached)
        }

        if let extracted = extractDominantColor(from: image) {
            let uiColor = UIColor(extracted)
            if let key = key as NSString? {
                cache.setObject(uiColor, forKey: key)
            }
            return extracted
        }

        return Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    /// Core extraction algorithm: downsample to 16x16 thumbnail using explicit RGBA CGContext,
    /// score pixels by saturation and luminance, extract true chromatic hue, and adjust
    /// into an elegant, high-contrast dark tone (~0.12 - 0.20 luminance).
    private func extractDominantColor(from image: UIImage) -> Color? {
        let width = 16
        let height = 16
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Explicit 32-bit big-endian RGBA to prevent byte-order/endianness mismatches
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()

        var bestColor: (r: CGFloat, g: CGFloat, b: CGFloat)? = nil
        var bestScore: CGFloat = -1
        let pixelCount = width * height

        for i in 0..<pixelCount {
            let offset = i * 4
            let a = CGFloat(rawData[offset + 3]) / 255.0
            if a < 0.5 { continue }

            let r = CGFloat(rawData[offset]) / 255.0
            let g = CGFloat(rawData[offset + 1]) / 255.0
            let b = CGFloat(rawData[offset + 2]) / 255.0

            // Relative luminance (ITU-R BT.709)
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if lum > 0.92 || lum < 0.06 { continue } // skip pure white/black

            // Max chromatic difference as saturation proxy
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0

            // Score: prioritize saturation, penalize extreme luminance
            let score = sat * 2.0 + (1.0 - abs(lum - 0.45))
            if score > bestScore {
                bestScore = score
                bestColor = (r, g, b)
            }
        }

        guard let chosen = bestColor else {
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        }

        let uiColor = UIColor(red: chosen.r, green: chosen.g, blue: chosen.b, alpha: 1.0)
        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getHue(&hue, saturation: &sat, brightness: &brightness, alpha: &alpha) else {
            return Color(red: 0.14, green: 0.14, blue: 0.16)
        }

        // Keep hue 100% faithful to cover artwork; adjust saturation and luxury dark brightness
        let targetSat: CGFloat = sat > 0.15 ? min(sat * 0.90, 0.55) : sat
        let targetBrightness: CGFloat = sat > 0.15 ? 0.22 : 0.18
        let darkUIColor = UIColor(hue: hue, saturation: targetSat, brightness: targetBrightness, alpha: 1.0)
        return Color(uiColor: darkUIColor)
    }

    /// Calculate relative luminance (ITU-R BT.709) of a Color to determine light vs dark backgrounds.
    public static func luminance(of color: Color) -> CGFloat {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        var white: CGFloat = 0
        if ui.getWhite(&white, alpha: &a) {
            return white
        }
        return 0.15
    }
}