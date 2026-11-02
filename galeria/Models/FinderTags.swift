import Foundation

/// The Finder color tags use stable English names so they remain readable
/// across launches and can be inspected in Finder's Tags UI.
enum FinderColorLabel: String, CaseIterable, Codable, Sendable, Identifiable {
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case gray = "Gray"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .gray: "Gray"
        }
    }

    var systemImage: String {
        switch self {
        case .red: "circle.fill"
        default: "circle.fill"
        }
    }
}

/// Pure encoding for the Finder tags Galeria uses for ratings, flags and labels.
enum FinderTagCodec {
    static let ratingPrefix = "Rating "
    static let pickTag = "Pick"
    static let rejectTag = "Reject"
    static let flagTags: Set<String> = [pickTag, rejectTag]
    static let labelTags = Set(FinderColorLabel.allCases.map(\.rawValue))

    static func rating(from tags: [String]) -> Int {
        tags.compactMap { tag -> Int? in
            guard tag.hasPrefix(ratingPrefix),
                  let value = Int(tag.dropFirst(ratingPrefix.count)),
                  (1...5).contains(value)
            else { return nil }
            return value
        }
        .max() ?? 0
    }

    static func colorLabel(from tags: [String]) -> FinderColorLabel? {
        let labels = tags.compactMap(FinderColorLabel.init(rawValue:))
        return FinderColorLabel.allCases.first { labels.contains($0) }
    }

    static func isPick(_ tags: [String]) -> Bool { tags.contains(pickTag) }
    static func isReject(_ tags: [String]) -> Bool { tags.contains(rejectTag) }

    static func applyingRating(_ rating: Int, to tags: [String]) -> [String] {
        var result = tags.filter { !$0.hasPrefix(ratingPrefix) }
        if (1...5).contains(rating) {
            result.append("\(ratingPrefix)\(rating)")
        }
        return canonical(result)
    }

    static func applyingFlag(_ flag: ImageFlag, to tags: [String]) -> [String] {
        var result = tags.filter { !flagTags.contains($0) }
        switch flag {
        case .none: break
        case .pick: result.append(pickTag)
        case .reject: result.append(rejectTag)
        }
        return canonical(result)
    }

    static func applyingLabel(_ label: FinderColorLabel?, to tags: [String]) -> [String] {
        var result = tags.filter { !labelTags.contains($0) }
        if let label {
            result.append(label.rawValue)
        }
        return canonical(result)
    }

    /// Drops duplicates and keeps Finder's tag order (user tags, then our metadata).
    static func canonical(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

enum ImageFlag: String, Codable, CaseIterable, Sendable {
    case none
    case pick
    case reject

    var displayName: String {
        switch self {
        case .none: "Unflagged"
        case .pick: "Pick"
        case .reject: "Reject"
        }
    }
}
