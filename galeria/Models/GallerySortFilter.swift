import Foundation
import Observation

enum GallerySortKey: String, CaseIterable, Codable, Sendable, Identifiable {
    case name
    case dateTaken
    case dateModified
    case dateAdded
    case fileSize
    case dimensions
    case type

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: "Name"
        case .dateTaken: "Date Taken"
        case .dateModified: "Date Modified"
        case .dateAdded: "Date Added"
        case .fileSize: "File Size"
        case .dimensions: "Dimensions"
        case .type: "File Type"
        }
    }
}

enum SortDirection: String, CaseIterable, Codable, Sendable {
    case ascending
    case descending

    var displayName: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }

    var systemImage: String {
        switch self {
        case .ascending: "arrow.up"
        case .descending: "arrow.down"
        }
    }
}

enum GalleryGrouping: String, CaseIterable, Codable, Sendable, Identifiable {
    case none
    case day
    case month

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .day: "Day"
        case .month: "Month"
        }
    }
}

enum OrientationFilter: String, CaseIterable, Codable, Sendable, Identifiable {
    case any
    case landscape
    case portrait
    case square

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any: "Any"
        case .landscape: "Landscape"
        case .portrait: "Portrait"
        case .square: "Square"
        }
    }

    func matches(_ item: ImageItem) -> Bool {
        switch self {
        case .any: true
        case .landscape: item.isLandscape
        case .portrait: item.isPortrait
        case .square: item.isSquare
        }
    }
}

enum FlagFilter: String, CaseIterable, Codable, Sendable, Identifiable {
    case any
    case picks
    case rejects
    case unflagged

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any: "Any Flag"
        case .picks: "Picks"
        case .rejects: "Rejects"
        case .unflagged: "Unflagged"
        }
    }

    func matches(_ item: ImageItem) -> Bool {
        switch self {
        case .any: true
        case .picks: item.isPick
        case .rejects: item.isReject
        case .unflagged: !item.isPick && !item.isReject
        }
    }
}

struct GalleryFilter: Hashable, Sendable {
    var formats: Set<ImageFormat> = []
    var orientation: OrientationFilter = .any
    var minimumWidth: Int = 0
    var minimumHeight: Int = 0
    var minimumRating: Int = 0
    var label: FinderColorLabel?
    var flag: FlagFilter = .any
    var searchText: String = ""
    var smartLabels: [URL: [String]] = [:]

    var isActive: Bool {
        !formats.isEmpty || orientation != .any || minimumWidth > 0 || minimumHeight > 0
            || minimumRating > 0 || label != nil || flag != .any || !searchText.isEmpty
    }

    var activeChips: [String] {
        var chips: [String] = []
        if !formats.isEmpty {
            chips.append(formats.sorted { $0.rawValue < $1.rawValue }.map(\.displayName).joined(separator: ", "))
        }
        if orientation != .any { chips.append(orientation.displayName) }
        if minimumWidth > 0 || minimumHeight > 0 {
            chips.append("≥ \(minimumWidth) × \(minimumHeight)")
        }
        if minimumRating > 0 { chips.append("Rating \(minimumRating)+") }
        if let label { chips.append(label.displayName) }
        if flag != .any { chips.append(flag.displayName) }
        if !searchText.isEmpty { chips.append("Search: \(searchText)") }
        return chips
    }

    func matches(_ item: ImageItem) -> Bool {
        if !formats.isEmpty && !formats.contains(item.format) { return false }
        if !orientation.matches(item) { return false }
        if item.pixelWidth < minimumWidth || item.pixelHeight < minimumHeight { return false }
        if item.rating < minimumRating { return false }
        if let label, item.label != label { return false }
        if !flag.matches(item) { return false }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let nameMatches = item.name.localizedStandardContains(query)
            let labels = smartLabels[item.url] ?? []
            let labelMatches = labels.contains { $0.localizedStandardContains(query) }
            if !nameMatches && !labelMatches { return false }
        }
        return true
    }
}

struct GallerySection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let date: Date?
    let items: [ImageItem]
}

/// Sort, filter and grouping state. This type never imports SwiftUI or AppKit.
@Observable
@MainActor
final class SortFilterModel {
    var sortKey: GallerySortKey = .name {
        didSet { if oldValue != sortKey { onChange?() } }
    }
    var direction: SortDirection = .ascending {
        didSet { if oldValue != direction { onChange?() } }
    }
    var filter = GalleryFilter()
    var grouping: GalleryGrouping = .none {
        didSet { if oldValue != grouping { onChange?() } }
    }

    /// Observers persist per-folder sort state without coupling this model to UserDefaults.
    @ObservationIgnored var onChange: (() -> Void)?

    func sections(for items: [ImageItem], calendar: Calendar = .current) -> [GallerySection] {
        let filtered = items.filter(filter.matches)
        let sorted = filtered.sorted(by: areInIncreasingOrder)
        guard grouping != .none else {
            return [GallerySection(id: "all", title: nil, date: nil, items: sorted)]
        }

        let grouped = Dictionary(grouping: sorted) { item -> Date? in
            let components: Set<Calendar.Component> = grouping == .day
                ? [.year, .month, .day]
                : [.year, .month]
            var value = calendar.dateComponents(components, from: item.captureDate)
            value.timeZone = calendar.timeZone
            return calendar.date(from: value)
        }

        let validKeys = grouped.keys.compactMap { $0 }
        let sortedKeys = validKeys.sorted(by: direction == .ascending ? (<) : (>))
        var sections = sortedKeys.map { date in
            GallerySection(
                id: "date-\(date.timeIntervalSince1970)",
                title: grouping == .day ? Self.dayFormatter.string(from: date) : Self.monthFormatter.string(from: date),
                date: date,
                items: grouped[date] ?? []
            )
        }
        if let unknown = grouped[nil], !unknown.isEmpty {
            sections.append(GallerySection(id: "unknown-date", title: "Unknown Date", date: nil, items: unknown))
        }
        return sections
    }

    func orderedItems(in sections: [GallerySection]) -> [ImageItem] {
        sections.flatMap(\.items)
    }

    private func areInIncreasingOrder(_ lhs: ImageItem, _ rhs: ImageItem) -> Bool {
        let comparison: ComparisonResult
        switch sortKey {
        case .name:
            comparison = lhs.name.localizedStandardCompare(rhs.name)
        case .dateTaken:
            comparison = Self.compare(lhs.captureDate, rhs.captureDate)
        case .dateModified:
            comparison = Self.compare(lhs.modifiedAt, rhs.modifiedAt)
        case .dateAdded:
            comparison = Self.compare(lhs.addedAt, rhs.addedAt)
        case .fileSize:
            comparison = Self.compare(lhs.fileSize, rhs.fileSize)
        case .dimensions:
            comparison = Self.compare(Double(lhs.pixelWidth * lhs.pixelHeight), Double(rhs.pixelWidth * rhs.pixelHeight))
        case .type:
            comparison = lhs.format.displayName.localizedStandardCompare(rhs.format.displayName)
        }
        if comparison == .orderedSame {
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            return direction == .ascending ? nameOrder == .orderedAscending : nameOrder == .orderedDescending
        }
        return direction == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()
}
