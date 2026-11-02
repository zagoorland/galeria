import Foundation
import Observation

struct GalleryError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let recovery: Recovery

    enum Recovery: Equatable {
        case chooseFolder
        case retry
        case none
    }

    init(title: String, message: String, recovery: Recovery = .none) {
        self.title = title
        self.message = message
        self.recovery = recovery
    }
}

/// Owns the current folder, its live watch, and the raw scanned image list.
@Observable
@MainActor
final class FolderStore {
    private(set) var folderURL: URL?
    private(set) var attemptedURL: URL?
    private(set) var items: [ImageItem] = []
    private(set) var isScanning = false
    private(set) var error: GalleryError?
    private(set) var skippedCount = 0
    var includeSubfolders = false

    var folderName: String { folderURL?.lastPathComponent ?? "No Folder" }
    var itemCount: Int { items.count }

    @ObservationIgnored private let scanner = ImageScanner()
    @ObservationIgnored private let watcher = FolderWatcher()
    @ObservationIgnored private var accessHeld = false
    @ObservationIgnored private var accessURL: URL?
    @ObservationIgnored private var scannedURL: URL?
    @ObservationIgnored private var scanGeneration = UUID()
    @ObservationIgnored private var reloadIncludesSubfolders = false

    /// Called whenever the scanned collection changes, including live updates.
    @ObservationIgnored var onItemsChanged: (([ImageItem]) -> Void)?

    deinit {
        watcher.stop()
    }

    func openFolder(_ url: URL, includeSubfolders: Bool, requestSecurityScope: Bool = true) async {
        if scannedURL?.standardizedFileURL == url.standardizedFileURL {
            self.includeSubfolders = includeSubfolders
            await refresh(showLoading: items.isEmpty)
            return
        }

        watcher.stop()
        releaseSecurityScope()
        scanGeneration = UUID()
        let generation = scanGeneration
        self.includeSubfolders = includeSubfolders
        attemptedURL = url
        folderURL = url
        scannedURL = nil
        items = []
        onItemsChanged?([])
        isScanning = true
        error = nil
        skippedCount = 0

        if requestSecurityScope || url.isFileURL {
            accessHeld = url.startAccessingSecurityScopedResource()
            accessURL = accessHeld ? url : nil
        }

        do {
            var didReceiveFirstBatch = false
            let scanned = try await scanner.scan(
                folder: url,
                includeSubfolders: includeSubfolders,
                batchSize: 12
            ) { [weak self] batch in
                guard let self, generation == self.scanGeneration, !didReceiveFirstBatch else { return }
                didReceiveFirstBatch = true
                self.items = batch.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                self.onItemsChanged?(self.items)
            }
            guard generation == scanGeneration else { return }
            scannedURL = url
            folderURL = url
            items = scanned
            isScanning = false
            if scanned.isEmpty {
                error = nil
            }
            startWatching(url)
            onItemsChanged?(scanned)
        } catch {
            guard generation == scanGeneration else { return }
            isScanning = false
            folderURL = url
            items = []
            releaseSecurityScope()
            self.error = Self.galleryError(from: error)
            onItemsChanged?([])
        }
    }

    func refresh(showLoading: Bool = false) async {
        guard let folder = scannedURL else { return }
        let generation = UUID()
        scanGeneration = generation
        if showLoading { isScanning = true }
        do {
            let scanned = try await scanner.scan(folder: folder, includeSubfolders: includeSubfolders)
            guard generation == scanGeneration else { return }
            isScanning = false
            error = nil
            items = scanned
            skippedCount = 0
            onItemsChanged?(scanned)
        } catch {
            guard generation == scanGeneration else { return }
            isScanning = false
            self.error = Self.galleryError(from: error)
        }
    }

    func setIncludeSubfolders(_ include: Bool) async {
        guard include != includeSubfolders else { return }
        includeSubfolders = include
        guard let folderURL else { return }
        await openFolder(folderURL, includeSubfolders: include, requestSecurityScope: false)
    }

    func retry() async {
        guard let scannedURL else { return }
        await openFolder(scannedURL, includeSubfolders: includeSubfolders, requestSecurityScope: !accessHeld)
    }

    func close() {
        watcher.stop()
        releaseSecurityScope()
        scanGeneration = UUID()
        folderURL = nil
        attemptedURL = nil
        scannedURL = nil
        items = []
        error = nil
        isScanning = false
    }

    func removeItems(with urls: Set<URL>) {
        items.removeAll { urls.contains($0.url) }
        onItemsChanged?(items)
    }

    func updateTags(for url: URL, tags: [String]) {
        guard let index = items.firstIndex(where: { $0.url == url }) else { return }
        items[index] = items[index].replacingTags(tags)
        onItemsChanged?(items)
    }

    func item(for url: URL) -> ImageItem? {
        items.first { $0.url == url }
    }

    var availableURLs: Set<URL> { Set(items.map(\.url)) }

    private func startWatching(_ url: URL) {
        watcher.start(url: url) { [weak self] in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    private func releaseSecurityScope() {
        if accessHeld, let accessURL {
            accessURL.stopAccessingSecurityScopedResource()
        }
        accessHeld = false
        accessURL = nil
    }

    private static func galleryError(from error: Error) -> GalleryError {
        if let scanError = error as? FolderScanError {
            switch scanError {
            case .folderMissing:
                return GalleryError(title: "Folder Not Found",
                                    message: "The folder was moved, renamed, or deleted. Choose another folder to continue.",
                                    recovery: .chooseFolder)
            case .permissionDenied:
                return GalleryError(title: "Permission Needed",
                                    message: "Galeria no longer has permission to read this folder. Choose it again to restore access.",
                                    recovery: .chooseFolder)
            case .cannotRead(_, let message):
                return GalleryError(title: "Could Not Read Folder", message: message, recovery: .retry)
            }
        }
        return GalleryError(title: "Could Not Read Folder",
                            message: error.localizedDescription,
                            recovery: .retry)
    }
}
