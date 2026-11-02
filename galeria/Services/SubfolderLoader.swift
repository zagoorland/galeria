import Foundation

struct SidebarSubfolder: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    var id: URL { url }
}

/// Lazily lists child folders for the sidebar tree, off the main actor.
actor SubfolderLoader {
    private let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .isPackageKey, .nameKey]

    func subfolders(of folder: URL) async -> [SidebarSubfolder] {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(at: folder,
                                                                  includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        var results: [SidebarSubfolder] = []
        for url in children {
            if Task.isCancelled { return [] }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true,
                  values.isHidden != true,
                  values.isPackage != true
            else { continue }
            results.append(SidebarSubfolder(url: url,
                                            name: values.name ?? url.lastPathComponent))
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
