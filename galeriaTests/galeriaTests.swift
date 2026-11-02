import Foundation
import Testing
@testable import galeria

struct ImageFormatTests {
    @Test("Known extensions map to formats")
    func extensionMapping() {
        #expect(ImageFormat.forExtension("JPG") == .jpeg)
        #expect(ImageFormat.forExtension("jpeg") == .jpeg)
        #expect(ImageFormat.forExtension("heic") == .heic)
        #expect(ImageFormat.forExtension("webp") == .webp)
        #expect(ImageFormat.forExtension("dng") == .dng)
        #expect(ImageFormat.forExtension("txt") == nil)
        #expect(ImageFormat.rawCases)
    }

    @Test("RAW extensions are recognized but not lossless-rotatable")
    func rawFormats() {
        let rawExtensions = ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"]
        for ext in rawExtensions {
            let format = ImageFormat.forExtension(ext)
            #expect(format?.isRaw == true, "Expected \(ext) to be RAW")
            #expect(format?.supportsLosslessRotation == false)
        }
        #expect(ImageFormat.jpeg.supportsLosslessRotation)
    }
}

private extension ImageFormat {
    static var rawCases: Bool {
        ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"]
            .allSatisfy { ImageFormat.forExtension($0)?.isRaw == true }
    }
}

@MainActor
struct BookmarkPersistenceTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "galeria.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Last-folder record persists and clears")
    func lastFolderRecord() throws {
        let defaults = try makeDefaults()
        let service = BookmarkService(defaults: defaults)
        let record = BookmarkRecord(data: Data("bookmark".utf8),
                                    path: "/tmp/photos",
                                    name: "photos",
                                    date: Date(timeIntervalSince1970: 123))
        service.storeLastFolderRecord(record)
        let loaded = try #require(service.lastFolderRecord())
        #expect(loaded.path == record.path)
        #expect(loaded.name == record.name)
        #expect(loaded.data == record.data)
        #expect(defaults.data(forKey: BookmarkService.Key.lastFolder) == record.data)
        service.clearLastFolder()
        #expect(service.lastFolderRecord() == nil)
        #expect(defaults.data(forKey: BookmarkService.Key.lastFolder) == nil)
    }

    @Test("Favorites and recents encode and decode")
    func collectionsRoundTrip() throws {
        let defaults = try makeDefaults()
        let service = BookmarkService(defaults: defaults)
        let first = BookmarkRecord(data: Data("one".utf8), path: "/a", name: "A", date: Date(timeIntervalSince1970: 1))
        let second = BookmarkRecord(data: Data("two".utf8), path: "/b", name: "B", date: Date(timeIntervalSince1970: 2))
        service.save([first, second], forKey: BookmarkService.Key.favorites)
        #expect(service.favoriteFolders() == [first, second])
        #expect(service.records(forKey: BookmarkService.Key.recents).isEmpty)
    }
}

@MainActor
struct SortFilterTests {
    private func item(_ name: String, size: Int64 = 100, created: Date = .distantPast,
                      width: Int = 100, height: Int = 100, rating: Int = 0,
                      format: ImageFormat = .jpeg) -> ImageItem {
        ImageItem(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, fileSize: size,
                  createdAt: created, modifiedAt: created, addedAt: created,
                  pixelWidth: width, pixelHeight: height, format: format, tags: [],
                  exifCaptureDate: nil, cameraMake: nil, cameraModel: nil, lens: nil,
                  iso: nil, aperture: nil, exposureTime: nil, focalLength: nil,
                  latitude: nil, longitude: nil, orientation: 1)
    }

    @Test("Name sort is natural and direction-aware")
    func nameSort() {
        let model = SortFilterModel()
        let items = [item("Image 10"), item("Image 2"), item("image 1")]
        #expect(model.sections(for: items).first?.items.map(\.name) == ["image 1", "Image 2", "Image 10"])
        model.direction = .descending
        #expect(model.sections(for: items).first?.items.map(\.name) == ["Image 10", "Image 2", "image 1"])
    }

    @Test("Filters compose")
    func filters() {
        let model = SortFilterModel()
        let items = [
            item("wide.jpg", width: 300, height: 150, format: .jpeg),
            item("tall.png", width: 150, height: 300, format: .png),
            item("small.jpg", width: 80, height: 80, format: .jpeg)
        ]
        model.filter.orientation = .portrait
        #expect(model.sections(for: items).first?.items.map(\.name) == ["tall.png"])
        model.filter.orientation = .any
        model.filter.minimumWidth = 100
        model.filter.formats = [.jpeg]
        #expect(model.sections(for: items).first?.items.map(\.name) == ["wide.jpg"])
    }

    @Test("Search matches file names")
    func search() {
        let model = SortFilterModel()
        let items = [item("beach.jpg"), item("forest.heic"), item("mountain.jpeg")]
        model.filter.searchText = "for"
        #expect(model.sections(for: items).first?.items.map(\.name) == ["forest.heic"])
    }
}
