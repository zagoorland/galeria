import Foundation

/// An immutable snapshot of an image's file and EXIF metadata.
///
/// Thumbnails are deliberately not part of this value; they are loaded by
/// `ThumbnailService` and never keep a full-resolution image in the grid.
struct ImageItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let fileSize: Int64
    let createdAt: Date
    let modifiedAt: Date
    let addedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let format: ImageFormat
    let tags: [String]
    let exifCaptureDate: Date?
    let cameraMake: String?
    let cameraModel: String?
    let lens: String?
    let iso: Int?
    let aperture: Double?
    let exposureTime: Double?
    let focalLength: Double?
    let latitude: Double?
    let longitude: Double?
    let orientation: Int

    var id: URL { url }

    var rating: Int { FinderTagCodec.rating(from: tags) }
    var label: FinderColorLabel? { FinderTagCodec.colorLabel(from: tags) }
    var isPick: Bool { FinderTagCodec.isPick(tags) }
    var isReject: Bool { FinderTagCodec.isReject(tags) }
    var flag: ImageFlag {
        if isPick { return .pick }
        if isReject { return .reject }
        return .none
    }

    var captureDate: Date { exifCaptureDate ?? createdAt }
    var aspectRatio: CGFloat {
        guard pixelWidth > 0, pixelHeight > 0 else { return 1 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    var isLandscape: Bool { pixelWidth > pixelHeight }
    var isPortrait: Bool { pixelHeight > pixelWidth }
    var isSquare: Bool { pixelWidth == pixelHeight && pixelWidth > 0 }

    var dimensionsDescription: String {
        guard pixelWidth > 0, pixelHeight > 0 else { return "Unknown dimensions" }
        return "\(pixelWidth) × \(pixelHeight)"
    }

    var fileExtension: String { url.pathExtension.lowercased() }
    var hasLocation: Bool { latitude != nil && longitude != nil }

    var cameraDescription: String? {
        [cameraMake, cameraModel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ").nilIfEmpty
    }

    var apertureDescription: String? {
        aperture.map { String(format: "ƒ/%.1f", $0) }
    }

    var exposureDescription: String? {
        guard let exposureTime, exposureTime > 0 else { return nil }
        if exposureTime >= 1 {
            return String(format: "%.1f s", exposureTime)
        }
        return "1/\(Int((1 / exposureTime).rounded())) s"
    }

    var focalLengthDescription: String? {
        focalLength.map { String(format: "%.0f mm", $0) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension ImageItem {
    /// Returns a copy with new Finder tags while retaining every loaded metadata field.
    func replacingTags(_ tags: [String]) -> ImageItem {
        ImageItem(
            url: url, name: name, fileSize: fileSize,
            createdAt: createdAt, modifiedAt: modifiedAt, addedAt: addedAt,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            format: format, tags: FinderTagCodec.canonical(tags),
            exifCaptureDate: exifCaptureDate,
            cameraMake: cameraMake, cameraModel: cameraModel, lens: lens,
            iso: iso, aperture: aperture, exposureTime: exposureTime,
            focalLength: focalLength, latitude: latitude, longitude: longitude,
            orientation: orientation
        )
    }
}
