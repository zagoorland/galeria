import Foundation
import Testing
@testable import galeria

struct BatchRenamerTests {
    @Test("Two-phase rename supports swapping names and rollback")
    func swapNames() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeria-renamer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("a.jpg")
        let b = folder.appendingPathComponent("b.jpg")
        try Data("A".utf8).write(to: a)
        try Data("B".utf8).write(to: b)

        let renamer = BatchRenamer()
        try await renamer.apply([
            RenameChange(originalURL: a, renamedURL: b),
            RenameChange(originalURL: b, renamedURL: a)
        ])
        #expect(try String(contentsOf: a, encoding: .utf8) == "B")
        #expect(try String(contentsOf: b, encoding: .utf8) == "A")

        try await renamer.apply([
            RenameChange(originalURL: a, renamedURL: b),
            RenameChange(originalURL: b, renamedURL: a)
        ])
        #expect(try String(contentsOf: a, encoding: .utf8) == "A")
        #expect(try String(contentsOf: b, encoding: .utf8) == "B")
    }

    @Test("Rename refuses an existing destination")
    func refusesOverwrite() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeria-renamer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.jpg")
        let destination = folder.appendingPathComponent("taken.jpg")
        try Data("source".utf8).write(to: source)
        try Data("taken".utf8).write(to: destination)
        let renamer = BatchRenamer()
        await #expect(throws: BatchRenameError.self) {
            try await renamer.apply([RenameChange(originalURL: source, renamedURL: destination)])
        }
        #expect(try String(contentsOf: source, encoding: .utf8) == "source")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "taken")
    }
}
