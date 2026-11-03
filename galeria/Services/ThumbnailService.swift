import AppKit
import CryptoKit
import Foundation
import ImageIO

enum ThumbnailQuality: String, CaseIterable, Codable, Sendable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: "Fast"
        case .medium: "Balanced"
        case .high: "Sharp"
        }
    }

    var maxPixelSize: Int {
        switch self {
        case .low: 512
        case .medium: 1024
        case .high: 2048
        }
    }
}

/// A thread-safe snapshot of the thumbnail memory cache. The grid checks it
/// synchronously so cells that are already warm never flash a placeholder.
final class ThumbnailMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSImage>()

    init(countLimit: Int, totalCostLimit: Int) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: NSImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Loads downsampled thumbnails from ImageIO, caching them in memory and on disk.
/// All image I/O runs off the main actor.
actor ThumbnailService {
    nonisolated let memoryCache: ThumbnailMemoryCache
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private static let pixelBuckets = [256, 512, 1024, 2048, 4096]

    init(cacheDirectory: URL? = nil) {
        let base = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("zagoor.galeria", isDirectory: true)
            .appendingPathComponent("Thumbnails", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("galeria-thumbnails", isDirectory: true)
        self.cacheDirectory = base
        self.memoryCache = ThumbnailMemoryCache(countLimit: 2000,
                                                totalCostLimit: 384 * 1024 * 1024)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    /// Requests a thumbnail at approximately `maxPixel` pixels on the long edge.
    func thumbnail(for item: ImageItem, maxPixel: Int) async -> NSImage? {
        let pixelSize = Self.pixelBucket(maxPixel)
        let key = Self.cacheKey(for: item, pixelSize: pixelSize)
        if let image = memoryCache.image(for: key) { return image }

        // A larger variant is already in memory. Reuse it instead of falling
        // back to the original image just because the grid density changed.
        if let larger = largerMemoryThumbnail(for: item, pixelSize: pixelSize),
           let resized = Self.downscale(larger, to: pixelSize) {
            cache(resized, forKey: key)
            return resized
        }

        if let task = inFlight[key] { return await task.value }

        let diskURL = cacheDirectory.appendingPathComponent(key).appendingPathExtension("jpg")
        let directory = cacheDirectory
        let task = Task<NSImage?, Never>.detached(priority: .userInitiated) {
            if let data = try? Data(contentsOf: diskURL, options: [.mappedIfSafe]),
               let image = NSImage(data: data) {
                return image
            }
            if let cached = Self.loadLargerCachedThumbnail(for: item,
                                                           pixelSize: pixelSize,
                                                           cacheDirectory: directory,
                                                           destination: diskURL) {
                return cached
            }
            return Self.generateThumbnail(for: item.url, maxPixel: pixelSize, destination: diskURL)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            cache(image, forKey: key)
        }
        return image
    }

    private func cache(_ image: NSImage, forKey key: String) {
        memoryCache.set(image, for: key)
    }

    /// Synchronous lookup for a cell that is being configured on the main
    /// thread. A larger cached variant is also acceptable: AppKit scales it
    /// down to the tile without another decode.
    nonisolated func cachedImage(for item: ImageItem, maxPixel: Int) -> NSImage? {
        let pixelSize = Self.pixelBucket(maxPixel)
        if let image = memoryCache.image(for: Self.cacheKey(for: item, pixelSize: pixelSize)) {
            return image
        }
        for bucket in Self.pixelBuckets where bucket > pixelSize {
            if let image = memoryCache.image(for: Self.cacheKey(for: item, pixelSize: bucket)) {
                return image
            }
        }
        return nil
    }

    private func largerMemoryThumbnail(for item: ImageItem, pixelSize: Int) -> NSImage? {
        for bucket in Self.pixelBuckets where bucket > pixelSize {
            if let image = memoryCache.image(for: Self.cacheKey(for: item, pixelSize: bucket)) {
                return image
            }
        }
        return nil
    }

    func prefetch(items: [ImageItem], maxPixel: Int) async {
        for item in items {
            if Task.isCancelled { return }
            _ = await thumbnail(for: item, maxPixel: maxPixel)
        }
    }


    /// Warms disk and memory caches for a folder after the first screen is
    /// visible. Processing in small concurrent batches keeps this from
    /// monopolizing ImageIO while the grid remains interactive.
    func warmCache(for items: [ImageItem], maxPixel: Int, concurrency: Int = 12) async {
        guard !items.isEmpty else { return }
        let batchSize = max(1, concurrency)
        var index = 0
        while index < items.count {
            if Task.isCancelled { return }
            let end = min(index + batchSize, items.count)
            let batch = items[index..<end]
            await withTaskGroup(of: Void.self) { group in
                for item in batch {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        _ = await self.thumbnail(for: item, maxPixel: maxPixel)
                    }
                }
            }
            index = end
        }
    }

    func clearCache() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        memoryCache.removeAll()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Clears oldest files until the on-disk cache fits the limit.
    func trimCache(maxBytes: Int64) {
        guard maxBytes > 0 else { return }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? fileManager.contentsOfDirectory(at: cacheDirectory,
                                                             includingPropertiesForKeys: keys,
                                                             options: [.skipsHiddenFiles]) else { return }
        var entries: [(url: URL, date: Date, size: Int64)] = []
        var total: Int64 = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = Int64(values?.fileSize ?? 0)
            total += size
            entries.append((url, values?.contentModificationDate ?? .distantPast, size))
        }
        guard total > maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
            if total <= maxBytes { break }
        }
    }

    private nonisolated static func loadLargerCachedThumbnail(
        for item: ImageItem,
        pixelSize: Int,
        cacheDirectory: URL,
        destination: URL
    ) -> NSImage? {
        for bucket in pixelBuckets where bucket > pixelSize {
            let key = cacheKey(for: item, pixelSize: bucket)
            let sourceURL = cacheDirectory.appendingPathComponent(key).appendingPathExtension("jpg")
            guard FileManager.default.fileExists(atPath: sourceURL.path),
                  let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)
            else { continue }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                continue
            }
            // Persist the exact size so repeated density changes stay fast.
            writeJPEG(cgImage, to: destination)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return nil
    }

    private nonisolated static func downscale(_ image: NSImage, to maxPixel: Int) -> NSImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        let current = max(cgImage.width, cgImage.height)
        guard current > maxPixel else { return image }
        let ratio = CGFloat(maxPixel) / CGFloat(current)
        let width = max(1, Int((CGFloat(cgImage.width) * ratio).rounded()))
        let height = max(1, Int((CGFloat(cgImage.height) * ratio).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: NSSize(width: width, height: height))
    }

    private nonisolated static func generateThumbnail(for url: URL, maxPixel: Int, destination: URL) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        writeJPEG(cgImage, to: destination)
        return image
    }

    private nonisolated static func writeJPEG(_ image: CGImage, to destination: URL) {
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.82]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    nonisolated static func pixelBucket(_ requested: Int) -> Int {
        let clamped = min(max(requested, 256), 4096)
        return ((clamped + 127) / 128) * 128
    }

    nonisolated static func cacheKey(for item: ImageItem, pixelSize: Int) -> String {
        let raw = "\(item.url.path)|\(item.modifiedAt.timeIntervalSince1970)|\(pixelSize)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
