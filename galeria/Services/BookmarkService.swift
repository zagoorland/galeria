import Foundation

struct BookmarkRecord: Codable, Hashable, Identifiable, Sendable {
    var id: String { path + "|" + date.timeIntervalSince1970.description }
    let data: Data
    let path: String
    let name: String
    let date: Date
}

struct ResolvedBookmark: Sendable {
    let url: URL
    let isStale: Bool
    let record: BookmarkRecord
}

enum BookmarkError: LocalizedError {
    case cannotCreateBookmark(String)
    case cannotResolve(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateBookmark(let path): "Could not save access to \(path)."
        case .cannotResolve(let path): "Could not reopen \(path). Choose the folder again to grant access."
        }
    }
}

/// Stores security-scoped folder bookmarks in UserDefaults. No other persistence layer is used.
@MainActor
final class BookmarkService {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    enum Key {
        static let lastFolder = "lastFolderBookmark"
        static let favorites = "favoriteFolderBookmarks"
        static let recents = "recentFolderBookmarks"
        static let moveDestinations = "moveDestinationBookmarks"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Security-scoped bookmarks

    func bookmarkData(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        } catch {
            throw BookmarkError.cannotCreateBookmark(url.lastPathComponent)
        }
    }

    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale)
            return (url, stale)
        } catch {
            throw BookmarkError.cannotResolve("the saved folder")
        }
    }

    // MARK: Last folder

    /// Saves a bookmark and returns it, so callers can refresh stale data later.
    @discardableResult
    func saveLastFolder(url: URL) throws -> BookmarkRecord {
        let data = try bookmarkData(for: url)
        let record = BookmarkRecord(data: data, path: url.path, name: url.lastPathComponent, date: Date())
        storeLastFolderRecord(record)
        addRecent(url: url, data: data)
        return record
    }

    func loadLastFolder() throws -> ResolvedBookmark? {
        guard let data = defaults.data(forKey: Key.lastFolder) else { return nil }
        let record = lastFolderRecord() ?? BookmarkRecord(data: data, path: "", name: "", date: Date())
        let resolved = try resolve(data)
        var current = record
        if resolved.isStale, let refreshed = try? bookmarkData(for: resolved.url) {
            current = BookmarkRecord(data: refreshed, path: resolved.url.path,
                                     name: resolved.url.lastPathComponent, date: Date())
            storeLastFolderRecord(current)
        }
        return ResolvedBookmark(url: resolved.url, isStale: resolved.isStale, record: current)
    }

    func clearLastFolder() {
        defaults.removeObject(forKey: Key.lastFolder)
        defaults.removeObject(forKey: Key.lastFolder + ".record")
    }

    /// Test seam and a useful recovery path after a stale bookmark is refreshed.
    func storeLastFolderRecord(_ record: BookmarkRecord) {
        defaults.set(record.data, forKey: Key.lastFolder)
        if let encoded = try? encoder.encode(record) {
            defaults.set(encoded, forKey: Key.lastFolder + ".record")
        }
    }

    func lastFolderRecord() -> BookmarkRecord? {
        guard let data = defaults.data(forKey: Key.lastFolder + ".record") else { return nil }
        return try? decoder.decode(BookmarkRecord.self, from: data)
    }

    // MARK: Recents and favorites

    func recentFolders() -> [BookmarkRecord] { records(forKey: Key.recents) }

    func favoriteFolders() -> [BookmarkRecord] { records(forKey: Key.favorites) }

    func moveDestinations() -> [BookmarkRecord] { records(forKey: Key.moveDestinations) }

    func isFavorite(_ url: URL) -> Bool {
        favoriteFolders().contains { $0.path == url.path }
    }

    @discardableResult
    func toggleFavorite(url: URL) throws -> Bool {
        var favorites = favoriteFolders()
        if let index = favorites.firstIndex(where: { $0.path == url.path }) {
            favorites.remove(at: index)
            save(favorites, forKey: Key.favorites)
            return false
        }
        let data = try bookmarkData(for: url)
        let record = BookmarkRecord(data: data, path: url.path,
                                    name: url.lastPathComponent, date: Date())
        favorites.insert(record, at: 0)
        save(Array(favorites.prefix(30)), forKey: Key.favorites)
        return true
    }

    func addRecent(url: URL, data: Data? = nil) {
        guard let bookmark = data ?? (try? bookmarkData(for: url)) else { return }
        var recents = recentFolders().filter { $0.path != url.path }
        recents.insert(BookmarkRecord(data: bookmark, path: url.path,
                                      name: url.lastPathComponent, date: Date()), at: 0)
        save(Array(recents.prefix(12)), forKey: Key.recents)
    }

    func addMoveDestination(url: URL) throws {
        let data = try bookmarkData(for: url)
        var destinations = moveDestinations().filter { $0.path != url.path }
        destinations.insert(BookmarkRecord(data: data, path: url.path,
                                           name: url.lastPathComponent, date: Date()), at: 0)
        save(Array(destinations.prefix(9)), forKey: Key.moveDestinations)
    }

    func removeRecord(_ record: BookmarkRecord, fromFavorites: Bool) {
        if fromFavorites {
            save(favoriteFolders().filter { $0.id != record.id }, forKey: Key.favorites)
        } else {
            save(recentFolders().filter { $0.id != record.id }, forKey: Key.recents)
        }
    }

    func resolvedURL(for record: BookmarkRecord) -> (URL, Bool)? {
        (try? resolve(record.data)).map { ($0.url, $0.isStale) }
    }

    // MARK: Storage helpers

    func records(forKey key: String) -> [BookmarkRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? decoder.decode([BookmarkRecord].self, from: data)) ?? []
    }

    func save(_ records: [BookmarkRecord], forKey key: String) {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
