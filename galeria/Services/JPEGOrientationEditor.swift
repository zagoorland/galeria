import Foundation
import ImageIO

enum JPEGOrientationError: LocalizedError {
    case notJPEG
    case noExifOrientation
    case unsupportedOrientation
    case malformed

    var errorDescription: String? {
        switch self {
        case .notJPEG: "The file is not a JPEG."
        case .noExifOrientation: "This JPEG has no EXIF orientation tag to update."
        case .unsupportedOrientation: "This JPEG uses a mirrored orientation that needs re-encoding."
        case .malformed: "The JPEG metadata could not be read safely."
        }
    }
}

/// Rotates JPEGs by rewriting the EXIF orientation value in place. The
/// compressed image data is untouched, so this path is lossless.
enum JPEGOrientationEditor {
    static func canRotateLosslessly(fileURL: URL, direction: RotationDirection = .right) -> Bool {
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else { return false }
        return (try? rotatedData(data, direction: direction)) != nil
    }

    @discardableResult
    static func rotateLosslessly(fileURL: URL, direction: RotationDirection) throws -> Bool {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let rotated = try rotatedData(data, direction: direction)
        let tags = (try? fileURL.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        do {
            try rotated.write(to: fileURL, options: [.atomic])
        } catch {
            return false
        }
        if !tags.isEmpty {
            try? (fileURL as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
        }
        if let attributes, let creationDate = attributes[.creationDate] as? Date {
            try? FileManager.default.setAttributes([.creationDate: creationDate], ofItemAtPath: fileURL.path)
        }
        return true
    }

    static func rotatedData(_ data: Data, direction: RotationDirection) throws -> Data {
        var bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
            throw JPEGOrientationError.notJPEG
        }
        var index = 2
        while index + 4 <= bytes.count {
            guard bytes[index] == 0xFF else {
                index += 1
                continue
            }
            let marker = bytes[index + 1]
            if marker == 0xD9 || marker == 0xDA { break }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) {
                index += 2
                continue
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2, index + 2 + length <= bytes.count else {
                throw JPEGOrientationError.malformed
            }
            if marker == 0xE1 {
                let payload = index + 4
                if payload + 6 <= bytes.count,
                   String(decoding: bytes[payload..<(payload + 6)], as: UTF8.self) == "Exif\u{0}\u{0}" {
                    let tiffStart = payload + 6
                    try updateOrientation(in: &bytes, tiffStart: tiffStart, direction: direction)
                    return Data(bytes)
                }
            }
            index += 2 + length
        }
        throw JPEGOrientationError.noExifOrientation
    }

    private static func updateOrientation(in bytes: inout [UInt8], tiffStart: Int, direction: RotationDirection) throws {
        guard tiffStart + 8 <= bytes.count else { throw JPEGOrientationError.malformed }
        let littleEndian: Bool
        if bytes[tiffStart] == 0x49, bytes[tiffStart + 1] == 0x49 {
            littleEndian = true
        } else if bytes[tiffStart] == 0x4D, bytes[tiffStart + 1] == 0x4D {
            littleEndian = false
        } else {
            throw JPEGOrientationError.malformed
        }
        guard read16(bytes, tiffStart + 2, littleEndian) == 42 else {
            throw JPEGOrientationError.malformed
        }
        var ifdOffset = Int(read32(bytes, tiffStart + 4, littleEndian))
        var found = false
        var visited = Set<Int>()

        // Update orientation in IFD0 and, when present, the thumbnail IFD.
        for _ in 0..<2 {
            guard ifdOffset != 0, !visited.contains(ifdOffset) else { break }
            visited.insert(ifdOffset)
            let ifdStart = tiffStart + ifdOffset
            guard ifdStart + 2 <= bytes.count else { break }
            let entryCount = Int(read16(bytes, ifdStart, littleEndian))
            let entriesStart = ifdStart + 2
            guard entriesStart + entryCount * 12 + 4 <= bytes.count else { break }
            for entryIndex in 0..<entryCount {
                let entry = entriesStart + entryIndex * 12
                let tag = read16(bytes, entry, littleEndian)
                guard tag == 0x0112 else { continue }
                let type = read16(bytes, entry + 2, littleEndian)
                let count = read32(bytes, entry + 4, littleEndian)
                guard count == 1 else { throw JPEGOrientationError.malformed }
                if type == 3 {
                    let current = Int(read16(bytes, entry + 8, littleEndian))
                    guard let next = rotatedOrientation(current, direction: direction) else {
                        throw JPEGOrientationError.unsupportedOrientation
                    }
                    write16(&bytes, entry + 8, UInt16(next), littleEndian)
                    found = true
                } else if type == 4 {
                    let current = Int(read32(bytes, entry + 8, littleEndian))
                    guard let next = rotatedOrientation(current, direction: direction) else {
                        throw JPEGOrientationError.unsupportedOrientation
                    }
                    write32(&bytes, entry + 8, UInt32(next), littleEndian)
                    found = true
                } else {
                    throw JPEGOrientationError.malformed
                }
            }
            ifdOffset = Int(read32(bytes, entriesStart + entryCount * 12, littleEndian))
        }
        guard found else { throw JPEGOrientationError.noExifOrientation }
    }

    private static func rotatedOrientation(_ value: Int, direction: RotationDirection) -> Int? {
        let clockwise = [1: 6, 6: 3, 3: 8, 8: 1]
        let counterClockwise = [1: 8, 8: 3, 3: 6, 6: 1]
        return (direction == .right ? clockwise : counterClockwise)[value]
    }

    private static func read16(_ bytes: [UInt8], _ offset: Int, _ littleEndian: Bool) -> Int {
        guard offset + 1 < bytes.count else { return 0 }
        let a = Int(bytes[offset]), b = Int(bytes[offset + 1])
        return littleEndian ? a | (b << 8) : (a << 8) | b
    }

    private static func read32(_ bytes: [UInt8], _ offset: Int, _ littleEndian: Bool) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        let values = (0...3).map { UInt32(bytes[offset + $0]) }
        return littleEndian
            ? values[0] | (values[1] << 8) | (values[2] << 16) | (values[3] << 24)
            : (values[0] << 24) | (values[1] << 16) | (values[2] << 8) | values[3]
    }

    private static func write16(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt16, _ littleEndian: Bool) {
        guard offset + 1 < bytes.count else { return }
        if littleEndian {
            bytes[offset] = UInt8(value & 0xFF)
            bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        } else {
            bytes[offset] = UInt8((value >> 8) & 0xFF)
            bytes[offset + 1] = UInt8(value & 0xFF)
        }
    }

    private static func write32(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt32, _ littleEndian: Bool) {
        guard offset + 3 < bytes.count else { return }
        if littleEndian {
            for index in 0..<4 {
                bytes[offset + index] = UInt8((value >> (8 * UInt32(index))) & 0xFF)
            }
        } else {
            for index in 0..<4 {
                bytes[offset + index] = UInt8((value >> (8 * UInt32(3 - index))) & 0xFF)
            }
        }
    }
}
