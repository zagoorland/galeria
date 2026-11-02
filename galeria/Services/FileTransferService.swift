import Foundation

enum TransferMode: String, Sendable {
    case move
    case copy

    var displayName: String {
        switch self {
        case .move: "Move"
        case .copy: "Copy"
        }
    }
}

struct TransferMapping: Hashable, Sendable {
    let originalURL: URL
    let destinationURL: URL
}

enum FileTransferError: LocalizedError {
    case destinationMissing(URL)
    case sourceMissing(URL)
    case sameFolder
    case noWritableAccess(URL)

    var errorDescription: String? {
        switch self {
        case .destinationMissing: "The destination folder is unavailable."
        case .sourceMissing(let url): "“\(url.lastPathComponent)” no longer exists."
        case .sameFolder: "The images are already in that folder."
        case .noWritableAccess(let url): "Galeria cannot write to “\(url.lastPathComponent)”. Choose it again to grant access."
        }
    }
}

/// Copies or moves files without ever overwriting an existing destination.
actor FileTransferService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func transfer(_ urls: [URL], to destination: URL, mode: TransferMode) throws -> [TransferMapping] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileTransferError.destinationMissing(destination)
        }
        guard fileManager.isWritableFile(atPath: destination.path) else {
            throw FileTransferError.noWritableAccess(destination)
        }
        for url in urls where !fileManager.fileExists(atPath: url.path) {
            throw FileTransferError.sourceMissing(url)
        }
        if urls.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL }) {
            throw FileTransferError.sameFolder
        }

        var mappings: [TransferMapping] = []
        do {
            for url in urls {
                if url.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL {
                    continue
                }
                let target = Self.availableURL(for: url.lastPathComponent, in: destination, fileManager: fileManager)
                switch mode {
                case .move:
                    try fileManager.moveItem(at: url, to: target)
                case .copy:
                    try fileManager.copyItem(at: url, to: target)
                }
                mappings.append(TransferMapping(originalURL: url, destinationURL: target))
            }
        } catch {
            if mode == .move {
                for mapping in mappings {
                    try? fileManager.moveItem(at: mapping.destinationURL, to: mapping.originalURL)
                }
            } else {
                for mapping in mappings {
                    try? fileManager.removeItem(at: mapping.destinationURL)
                }
            }
            throw error
        }
        return mappings
    }

    func moveBack(_ mappings: [TransferMapping]) throws {
        for mapping in mappings where fileManager.fileExists(atPath: mapping.destinationURL.path) {
            guard !fileManager.fileExists(atPath: mapping.originalURL.path) else {
                throw TrashServiceError.originalLocationOccupied(mapping.originalURL)
            }
            try fileManager.moveItem(at: mapping.destinationURL, to: mapping.originalURL)
        }
    }

    /// Returns a Finder-style non-colliding name, e.g. “Photo 2.jpg”.
    nonisolated static func availableURL(for name: String, in directory: URL, fileManager: FileManager = .default) -> URL {
        let initial = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }
        let ext = initial.pathExtension
        let base = initial.deletingPathExtension().lastPathComponent
        var counter = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
            if counter > 9999 { return directory.appendingPathComponent(UUID().uuidString) }
        }
    }
}
