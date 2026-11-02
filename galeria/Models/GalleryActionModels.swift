import Foundation

struct TagChange: Hashable, Sendable {
    let url: URL
    let oldTags: [String]
    let newTags: [String]
}

struct TagChangeBatch: Sendable {
    let name: String
    let changes: [TagChange]
}

struct BatchRenameChange: Hashable, Sendable {
    let originalURL: URL
    let renamedURL: URL
}

enum RotationDirection: String, Sendable {
    case left
    case right

    var displayName: String {
        switch self {
        case .left: "Rotate Left"
        case .right: "Rotate Right"
        }
    }
}
