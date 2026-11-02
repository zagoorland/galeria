import Foundation

enum FinderTagError: LocalizedError {
    case cannotWrite(URL, Error)

    var errorDescription: String? {
        switch self {
        case .cannotWrite(let url, let error):
            "Could not update tags for “\(url.lastPathComponent)”. \(error.localizedDescription)"
        }
    }
}

/// Writes Finder tags to files. Ratings, flags and labels are stored as ordinary
/// Finder tags so they remain visible in Finder and survive a relaunch.
actor FinderTagService {
    func apply(tags: [String], to url: URL) throws -> [String] {
        let canonical = FinderTagCodec.canonical(tags)
        do {
            // URLResourceValues.tagNames is writable only on newer systems;
            // NSURL's resource value API has supported this since macOS 10.9.
            try (url as NSURL).setResourceValue(canonical, forKey: .tagNamesKey)
            return canonical
        } catch {
            throw FinderTagError.cannotWrite(url, error)
        }
    }

    func readTags(from url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }
}
