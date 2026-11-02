import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import galeria

@MainActor
struct ScannerTests {
    private enum TestError: Error { case setupFailed }

    @Test("Scanner finds images, skips non-images, and honors subfolder toggle")
    func scanning() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeria-scanner-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try writePNG(to: root.appendingPathComponent("first.png"))
        try writePNG(to: nested.appendingPathComponent("second.png"))
        try Data("not an image".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let scanner = ImageScanner()
        let flat = try await scanner.scan(folder: root, includeSubfolders: false)
        #expect(flat.count == 1)
        #expect(flat.first?.format == .png)
        #expect(flat.first?.pixelWidth == 4)
        #expect(flat.first?.pixelHeight == 4)

        let recursive = try await scanner.scan(folder: root, includeSubfolders: true)
        #expect(recursive.count == 2)
        #expect(recursive.map(\.name).sorted() == ["first.png", "second.png"])
    }

    @Test("Scanner reports a missing folder")
    func missingFolder() async {
        let scanner = ImageScanner()
        await #expect(throws: FolderScanError.self) {
            try await scanner.scan(folder: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)"),
                                   includeSubfolders: false)
        }
    }

    private func writePNG(to url: URL) throws {
        let width = 4, height = 4
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw TestError.setupFailed
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw TestError.setupFailed }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                               UTType.png.identifier as CFString, 1, nil) else {
            throw TestError.setupFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TestError.setupFailed }
    }
}
