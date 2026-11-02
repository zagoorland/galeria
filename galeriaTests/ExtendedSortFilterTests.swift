import Foundation
import Testing
@testable import galeria

@MainActor
struct ExtendedSortFilterTests {
    private func item(_ name: String, size: Int64 = 100,
                      created: Date = Date(timeIntervalSince1970: 0),
                      modified: Date? = nil,
                      width: Int = 100, height: Int = 100,
                      format: ImageFormat = .jpeg,
                      tags: [String] = []) -> ImageItem {
        ImageItem(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, fileSize: size,
                  createdAt: created, modifiedAt: modified ?? created, addedAt: created,
                  pixelWidth: width, pixelHeight: height, format: format, tags: tags,
                  exifCaptureDate: nil, cameraMake: nil, cameraModel: nil, lens: nil,
                  iso: nil, aperture: nil, exposureTime: nil, focalLength: nil,
                  latitude: nil, longitude: nil, orientation: 1)
    }

    @Test("Date, size, dimension and type sorts work in both directions")
    func numericSorts() {
        let model = SortFilterModel()
        let jan = Date(timeIntervalSince1970: 1_000)
        let feb = Date(timeIntervalSince1970: 2_000)
        let items = [
            item("small.png", size: 10, created: feb, width: 20, height: 20, format: .png),
            item("large.jpg", size: 300, created: jan, width: 400, height: 200, format: .jpeg),
            item("medium.heic", size: 100, created: jan, width: 100, height: 100, format: .heic)
        ]

        model.sortKey = .dateModified
        #expect(model.sections(for: items).first?.items.map(\.name) == ["large.jpg", "medium.heic", "small.png"])

        model.sortKey = .fileSize
        model.direction = .descending
        #expect(model.sections(for: items).first?.items.map(\.name) == ["large.jpg", "medium.heic", "small.png"])

        model.sortKey = .dimensions
        model.direction = .ascending
        #expect(model.sections(for: items).first?.items.map(\.name) == ["small.png", "medium.heic", "large.jpg"])

        model.sortKey = .type
        #expect(model.sections(for: items).first?.items.map(\.name) == ["medium.heic", "large.jpg", "small.png"])
    }

    @Test("Unflagged, rating and label filters match Finder tags")
    func metadataFilters() {
        let model = SortFilterModel()
        let rated = item("rated.jpg", tags: FinderTagCodec.applyingRating(4, to: ["Trip"]))
        let rejected = item("rejected.jpg", tags: FinderTagCodec.applyingFlag(.reject, to: []))
        let green = item("green.jpg", tags: FinderTagCodec.applyingLabel(.green, to: []))

        model.filter.minimumRating = 4
        #expect(model.sections(for: [rated, rejected, green]).first?.items.map(\.name) == ["rated.jpg"])
        model.filter.minimumRating = 0
        model.filter.flag = .rejects
        #expect(model.sections(for: [rated, rejected, green]).first?.items.map(\.name) == ["rejected.jpg"])
        model.filter.flag = .any
        model.filter.label = .green
        #expect(model.sections(for: [rated, rejected, green]).first?.items.map(\.name) == ["green.jpg"])
    }

    @Test("Content labels participate in search")
    func smartSearch() {
        let model = SortFilterModel()
        let beach = item("IMG_0001.jpg")
        let dog = item("IMG_0002.jpg")
        model.filter.smartLabels = [beach.url: ["beach", "ocean"], dog.url: ["dog", "pet"]]
        model.filter.searchText = "ocean"
        #expect(model.sections(for: [beach, dog]).first?.items.map(\.name) == ["IMG_0001.jpg"])
        model.filter.searchText = "IMG_0002"
        #expect(model.sections(for: [beach, dog]).first?.items.map(\.name) == ["IMG_0002.jpg"])
    }

    @Test("Month and day grouping creates dated sections")
    func grouping() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 2)) ?? Date()
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)) ?? Date()
        let day3 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)) ?? Date()
        let items = [item("a.jpg", created: day1), item("b.jpg", created: day2), item("c.jpg", created: day3)]
        let model = SortFilterModel()
        model.grouping = .month
        let monthSections = model.sections(for: items, calendar: calendar)
        #expect(monthSections.count == 2)
        #expect(monthSections.allSatisfy { $0.title != nil })
        model.grouping = .day
        #expect(model.sections(for: items, calendar: calendar).count == 3)
    }

    @Test("Filter chips describe active filters")
    func chips() {
        let model = SortFilterModel()
        model.filter.orientation = .landscape
        model.filter.minimumRating = 3
        model.filter.formats = [.jpeg]
        #expect(model.filter.activeChips.count == 3)
        #expect(model.filter.isActive)
    }
}
