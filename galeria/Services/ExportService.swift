import CoreGraphics
import Foundation
import ImageIO

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg
    case png
    case heic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        }
    }

    var contentTypeIdentifier: String {
        switch self {
        case .jpeg: "public.jpeg"
        case .png: "public.png"
        case .heic: "public.heic"
        }
    }

    var supportsQuality: Bool { self != .png }
}

struct ExportOptions: Sendable {
    var format: ExportFormat
    var quality: Double
    var maximumDimension: Int?
    var stripMetadata: Bool
    var destination: URL
}

struct ExportedFile: Sendable {
    let sourceURL: URL
    let destinationURL: URL
}

enum ExportError: LocalizedError {
    case unreadable(URL)
    case cannotEncode(URL)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): "“\(url.lastPathComponent)” could not be decoded."
        case .cannotEncode(let url): "“\(url.lastPathComponent)” could not be encoded in the selected format."
        case .cancelled: "Export cancelled."
        }
    }
}

/// Batch conversion with ImageIO. Work happens on this actor; the target
/// directory is supplied by the caller and kept security-scoped while exporting.
actor ExportService {
    func export(
        items: [ImageItem],
        options: ExportOptions,
        progress: @escaping @MainActor @Sendable (Double, String) -> Void
    ) async throws -> [ExportedFile] {
        var exported: [ExportedFile] = []
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            await progress(Double(index) / Double(max(items.count, 1)), "Converting \(item.name)…")
            let destination = try convert(item: item, options: options)
            exported.append(ExportedFile(sourceURL: item.url, destinationURL: destination))
            await progress(Double(index + 1) / Double(max(items.count, 1)), "Exported \(index + 1) of \(items.count)")
        }
        return exported
    }

    private func convert(item: ImageItem, options: ExportOptions) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL,
                                                      [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ExportError.unreadable(item.url)
        }
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (sourceProperties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (sourceProperties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let sourceMax = max(width, height)
        let maximum = options.maximumDimension.map { max($0, 1) } ?? max(sourceMax, 1)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ExportError.unreadable(item.url)
        }

        var properties: [CFString: Any] = [:]
        if !options.stripMetadata {
            properties = sourceProperties ?? [:]
            properties[kCGImagePropertyOrientation] = 1
            properties[kCGImagePropertyPixelWidth] = image.width
            properties[kCGImagePropertyPixelHeight] = image.height
        }
        if options.format.supportsQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(options.quality, 0.1), 1.0)
        }

        let base = item.url.deletingPathExtension().lastPathComponent
        let target = FileTransferService.availableURL(for: "\(base).\(options.format.fileExtension)",
                                                      in: options.destination)
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL,
                                                                 options.format.contentTypeIdentifier as CFString,
                                                                 1, nil) else {
            throw ExportError.cannotEncode(item.url)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: target)
            throw ExportError.cannotEncode(item.url)
        }
        return target
    }
}
