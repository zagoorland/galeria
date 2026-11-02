import Foundation
import Testing
@testable import galeria

struct RenameTests {
    private func item(name: String, directory: URL = URL(fileURLWithPath: "/tmp"),
                      date: Date = Date(timeIntervalSince1970: 0),
                      camera: String? = "Leica Q3") -> ImageItem {
        ImageItem(url: directory.appendingPathComponent(name), name: name, fileSize: 100,
                  createdAt: date, modifiedAt: date, addedAt: date,
                  pixelWidth: 100, pixelHeight: 100, format: .jpeg, tags: [],
                  exifCaptureDate: date, cameraMake: "Leica", cameraModel: camera, lens: nil,
                  iso: nil, aperture: nil, exposureTime: nil, focalLength: nil,
                  latitude: nil, longitude: nil, orientation: 1)
    }

    @Test("Pattern tokens render and extension is preserved")
    func patternRendering() {
        let folder = URL(fileURLWithPath: "/tmp/album")
        let first = item(name: "IMG_0001.JPG", directory: folder)
        let second = item(name: "IMG_0002.JPG", directory: folder)
        let engine = BatchRenameEngine()
        let plan = engine.plan(items: [first, second], pattern: "{date}_{camera}_{counter}",
                               counterStart: 5, counterPadding: 3)
        #expect(plan.collisions.isEmpty)
        #expect(plan.changes[0].renamedURL.lastPathComponent == "1970-01-01_Leica Q3_005.JPG")
        #expect(plan.changes[1].renamedURL.lastPathComponent == "1970-01-01_Leica Q3_006.JPG")
    }

    @Test("Duplicate generated names are collisions")
    func duplicateNames() {
        let folder = URL(fileURLWithPath: "/tmp/album")
        let items = [item(name: "a.jpg", directory: folder), item(name: "b.jpg", directory: folder)]
        let plan = BatchRenameEngine().plan(items: items, pattern: "same", counterStart: 0, counterPadding: 1)
        #expect(!plan.collisions.isEmpty)
        #expect(!plan.canApply)
    }

    @Test("Existing files outside the rename set block a collision")
    func existingCollision() {
        let folder = URL(fileURLWithPath: "/tmp/album")
        let original = item(name: "original.jpg", directory: folder)
        let existing = folder.appendingPathComponent("taken.jpg", isDirectory: false).path.lowercased()
        let plan = BatchRenameEngine(existingPaths: [existing])
            .plan(items: [original], pattern: "taken", counterStart: 0, counterPadding: 1)
        #expect(plan.collisions.count == 1)
    }

    @Test("A swap of existing names is allowed by the two-phase renamer")
    func swapsAllowedByPlan() {
        let folder = URL(fileURLWithPath: "/tmp/album")
        let first = item(name: "a.jpg", directory: folder)
        let second = item(name: "b.jpg", directory: folder)
        let plan = BatchRenameEngine(existingPaths: [first.url.path.lowercased(), second.url.path.lowercased()])
            .plan(items: [first, second], pattern: "{counter}", counterStart: 1, counterPadding: 1)
        #expect(plan.collisions.isEmpty)
    }

    @Test("Name sanitization removes path separators")
    func sanitization() {
        #expect(BatchRenameEngine.sanitizedBase("a/b:c") == "a-b-c")
        #expect(BatchRenameEngine.sanitizedBase("  .hidden  ") == "hidden")
    }
}
