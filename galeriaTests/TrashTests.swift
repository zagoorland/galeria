import Foundation
import Testing
@testable import galeria

struct TrashTests {
    private struct LocalProvider: TrashProvider {
        let trashDirectory: URL

        func recycle(_ urls: [URL]) async throws -> [TrashMapping] {
            try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
            var mappings: [TrashMapping] = []
            for url in urls {
                let trashed = trashDirectory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
                try FileManager.default.moveItem(at: url, to: trashed)
                mappings.append(TrashMapping(originalURL: url, trashedURL: trashed))
            }
            return mappings
        }
    }

    @Test("Trash mapping can be restored to the original folder")
    func trashAndRestore() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try makeFile(named: "photo.jpg", in: root, contents: "pixels")
        let provider = LocalProvider(trashDirectory: root.appendingPathComponent("Trash", isDirectory: true))
        let service = TrashService(provider: provider)

        let mappings = try await service.trash([file])
        #expect(mappings.count == 1)
        #expect(mappings.first?.originalURL == file)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        try await service.restore(mappings)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: file, encoding: .utf8) == "pixels")
    }

    @Test("Restore refuses to overwrite a file recreated at the original path")
    func collisionDoesNotOverwrite() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try makeFile(named: "photo.jpg", in: root, contents: "original")
        let trashDir = root.appendingPathComponent("Trash", isDirectory: true)
        let service = TrashService(provider: LocalProvider(trashDirectory: trashDir))
        let mappings = try await service.trash([file])
        try Data("new file".utf8).write(to: file)

        await #expect(throws: TrashServiceError.self) {
            try await service.restore(mappings)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "new file")
        if let trashed = mappings.first?.trashedURL {
            #expect(FileManager.default.fileExists(atPath: trashed.path))
        }
    }

    @Test("Copy destination naming never overwrites")
    func uniqueDestinationName() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeFile(named: "image.jpg", in: root, contents: "one")
        _ = try makeFile(named: "image 2.jpg", in: root, contents: "two")
        let destination = FileTransferService.availableURL(for: "image.jpg", in: root)
        #expect(destination.lastPathComponent == "image 3.jpg")
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeria-trash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(named name: String, in folder: URL, contents: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
}

struct ImportTests {
    private struct LocalProvider: TrashProvider {
        let trashDirectory: URL
        func recycle(_ urls: [URL]) async throws -> [TrashMapping] { [] }
    }

    @Test("Dropping a duplicate filename imports with a unique name")
    func copyDoesNotOverwrite() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeria-import-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceFile = source.appendingPathComponent("photo.jpg")
        try Data("new".utf8).write(to: sourceFile)
        try Data("old".utf8).write(to: destination.appendingPathComponent("photo.jpg"))

        let service = FileTransferService()
        let mappings = try await service.transfer([sourceFile], to: destination, mode: .copy)
        let imported = try #require(mappings.first?.destinationURL)
        #expect(imported.lastPathComponent == "photo 2.jpg")
        #expect(try String(contentsOf: imported, encoding: .utf8) == "new")
        #expect(try String(contentsOf: destination.appendingPathComponent("photo.jpg"), encoding: .utf8) == "old")
    }
}
