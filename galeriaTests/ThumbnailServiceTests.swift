import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import galeria

struct ThumbnailServiceTests {
    private enum TestError: Error { case setupFailed }

    @Test("Smaller thumbnail requests reuse a larger cached variant")
    func reusesLargerVariant() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeria-thumbnail-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("sample.png")
        try writePNG(to: imageURL, width: 800, height: 600)

        let items = try await ImageScanner().scan(folder: root, includeSubfolders: false)
        let item = try #require(items.first)

        let firstService = ThumbnailService(cacheDirectory: cache)
        let large = try #require(await firstService.thumbnail(for: item, maxPixel: 512))
        #expect(max(large.size.width, large.size.height) <= 512)

        // Remove the original so a successful smaller request can only come
        // from the cached variants, not a fresh decode of the source.
        try FileManager.default.removeItem(at: imageURL)

        // The 512 memory variant is downscaled without the original file.
        let small = try #require(await firstService.thumbnail(for: item, maxPixel: 256))
        #expect(max(small.size.width, small.size.height) <= 256)

        // A fresh service only has the disk cache. It must find the 512 JPEG
        // and produce the smaller variant from it.
        let secondService = ThumbnailService(cacheDirectory: cache)
        let fromDisk = try #require(await secondService.thumbnail(for: item, maxPixel: 256))
        #expect(max(fromDisk.size.width, fromDisk.size.height) <= 256)
    }

    private func writePNG(to url: URL, width: Int, height: Int) throws {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw TestError.setupFailed }
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              )
        else { throw TestError.setupFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TestError.setupFailed }
    }
}
