import Foundation
import Testing
@testable import galeria

struct JPEGRotationTests {
    @Test("Lossless rotation rewrites the EXIF orientation value without changing size")
    func orientationUpdate() throws {
        let jpeg = makeJPEGWithOrientation(1)
        let rotated = try JPEGOrientationEditor.rotatedData(jpeg, direction: .right)
        #expect(rotated.count == jpeg.count)
        #expect(try orientation(in: rotated) == 6)
        #expect(try orientation(in: jpeg) == 1)

        let back = try JPEGOrientationEditor.rotatedData(rotated, direction: .left)
        #expect(try orientation(in: back) == 1)
    }

    @Test("Rotating four times returns to the original orientation")
    func fullTurn() throws {
        var data = makeJPEGWithOrientation(1)
        for _ in 0..<4 {
            data = try JPEGOrientationEditor.rotatedData(data, direction: .right)
        }
        #expect(try orientation(in: data) == 1)
    }

    @Test("Mirrored orientations are not changed losslessly")
    func mirroredUnsupported() {
        let jpeg = makeJPEGWithOrientation(2)
        #expect(throws: JPEGOrientationError.self) {
            try JPEGOrientationEditor.rotatedData(jpeg, direction: .right)
        }
    }

    private func orientation(in data: Data) throws -> Int {
        let bytes = [UInt8](data)
        let exifStart = 2 + 4 + 6 // SOI, APP1 marker + length, Exif header
        let little = bytes[exifStart] == 0x49
        let ifdOffset = Int(read32(bytes, exifStart + 4, little))
        let entry = exifStart + ifdOffset + 2 // IFD has exactly one entry
        return little ? Int(bytes[entry + 8]) : Int(bytes[entry + 9])
    }

    private func makeJPEGWithOrientation(_ orientation: UInt16) -> Data {
        let little: UInt16 = orientation
        let tiff: [UInt8] = [
            0x49, 0x49, 0x2A, 0x00,
            0x08, 0x00, 0x00, 0x00,
            0x01, 0x00,
            0x12, 0x01,
            0x03, 0x00,
            0x01, 0x00, 0x00, 0x00,
            UInt8(little & 0xFF), UInt8(little >> 8), 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00
        ]
        let payload = Array("Exif".utf8) + [0, 0] + tiff
        let length = payload.count + 2
        var result: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 0xFF)]
        result.append(contentsOf: payload)
        result.append(contentsOf: [0xFF, 0xD9])
        return Data(result)
    }

    private func read32(_ bytes: [UInt8], _ offset: Int, _ little: Bool) -> UInt32 {
        let values = (0...3).map { UInt32(bytes[offset + $0]) }
        return little
            ? values[0] | (values[1] << 8) | (values[2] << 16) | (values[3] << 24)
            : (values[0] << 24) | (values[1] << 16) | (values[2] << 8) | values[3]
    }
}
