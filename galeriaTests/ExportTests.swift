import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import galeria

struct ExportTests {
    private enum TestError: Error { case failed }

    @Test("Export writes a converted file without overwriting")
    func exportJPEG() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeria-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.png")
        try writeGIFFlikePNG(to: source, width: 120, height: 80)
        try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent("source.jpg")) // unrelated
        let item = ImageItem(url: source, name: "source.png", fileSize: 100,
                             createdAt: Date(), modifiedAt: Date(), addedAt: Date(),
                             pixelWidth: 120, pixelHeight: 80, format: .png, tags: [],
                             exifCaptureDate: nil, cameraMake: nil, cameraModel: nil, lens: nil,
                             iso: nil, aperture: nil, exposureTime: nil, focalLength: nil,
                             latitude: nil, longitude: nil, orientation: 1)
        let destination = folder.appendingPathComponent("Out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let options = ExportOptions(format: .jpeg, quality: 0.8, maximumDimension: 60,
                                    stripMetadata: true, destination: destination)
        let results = try await ExportService().export(items: [item], options: options) { _, _ in }
        let output = try #require(results.first?.destinationURL)
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(output.pathExtension == "jpg")
        let exported = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(exported, 0, nil))
        #expect(max(image.width, image.height) <= 60)
    }

    private func writeGIFFlikePNG(to url: URL, width: Int, height: Int) throws {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = { () -> CGImage? in
                  context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
                  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                  return context.makeImage()
              }(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                 UTType.png.identifier as CFString, 1, nil)
        else { throw TestError.failed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TestError.failed }
    }
}
