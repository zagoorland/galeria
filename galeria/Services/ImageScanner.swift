import AppKit
import Foundation
import ImageIO

enum FolderScanError: LocalizedError {
    case folderMissing(URL)
    case permissionDenied(URL)
    case cannotRead(URL, String)

    var errorDescription: String? {
        switch self {
        case .folderMissing: "That folder no longer exists."
        case .permissionDenied: "Galeria no longer has permission to read this folder."
        case .cannotRead(_, let message): "The folder could not be read. \(message)"
        }
    }
}

/// Scans on a background actor. Image headers are read with ImageIO, never by
/// decoding full-size bitmaps.
actor ImageScanner {
    /// Scans in filename order and streams the first batches to the UI so a
    /// 10,000-image folder shows its first screen before the full scan ends.
    func scan(
        folder: URL,
        includeSubfolders: Bool,
        batchSize: Int = 64,
        onBatch: (@MainActor @Sendable ([ImageItem]) -> Void)? = nil
    ) async throws -> [ImageItem] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FolderScanError.folderMissing(folder)
        }
        guard fileManager.isReadableFile(atPath: folder.path) else {
            throw FolderScanError.permissionDenied(folder)
        }

        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isHiddenKey, .isPackageKey,
            .fileSizeKey, .creationDateKey, .contentModificationDateKey,
            .addedToDirectoryDateKey, .nameKey, .isAliasFileKey, .isSymbolicLinkKey, .tagNamesKey
        ]

        var urls: [URL] = []
        do {
            if includeSubfolders {
                guard let enumerator = fileManager.enumerator(
                    at: folder,
                    includingPropertiesForKeys: resourceKeys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                ) else {
                    throw FolderScanError.cannotRead(folder, "Directory enumeration failed.")
                }
                while let url = enumerator.nextObject() as? URL {
                    if Task.isCancelled { return [] }
                    urls.append(url)
                }
            } else {
                urls = try fileManager.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: resourceKeys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            }
        } catch let error as FolderScanError {
            throw error
        } catch {
            throw FolderScanError.cannotRead(folder, error.localizedDescription)
        }

        urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var items: [ImageItem] = []
        var batch: [ImageItem] = []
        items.reserveCapacity(urls.count)
        batch.reserveCapacity(min(max(batchSize, 1), 256))
        for url in urls {
            if Task.isCancelled { return [] }
            autoreleasepool {
                guard let item = scanFile(url, resourceKeys: resourceKeys) else { return }
                items.append(item)
                batch.append(item)
            }
            if batch.count >= max(batchSize, 1) {
                if let onBatch { await onBatch(batch) }
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty, let onBatch {
            await onBatch(batch)
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func scanFile(_ url: URL, resourceKeys: [URLResourceKey]) -> ImageItem? {
        guard let format = ImageFormat.forExtension(url.pathExtension) else { return nil }
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        guard values?.isRegularFile == true, values?.isHidden != true else { return nil }
        if values?.isSymbolicLink == true || values?.isAliasFile == true { return nil }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(
            source, 0, [kCGImageSourceShouldCache: false] as CFDictionary
        ) as? [CFString: Any]

        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let gps = properties?[kCGImagePropertyGPSDictionary] as? [CFString: Any]

        let rawWidth = Self.int(properties?[kCGImagePropertyPixelWidth]) ?? 0
        let rawHeight = Self.int(properties?[kCGImagePropertyPixelHeight]) ?? 0
        let orientation = Self.int(properties?[kCGImagePropertyOrientation]) ?? 1
        // EXIF orientations 5–8 swap the displayed width and height.
        let swapsDimensions = (5...8).contains(orientation)
        let pixelWidth = swapsDimensions ? rawHeight : rawWidth
        let pixelHeight = swapsDimensions ? rawWidth : rawHeight
        let created = values?.creationDate ?? Date.distantPast
        let modified = values?.contentModificationDate ?? created
        let added = values?.addedToDirectoryDate ?? created
        let size = Int64(values?.fileSize ?? 0)
        let name = values?.name ?? url.lastPathComponent
        let tags = values?.tagNames ?? []

        let exifDate = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            .flatMap(Self.exifDateFormatter.date(from:))
        let make = tiff?[kCGImagePropertyTIFFMake] as? String
        let model = tiff?[kCGImagePropertyTIFFModel] as? String
        let lens = exif?[kCGImagePropertyExifLensModel] as? String
        let iso = Self.int(exif?[kCGImagePropertyExifISOSpeedRatings])
        let aperture = Self.double(exif?[kCGImagePropertyExifFNumber])
        let exposure = Self.double(exif?[kCGImagePropertyExifExposureTime])
        let focal = Self.double(exif?[kCGImagePropertyExifFocalLength])
        let latitude = Self.gpsCoordinate(
            value: Self.double(gps?[kCGImagePropertyGPSLatitude]),
            reference: gps?[kCGImagePropertyGPSLatitudeRef] as? String,
            positive: "N"
        )
        let longitude = Self.gpsCoordinate(
            value: Self.double(gps?[kCGImagePropertyGPSLongitude]),
            reference: gps?[kCGImagePropertyGPSLongitudeRef] as? String,
            positive: "E"
        )

        return ImageItem(
            url: url, name: name, fileSize: size,
            createdAt: created, modifiedAt: modified, addedAt: added,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            format: format, tags: tags,
            exifCaptureDate: exifDate,
            cameraMake: make, cameraModel: model, lens: lens,
            iso: iso, aperture: aperture, exposureTime: exposure,
            focalLength: focal, latitude: latitude, longitude: longitude,
            orientation: orientation
        )
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let array = value as? [Any], let first = array.first { return int(first) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let array = value as? [Any], let first = array.first { return double(first) }
        return nil
    }

    private static func gpsCoordinate(value: Double?, reference: String?, positive: String) -> Double? {
        guard let value, value != 0 else { return nil }
        return reference?.uppercased() == positive ? value : -value
    }

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()
}
