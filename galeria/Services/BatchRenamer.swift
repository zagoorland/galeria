import Foundation

enum BatchRenameError: LocalizedError {
    case sourceMissing(URL)
    case destinationExists(URL)
    case duplicateDestination(URL)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let url): "“\(url.lastPathComponent)” no longer exists."
        case .destinationExists(let url): "A file named “\(url.lastPathComponent)” already exists."
        case .duplicateDestination(let url): "More than one file would be renamed to “\(url.lastPathComponent)”."
        case .failed(let message): "The rename could not be completed. \(message)"
        }
    }
}

/// Renames through temporary names so swaps and overlapping names are safe.
actor BatchRenamer {
    private let fileManager = FileManager.default

    func apply(_ changes: [RenameChange]) throws {
        let effective = changes.filter { !$0.isNoop }
        guard !effective.isEmpty else { return }
        let originalPaths = Set(effective.map { $0.originalURL.standardizedFileURL.path.lowercased() })
        var seen: Set<String> = []
        for change in effective {
            guard fileManager.fileExists(atPath: change.originalURL.path) else {
                throw BatchRenameError.sourceMissing(change.originalURL)
            }
            let key = change.renamedURL.standardizedFileURL.path.lowercased()
            guard seen.insert(key).inserted else {
                throw BatchRenameError.duplicateDestination(change.renamedURL)
            }
            if fileManager.fileExists(atPath: change.renamedURL.path),
               change.originalURL.standardizedFileURL != change.renamedURL.standardizedFileURL,
               !originalPaths.contains(key) {
                throw BatchRenameError.destinationExists(change.renamedURL)
            }
        }

        var temporaries: [(original: URL, temporary: URL)] = []
        do {
            for change in effective {
                let ext = change.originalURL.pathExtension
                let temp = change.originalURL.deletingLastPathComponent()
                    .appendingPathComponent(".galeria-rename-\(UUID().uuidString)\(ext.isEmpty ? "" : ".\(ext)")")
                try fileManager.moveItem(at: change.originalURL, to: temp)
                temporaries.append((change.originalURL, temp))
            }
            for (index, change) in effective.enumerated() {
                try fileManager.moveItem(at: temporaries[index].temporary, to: change.renamedURL)
            }
        } catch {
            // Roll completed destinations back to their originals, then put any
            // remaining temporary files back where they came from.
            for (index, change) in effective.enumerated() where index < effective.count {
                let destination = change.renamedURL
                if fileManager.fileExists(atPath: destination.path),
                   !fileManager.fileExists(atPath: change.originalURL.path) {
                    try? fileManager.moveItem(at: destination, to: change.originalURL)
                }
            }
            for entry in temporaries where fileManager.fileExists(atPath: entry.temporary.path) {
                if !fileManager.fileExists(atPath: entry.original.path) {
                    try? fileManager.moveItem(at: entry.temporary, to: entry.original)
                }
            }
            throw BatchRenameError.failed(error.localizedDescription)
        }
    }
}
