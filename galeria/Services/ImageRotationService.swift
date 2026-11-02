import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageRotationError: LocalizedError {
    case unreadable(URL)
    case unsupportedFormat(ImageFormat)
    case cannotWrite(URL)
    case animationWouldBeLost

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): "“\(url.lastPathComponent)” could not be decoded."
        case .unsupportedFormat(let format): "\(format.displayName) files cannot be rotated safely."
        case .cannotWrite(let url): "The rotated image could not be saved over “\(url.lastPathComponent)”."
        case .animationWouldBeLost: "Rotating an animated GIF would discard its animation."
        }
    }
}

/// Re-encodes rotated images for formats other than JPEG. The lossless JPEG
/// orientation path is added by the rotation editor in Phase 6.
actor ImageRotationService {
    private let fileManager = FileManager.default

    /// Reads files off the main actor so a batch rotation warning never blocks the UI.
    func requiresReencode(items: [ImageItem], direction: RotationDirection) -> Bool {
        for item in items {
            if item.format.supportsLosslessRotation,
               let data = try? Data(contentsOf: item.url, options: [.mappedIfSafe]),
               (try? JPEGOrientationEditor.rotatedData(data, direction: direction)) != nil {
                continue
            }
            return true
        }
        return false
    }

    func rotate(_ url: URL, format: ImageFormat, direction: RotationDirection) throws {
        if format.isRaw { throw ImageRotationError.unsupportedFormat(format) }
        if format == .gif { throw ImageRotationError.animationWouldBeLost }
        if format == .jpeg, (try? JPEGOrientationEditor.rotateLosslessly(fileURL: url, direction: direction)) == true {
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageRotationError.unreadable(url)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let maxPixel = max(width, height, 1)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1)
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageRotationError.unreadable(url)
        }
        guard let rotated = Self.rotate(decoded, direction: direction) else {
            throw ImageRotationError.unreadable(url)
        }

        let tags = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        var outputProperties: [CFString: Any] = properties ?? [:]
        outputProperties[kCGImagePropertyOrientation] = 1
        outputProperties[kCGImagePropertyPixelWidth] = rotated.width
        outputProperties[kCGImagePropertyPixelHeight] = rotated.height
        outputProperties[kCGImageDestinationLossyCompressionQuality] = 1.0
        if let exif = outputProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            var updated = exif
            updated[kCGImagePropertyExifPixelXDimension] = rotated.width
            updated[kCGImagePropertyExifPixelYDimension] = rotated.height
            outputProperties[kCGImagePropertyExifDictionary] = updated
        }

        let ext = url.pathExtension.isEmpty ? format.rawValue : url.pathExtension
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".galeria-rotate-\(UUID().uuidString).\(ext)")
        let contentType = format.uniformTypeIdentifier.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, contentType, 1, nil) else {
            throw ImageRotationError.cannotWrite(url)
        }
        CGImageDestinationAddImage(destination, rotated, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? fileManager.removeItem(at: tempURL)
            throw ImageRotationError.cannotWrite(url)
        }

        do {
            _ = try fileManager.replaceItemAt(url, withItemAt: tempURL,
                                              backupItemName: nil,
                                              options: [.usingNewMetadataOnly])
            if !tags.isEmpty {
                try? (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw ImageRotationError.cannotWrite(url)
        }
    }

    private nonisolated static func rotate(_ image: CGImage, direction: RotationDirection) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: height,
                                      height: width,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        switch direction {
        case .right:
            context.translateBy(x: CGFloat(height), y: 0)
            context.rotate(by: .pi / 2)
        case .left:
            context.translateBy(x: 0, y: CGFloat(width))
            context.rotate(by: -.pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
