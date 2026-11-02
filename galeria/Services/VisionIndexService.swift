import CoreGraphics
import Foundation
import ImageIO
import Vision

private struct SmartIndexRecord: Codable {
    var modified: Date
    var labels: [String]
}

/// Opt-in on-device image classification. Labels are stored in a small JSON
/// cache keyed by path and modification date; nothing leaves the Mac.
actor VisionIndexService {
    private let fileManager = FileManager.default
    private let cacheURL: URL
    private var records: [String: SmartIndexRecord] = [:]
    private var didLoad = false

    init(cacheDirectory: URL? = nil) {
        let directory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("zagoor.galeria", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("galeria-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.cacheURL = directory.appendingPathComponent("SmartIndex.json")
    }

    func cachedLabels(for items: [ImageItem]) -> [URL: [String]] {
        loadIfNeeded()
        var result: [URL: [String]] = [:]
        for item in items {
            if let record = records[item.url.path],
               abs(record.modified.timeIntervalSince(item.modifiedAt)) < 0.5 {
                result[item.url] = record.labels
            }
        }
        return result
    }

    /// Classifies items that are missing from the cache and returns all labels.
    func index(
        items: [ImageItem],
        progress: @escaping @MainActor @Sendable (Int, Int) -> Void
    ) async -> [URL: [String]] {
        loadIfNeeded()
        var result: [URL: [String]] = [:]
        var changed = false
        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            if let record = records[item.url.path],
               abs(record.modified.timeIntervalSince(item.modifiedAt)) < 0.5 {
                result[item.url] = record.labels
            } else {
                let labels = classify(item)
                if !labels.isEmpty {
                    records[item.url.path] = SmartIndexRecord(modified: item.modifiedAt, labels: labels)
                    result[item.url] = labels
                    changed = true
                }
            }
            await progress(index + 1, items.count)
            if changed && (index + 1) % 12 == 0 {
                save()
            }
        }
        if changed { save() }
        return result
    }

    func cacheSize() -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: cacheURL.path)
        return Int64((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
    }

    func clearCache() {
        records.removeAll()
        didLoad = true
        try? fileManager.removeItem(at: cacheURL)
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: SmartIndexRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: cacheURL, options: [.atomic])
    }

    private func classify(_ item: ImageItem) -> [String] {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) else { return [] }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return [] }
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            let observations = (request.results ?? [])
                .filter { $0.confidence >= 0.12 }
                .prefix(10)
            return observations.map { $0.identifier.lowercased() }
        } catch {
            return []
        }
    }
}
