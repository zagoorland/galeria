import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Vision

enum DuplicateMode: String, CaseIterable, Identifiable, Sendable {
    case exact
    case similar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .exact: "Exact Copies"
        case .similar: "Similar Images"
        }
    }
}

struct DuplicateGroup: Identifiable, Sendable {
    let id: UUID
    let items: [ImageItem]
    let mode: DuplicateMode
    let smallestDistance: Double?
}

enum DuplicateFinderError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported: "Similarity search is not supported on this Mac."
        }
    }
}

/// Exact duplicates use SHA-256; similar images use Vision feature prints.
/// Both run in the background and update progress on the main actor.
actor DuplicateFinder {
    private let fileManager = FileManager.default

    func find(
        in items: [ImageItem],
        mode: DuplicateMode,
        threshold: Double,
        progress: @escaping @MainActor @Sendable (Double, String) -> Void
    ) async throws -> [DuplicateGroup] {
        switch mode {
        case .exact:
            return try await exactDuplicates(items: items, progress: progress)
        case .similar:
            return try await similarImages(items: items, threshold: threshold, progress: progress)
        }
    }

    private func exactDuplicates(
        items: [ImageItem],
        progress: @escaping @MainActor @Sendable (Double, String) -> Void
    ) async throws -> [DuplicateGroup] {
        await progress(0.02, "Grouping by file size…")
        let bySize = Dictionary(grouping: items.filter { $0.fileSize > 0 }, by: \.fileSize)
        let candidates = bySize.values.filter { $0.count > 1 }.flatMap { $0 }
        guard !candidates.isEmpty else {
            await progress(1, "No duplicates found")
            return []
        }
        var byHash: [String: [ImageItem]] = [:]
        for (index, item) in candidates.enumerated() {
            try Task.checkCancellation()
            if let digest = hashFile(at: item.url) {
                byHash[digest, default: []].append(item)
            }
            await progress(0.05 + 0.9 * Double(index + 1) / Double(candidates.count),
                           "Hashing \(item.name)…")
        }
        let groups = byHash.values
            .filter { $0.count > 1 }
            .map { items in
                DuplicateGroup(id: UUID(), items: items.sorted { $0.name < $1.name },
                               mode: .exact, smallestDistance: 0)
            }
            .sorted { ($0.items.first?.name ?? "") < ($1.items.first?.name ?? "") }
        await progress(1, groups.isEmpty ? "No duplicates found" : "Found \(groups.count) duplicate groups")
        return groups
    }

    private func similarImages(
        items: [ImageItem],
        threshold: Double,
        progress: @escaping @MainActor @Sendable (Double, String) -> Void
    ) async throws -> [DuplicateGroup] {
        guard items.count >= 2 else {
            await progress(1, "Not enough images to compare")
            return []
        }
        var observations: [(item: ImageItem, observation: VNFeaturePrintObservation)] = []
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            await progress(0.7 * Double(index) / Double(items.count), "Examining \(item.name)…")
            guard let request = featurePrint(for: item) else { continue }
            observations.append((item, request))
        }
        guard observations.count >= 2 else {
            await progress(1, "No comparable images")
            return []
        }

        var parent = Array(0..<observations.count)
        func root(_ index: Int) -> Int {
            var value = index
            while parent[value] != value {
                parent[value] = parent[parent[value]]
                value = parent[value]
            }
            return value
        }
        func union(_ a: Int, _ b: Int) {
            let rootA = root(a), rootB = root(b)
            if rootA != rootB { parent[rootB] = rootA }
        }

        let totalPairs = max(1, observations.count * (observations.count - 1) / 2)
        var compared = 0
        for i in 0..<observations.count {
            try Task.checkCancellation()
            for j in (i + 1)..<observations.count {
                var rawDistance: Float = .greatestFiniteMagnitude
                do {
                    try observations[i].observation.computeDistance(&rawDistance, to: observations[j].observation)
                } catch {
                    rawDistance = .greatestFiniteMagnitude
                }
                if Double(rawDistance) <= threshold {
                    union(i, j)
                }
                compared += 1
                if compared % 128 == 0 {
                    await progress(0.7 + 0.29 * Double(compared) / Double(totalPairs), "Comparing images…")
                }
            }
        }

        var buckets: [Int: [Int]] = [:]
        for index in observations.indices {
            buckets[root(index), default: []].append(index)
        }
        let groups = buckets.values
            .filter { $0.count > 1 }
            .map { indices -> DuplicateGroup in
                let groupItems = indices.map { observations[$0].item }
                var minimum = Double.greatestFiniteMagnitude
                if indices.count > 1 {
                    for a in 0..<(indices.count - 1) {
                        for b in (a + 1)..<indices.count {
                            var rawDistance: Float = .greatestFiniteMagnitude
                            do {
                                try observations[indices[a]].observation.computeDistance(&rawDistance, to: observations[indices[b]].observation)
                                minimum = min(minimum, Double(rawDistance))
                            } catch {
                                // Non-comparable prints are ignored.
                            }
                        }
                    }
                }
                return DuplicateGroup(id: UUID(),
                                      items: groupItems.sorted { $0.name < $1.name },
                                      mode: .similar,
                                      smallestDistance: minimum.isFinite ? minimum : nil)
            }
            .sorted { ($0.items.first?.name ?? "") < ($1.items.first?.name ?? "") }
        await progress(1, groups.isEmpty ? "No similar images found" : "Found \(groups.count) similar groups")
        return groups
    }

    private func featurePrint(for item: ImageItem) -> VNFeaturePrintObservation? {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }

    private func hashFile(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let data = try? handle.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
