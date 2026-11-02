import Foundation
import UniformTypeIdentifiers

/// Image formats the browser understands. RAW types rely on ImageIO support in the OS.
enum ImageFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case jpeg
    case png
    case heic
    case heif
    case gif
    case tiff
    case bmp
    case webp
    case avif
    case dng
    case cr2
    case cr3
    case nef
    case arw
    case raf
    case orf
    case rw2
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .heif: "HEIF"
        case .gif: "GIF"
        case .tiff: "TIFF"
        case .bmp: "BMP"
        case .webp: "WebP"
        case .avif: "AVIF"
        case .dng: "DNG"
        case .cr2, .cr3: "Canon RAW"
        case .nef: "Nikon RAW"
        case .arw: "Sony RAW"
        case .raf: "Fujifilm RAW"
        case .orf: "Olympus RAW"
        case .rw2: "Panasonic RAW"
        case .other: "Image"
        }
    }

    var isRaw: Bool {
        switch self {
        case .dng, .cr2, .cr3, .nef, .arw, .raf, .orf, .rw2: true
        default: false
        }
    }

    var supportsLosslessRotation: Bool { self == .jpeg }

    var uniformTypeIdentifier: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .heif: .heif
        case .gif: .gif
        case .tiff: .tiff
        case .bmp: .bmp
        case .webp: UTType.webP
        case .avif: UTType(filenameExtension: "avif") ?? .image
        case .dng: UTType(filenameExtension: "dng") ?? .rawImage
        case .cr2, .cr3, .nef, .arw, .raf, .orf, .rw2:
            UTType(filenameExtension: rawValue) ?? .rawImage
        case .other: .image
        }
    }

    static func forExtension(_ ext: String) -> ImageFormat? {
        switch ext.lowercased() {
        case "jpg", "jpeg": .jpeg
        case "png": .png
        case "heic": .heic
        case "heif": .heif
        case "gif": .gif
        case "tif", "tiff": .tiff
        case "bmp": .bmp
        case "webp": .webp
        case "avif": .avif
        case "dng": .dng
        case "cr2": .cr2
        case "cr3": .cr3
        case "nef": .nef
        case "arw": .arw
        case "raf": .raf
        case "orf": .orf
        case "rw2": .rw2
        default: nil
        }
    }

    /// Extensions used by the Open panel and import validation.
    static let supportedExtensions: Set<String> = Set(ImageFormat.allCases.flatMap { format -> [String] in
        switch format {
        case .jpeg: ["jpg", "jpeg"]
        case .tiff: ["tif", "tiff"]
        case .other: []
        default: [format.rawValue]
        }
    })
}
