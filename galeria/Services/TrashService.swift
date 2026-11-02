import AppKit
import Foundation

struct TrashMapping: Hashable, Sendable {
    let originalURL: URL
    let trashedURL: URL
}

enum TrashServiceError: LocalizedError {
    case fileNotInTrash(URL)
    case originalLocationOccupied(URL)
    case missingParentFolder(URL)
    case partialFailure(restored: Int, total: Int, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fileNotInTrash(let url):
            "“\(url.lastPathComponent)” is no longer in the Trash."
        case .originalLocationOccupied(let url):
            "A file named “\(url.lastPathComponent)” already exists at the original location. It was not overwritten."
        case .missingParentFolder(let url):
            "The original folder for “\(url.lastPathComponent)” no longer exists."
        case .partialFailure(let restored, let total, _):
            "Only \(restored) of \(total) files could be restored."
        }
    }
}

protocol TrashProvider: Sendable {
    func recycle(_ urls: [URL]) async throws -> [TrashMapping]
}

struct WorkspaceTrashProvider: TrashProvider {
    func recycle(_ urls: [URL]) async throws -> [TrashMapping] {
        try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { mapping, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let result = mapping.map {
                    TrashMapping(originalURL: $0.key, trashedURL: $0.value)
                }
                continuation.resume(returning: result)
            }
        }
    }
}

/// Moves files to the system Trash and can restore them without overwriting.
actor TrashService {
    private let provider: any TrashProvider
    private let fileManager: FileManager

    init(provider: any TrashProvider = WorkspaceTrashProvider(), fileManager: FileManager = .default) {
        self.provider = provider
        self.fileManager = fileManager
    }

    func trash(_ urls: [URL]) async throws -> [TrashMapping] {
        let existing = urls.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return [] }
        return try await provider.recycle(existing).sorted {
            $0.originalURL.path.localizedStandardCompare($1.originalURL.path) == .orderedAscending
        }
    }

    /// Preflights every mapping before moving anything. Existing files are never overwritten.
    func restore(_ mappings: [TrashMapping]) throws {
        guard !mappings.isEmpty else { return }
        for mapping in mappings {
            guard fileManager.fileExists(atPath: mapping.trashedURL.path) else {
                throw TrashServiceError.fileNotInTrash(mapping.trashedURL)
            }
        }
        for mapping in mappings {
            guard !fileManager.fileExists(atPath: mapping.originalURL.path) else {
                throw TrashServiceError.originalLocationOccupied(mapping.originalURL)
            }
            guard fileManager.fileExists(atPath: mapping.originalURL.deletingLastPathComponent().path) else {
                throw TrashServiceError.missingParentFolder(mapping.originalURL.deletingLastPathComponent())
            }
        }

        var restored = 0
        do {
            for mapping in mappings {
                try fileManager.moveItem(at: mapping.trashedURL, to: mapping.originalURL)
                restored += 1
            }
        } catch {
            throw TrashServiceError.partialFailure(restored: restored, total: mappings.count, underlying: error)
        }
    }
}
