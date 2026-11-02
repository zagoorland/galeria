import AppKit
import CryptoKit
import Foundation
import ImageIO

final class PreviewImagePayload: @unchecked Sendable {
    let image: NSImage
    let isAnimated: Bool
    let pixelWidth: Int
    let pixelHeight: Int

    init(image: NSImage, isAnimated: Bool, pixelWidth: Int, pixelHeight: Int) {
        self.image = image
        self.isAnimated = isAnimated
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Loads one high-quality preview image at a time, plus a small neighbor cache.
/// The thumbnail grid never touches these full-resolution images.
actor PreviewImageService {
    private let memoryCache = NSCache<NSString, PreviewImagePayload>()
    private var inFlight: [String: Task<PreviewImagePayload?, Never>] = [:]
    private let maximumPixelSize = 4096

    init() {
        memoryCache.countLimit = 6
        memoryCache.totalCostLimit = 256 * 1024 * 1024
    }

    func image(for item: ImageItem) async -> PreviewImagePayload? {
        let key = Self.cacheKey(for: item, maximumPixel: maximumPixelSize)
        if let cached = memoryCache.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }
        let url = item.url
        let maximum = maximumPixelSize
        let isGIF = item.format == .gif
        let task = Task<PreviewImagePayload?, Never>.detached(priority: .userInitiated) {
            Self.load(url: url, maximumPixel: maximum, allowAnimation: isGIF)
        }
        inFlight[key] = task
        let payload = await task.value
        inFlight[key] = nil
        if let payload {
            let cost = payload.pixelWidth * payload.pixelHeight * 4
            memoryCache.setObject(payload, forKey: key as NSString, cost: cost)
        }
        return payload
    }

    func preload(items: [ImageItem]) async {
        for item in items {
            if Task.isCancelled { return }
            _ = await image(for: item)
        }
    }

    func clearCache() {
        memoryCache.removeAllObjects()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }

    private nonisolated static func load(url: URL, maximumPixel: Int, allowAnimation: Bool) -> PreviewImagePayload? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let count = CGImageSourceGetCount(source)
        if allowAnimation, count > 1, let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
           let animatedImage = NSImage(data: data) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            return PreviewImagePayload(image: animatedImage, isAnimated: true, pixelWidth: width, pixelHeight: height)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return PreviewImagePayload(image: image, isAnimated: count > 1, pixelWidth: cgImage.width, pixelHeight: cgImage.height)
    }

    private nonisolated static func cacheKey(for item: ImageItem, maximumPixel: Int) -> String {
        let raw = "preview|\(item.url.path)|\(item.modifiedAt.timeIntervalSince1970)|\(maximumPixel)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
