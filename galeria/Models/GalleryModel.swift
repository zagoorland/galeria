import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The main window's state coordinator. File and image work live in separate
/// services; this type owns the folder session, selection and view preferences.
@Observable
@MainActor
final class GalleryModel {
    let folderStore: FolderStore
    let selection: SelectionModel
    let sortFilter: SortFilterModel
    let bookmarkService: BookmarkService
    let thumbnailService: ThumbnailService
    let trashService: TrashService
    let fileTransferService: FileTransferService
    let tagService: FinderTagService
    let rotationService: ImageRotationService
    let previewImageService: PreviewImageService
    let subfolderLoader: SubfolderLoader
    let batchRenamer: BatchRenamer
    let exportService: ExportService
    let duplicateFinder: DuplicateFinder
    let visionIndexService: VisionIndexService
    let undoJournal: UndoJournal
    var smartIndexingEnabled: Bool {
        didSet {
            guard smartIndexingEnabled != oldValue else { return }
            UserDefaults.standard.set(smartIndexingEnabled, forKey: PreferenceKey.smartIndexing)
            if smartIndexingEnabled {
                scheduleSmartIndexing(force: true)
            } else {
                indexingTask?.cancel()
                isIndexing = false
                sortFilter.filter.smartLabels = [:]
                smartIndexProgress = 0
            }
        }
    }
    var isIndexing = false
    var smartIndexProgress: Double = 0

    var density: Int {
        didSet {
            let clamped = min(max(density, 1), 10)
            if clamped != density {
                density = clamped
                return
            }
            persistDensity()
        }
    }
    var usesOriginalAspect: Bool {
        didSet { UserDefaults.standard.set(usesOriginalAspect, forKey: PreferenceKey.usesOriginalAspect) }
    }
    var showMetadataOverlays: Bool {
        didSet { UserDefaults.standard.set(showMetadataOverlays, forKey: PreferenceKey.showMetadataOverlays) }
    }
    var includeSubfolders: Bool {
        didSet { UserDefaults.standard.set(includeSubfolders, forKey: PreferenceKey.includeSubfolders) }
    }
    var thumbnailQuality: ThumbnailQuality {
        didSet { UserDefaults.standard.set(thumbnailQuality.rawValue, forKey: PreferenceKey.thumbnailQuality) }
    }

    var isDropTargeted = false
    var presentedError: GalleryError?
    var sidebarRevision = 0
    var sidebarVisibility: NavigationSplitViewVisibility = .all
    var hasRestoredLastFolder = false
    var previewURL: URL?
    var previewItems: [ImageItem] = []
    var previewIndex: Int?
    var previewIsFit = true
    var previewZoomScale: CGFloat = 1
    var previewFitScale: CGFloat = 1
    var previewShowFilmstrip: Bool {
        didSet { UserDefaults.standard.set(previewShowFilmstrip, forKey: PreferenceKey.filmstripVisible) }
    }
    var previewInfoVisible = false
    var previewLiveTextEnabled: Bool {
        didSet { UserDefaults.standard.set(previewLiveTextEnabled, forKey: PreferenceKey.liveTextEnabled) }
    }
    var isComparePresented = false
    var compareItems: [ImageItem] = []
    var isSlideshowActive = false
    var isSlideshowPlaying = false
    var showRenameSheet = false
    var renameTargets: [ImageItem] = []
    var showExportSheet = false
    var exportTargets: [ImageItem] = []
    var showDuplicateFinder = false
    var isCullMode = false
    var showRejectedReview = false
    var showMapView = false
    var slideshowInterval: Double {
        didSet { UserDefaults.standard.set(slideshowInterval, forKey: PreferenceKey.slideshowInterval) }
    }
    var infoItem: ImageItem?

    @ObservationIgnored weak var galleryWindow: NSWindow?
    @ObservationIgnored private var isRestoringPreferences = false
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored var sharingPicker: NSSharingServicePicker?
    @ObservationIgnored var slideshowEnteredFullscreen = false
    @ObservationIgnored private var indexingTask: Task<Void, Never>?
    @ObservationIgnored private var indexingDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var lastSmartIndexSignature = ""

    init(defaults: UserDefaults = .standard,
         bookmarkService: BookmarkService? = nil,
         thumbnailService: ThumbnailService? = nil) {
        PreferenceDefaults.registerDefaults()
        let bookmarkService = bookmarkService ?? BookmarkService(defaults: defaults)
        self.bookmarkService = bookmarkService
        self.thumbnailService = thumbnailService ?? ThumbnailService()
        self.trashService = TrashService()
        self.fileTransferService = FileTransferService()
        self.tagService = FinderTagService()
        self.rotationService = ImageRotationService()
        self.previewImageService = PreviewImageService()
        self.subfolderLoader = SubfolderLoader()
        self.batchRenamer = BatchRenamer()
        self.exportService = ExportService()
        self.duplicateFinder = DuplicateFinder()
        self.visionIndexService = VisionIndexService()
        self.undoJournal = UndoJournal()
        self.folderStore = FolderStore()
        self.selection = SelectionModel()
        self.sortFilter = SortFilterModel()
        self.density = defaults.object(forKey: PreferenceKey.defaultDensity) as? Int ?? PreferenceDefaults.density
        self.usesOriginalAspect = defaults.bool(forKey: PreferenceKey.usesOriginalAspect)
        self.showMetadataOverlays = defaults.object(forKey: PreferenceKey.showMetadataOverlays) as? Bool ?? true
        self.includeSubfolders = defaults.bool(forKey: PreferenceKey.includeSubfolders)
        self.thumbnailQuality = ThumbnailQuality(rawValue: defaults.string(forKey: PreferenceKey.thumbnailQuality) ?? "") ?? .medium
        self.previewShowFilmstrip = defaults.object(forKey: PreferenceKey.filmstripVisible) as? Bool ?? true
        self.previewLiveTextEnabled = defaults.bool(forKey: PreferenceKey.liveTextEnabled)
        self.slideshowInterval = defaults.object(forKey: PreferenceKey.slideshowInterval) as? Double ?? PreferenceDefaults.slideshowInterval
        self.smartIndexingEnabled = defaults.bool(forKey: PreferenceKey.smartIndexing)
        self.folderStore.includeSubfolders = self.includeSubfolders

        sortFilter.sortKey = GallerySortKey(rawValue: defaults.string(forKey: PreferenceKey.defaultSortKey) ?? "") ?? .name
        sortFilter.direction = SortDirection(rawValue: defaults.string(forKey: PreferenceKey.defaultSortDirection) ?? "") ?? .ascending
        sortFilter.onChange = { [weak self] in self?.persistSortFilter() }

        folderStore.onItemsChanged = { [weak self] items in
            self?.folderItemsDidChange(items)
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    // MARK: Derived state

    var sections: [GallerySection] {
        sortFilter.sections(for: folderStore.items)
    }

    var orderedItems: [ImageItem] {
        sortFilter.orderedItems(in: sections)
    }

    var selectedItems: [ImageItem] {
        orderedItems.filter { selection.isSelected($0.url) }
    }

    var selectedURLs: Set<URL> { selection.selectedIDs }

    var selectedTotalSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.fileSize }
    }

    var folderDisplayName: String {
        folderStore.folderURL?.lastPathComponent ?? "Galeria"
    }

    var filteredItemCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    var currentFolderPath: String {
        folderStore.folderURL?.path ?? "No folder selected"
    }

    var activeFilterChips: [String] { sortFilter.filter.activeChips }

    var favoriteRecords: [BookmarkRecord] {
        _ = sidebarRevision
        return bookmarkService.favoriteFolders()
    }

    var recentRecords: [BookmarkRecord] {
        _ = sidebarRevision
        return bookmarkService.recentFolders()
    }

    var moveDestinationRecords: [BookmarkRecord] {
        _ = sidebarRevision
        return bookmarkService.moveDestinations()
    }

    var isCurrentFolderFavorite: Bool {
        guard let url = folderStore.folderURL else { return false }
        _ = sidebarRevision
        return bookmarkService.isFavorite(url)
    }

    // MARK: Session lifecycle

    func start() async {
        guard !hasRestoredLastFolder else { return }
        hasRestoredLastFolder = true

        if let sample = ProcessInfo.processInfo.environment["GALERIA_SAMPLE_FOLDER"],
           !sample.isEmpty {
            await openFolder(URL(fileURLWithPath: sample, isDirectory: true), saveBookmark: false)
            return
        }

        do {
            if let resolved = try bookmarkService.loadLastFolder() {
                await openFolder(resolved.url, saveBookmark: false)
                if resolved.isStale, folderStore.error == nil {
                    _ = try? bookmarkService.saveLastFolder(url: resolved.url)
                } else {
                    bookmarkService.addRecent(url: resolved.url)
                }
                sidebarRevision += 1
            }
        } catch {
            bookmarkService.clearLastFolder()
            presentedError = GalleryError(
                title: "Could Not Reopen Folder",
                message: "The saved folder access is no longer valid. Choose a folder to continue.",
                recovery: .chooseFolder
            )
        }
    }

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open a Folder of Images"
        panel.prompt = "Open Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        if let folder = folderStore.folderURL {
            panel.directoryURL = folder.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await openFolder(url) }
    }

    func openFolder(_ url: URL, saveBookmark: Bool = true) async {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            presentedError = GalleryError(title: "Not a Folder",
                                          message: "Drop a folder, not a file, to open it in Galeria.")
            return
        }

        closeAllOverlays()
        selection.clear()
        sortFilter.filter = GalleryFilter()
        restoreFolderPreferences(for: url)
        await folderStore.openFolder(url, includeSubfolders: includeSubfolders)
        sidebarRevision += 1

        scheduleSmartIndexing(force: true)
        if folderStore.error == nil {
            if saveBookmark {
                do {
                    try bookmarkService.saveLastFolder(url: url)
                } catch {
                    presentedError = GalleryError(title: "Folder Access Not Saved",
                                                  message: error.localizedDescription)
                }
            }
        } else {
            presentedError = folderStore.error
        }
    }

    func retryFolder() async {
        await folderStore.retry()
        if let error = folderStore.error { presentedError = error }
    }

    func chooseAnotherFolder() {
        openFolderPanel()
    }

    func openParentFolder() {
        guard let current = folderStore.folderURL else { return }
        let parent = current.deletingLastPathComponent()
        guard parent.path != current.path else { return }
        Task { await openFolder(parent) }
    }

    func openBookmarkRecord(_ record: BookmarkRecord) {
        guard let resolved = bookmarkService.resolvedURL(for: record) else {
            presentedError = GalleryError(title: "Folder Unavailable",
                                          message: "This bookmark can no longer be opened. Choose the folder again.")
            return
        }
        Task { await openFolder(resolved.0) }
    }

    func toggleFavoriteCurrentFolder() {
        guard let url = folderStore.folderURL else { return }
        do {
            _ = try bookmarkService.toggleFavorite(url: url)
            sidebarRevision += 1
        } catch {
            presentedError = GalleryError(title: "Could Not Pin Folder", message: error.localizedDescription)
        }
    }

    func handleOpenedURLs(_ urls: [URL]) async {
        let fileManager = FileManager.default
        if let folder = urls.first(where: { url in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }) {
            await openFolder(folder)
            return
        }
        if let image = urls.first(where: { ImageFormat.forExtension($0.pathExtension) != nil }) {
            let folder = image.deletingLastPathComponent()
            await openFolder(folder)
            selection.selectOnly(image)
            return
        }
        await handleDroppedURLs(urls)
    }

    func handleDroppedURLs(_ urls: [URL]) async {
        let fileManager = FileManager.default
        if let folder = urls.first(where: { url in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }) {
            await openFolder(folder)
            return
        }
        let images = urls.filter { ImageFormat.forExtension($0.pathExtension) != nil }
        guard !images.isEmpty else { return }
        if folderStore.folderURL == nil,
           let parent = images.first?.deletingLastPathComponent() {
            await openFolder(parent)
            await importImages(images, into: parent)
        } else if let folder = folderStore.folderURL {
            await importImages(images, into: folder)
        }
    }

    /// Copies files dropped from Finder into the current folder without overwriting.
    func importImages(_ urls: [URL], into folder: URL) async {
        let sources = urls.filter { ImageFormat.forExtension($0.pathExtension) != nil }
        guard !sources.isEmpty else { return }
        let accesses = sources.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer {
            for (url, accessed) in accesses where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let mappings = try await fileTransferService.transfer(sources, to: folder, mode: .copy)
            await folderStore.refresh()
            let imported = Set(mappings.map(\.destinationURL))
            if !imported.isEmpty {
                selection.setSelection(imported, anchor: mappings.first?.destinationURL)
            }
        } catch {
            presentedError = GalleryError(title: "Could Not Add Images", message: error.localizedDescription)
        }
    }

    // MARK: Density & selection

    func setDensity(_ value: Int) {
        density = min(max(value, 1), 10)
    }

    func adjustDensity(by delta: Int) {
        setDensity(density + delta)
    }

    func updateSelectionFromGrid(_ ids: Set<URL>) {
        let order = orderedItems.map(\.url)
        selection.syncFromCollectionView(ids, order: order)
    }

    func updateSelection(_ ids: Set<URL>) {
        let order = orderedItems.map(\.url)
        selection.syncFromCollectionView(ids, order: order)
    }

    func selectAll() {
        selection.selectAll(orderedItems.map(\.url))
    }

    func clearSelection() {
        selection.clear()
    }

    func clearFilters() {
        sortFilter.filter = GalleryFilter()
        reconcileSelectionWithVisibleItems()
    }

    func reconcileSelectionWithVisibleItems() {
        let visible = Set(sections.flatMap(\.items).map(\.url))
        selection.retainOnly(available: visible)
    }

    func setSortKey(_ key: GallerySortKey) {
        sortFilter.sortKey = key
    }

    func toggleSortDirection() {
        sortFilter.direction = sortFilter.direction == .ascending ? .descending : .ascending
    }

    func setIncludeSubfolders(_ enabled: Bool) async {
        includeSubfolders = enabled
        guard folderStore.folderURL != nil else { return }
        await folderStore.setIncludeSubfolders(enabled)
    }

    func focusSearchRequested() {
        NotificationCenter.default.post(name: .galeriaFocusSearch, object: nil)
    }

    // MARK: Smart indexing

    /// Debounced so a burst of live folder events does not restart classification repeatedly.
    func scheduleSmartIndexing(force: Bool = false) {
        indexingDebounceTask?.cancel()
        guard smartIndexingEnabled, folderStore.folderURL != nil, !folderStore.items.isEmpty else {
            if !smartIndexingEnabled { sortFilter.filter.smartLabels = [:] }
            return
        }
        let signature = folderStore.items.map { "\($0.url.path)|\($0.modifiedAt.timeIntervalSince1970)" }.joined(separator: "|")
        if !force, signature == lastSmartIndexSignature, !sortFilter.filter.smartLabels.isEmpty {
            return
        }
        lastSmartIndexSignature = signature
        indexingDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self else { return }
            await self.runSmartIndexing()
        }
    }

    private func runSmartIndexing() async {
        indexingTask?.cancel()
        guard smartIndexingEnabled, folderStore.folderURL != nil else { return }
        let items = folderStore.items
        guard !items.isEmpty else { return }
        let service = visionIndexService
        let cached = await service.cachedLabels(for: items)
        if !cached.isEmpty { sortFilter.filter.smartLabels = cached }
        isIndexing = true
        smartIndexProgress = 0
        let task = Task { [weak self] in
            guard let self else { return }
            let all = await service.index(items: items) { completed, total in
                self.smartIndexProgress = total == 0 ? 1 : Double(completed) / Double(total)
            }
            guard !Task.isCancelled else { return }
            self.sortFilter.filter.smartLabels = all
            self.isIndexing = false
            self.smartIndexProgress = 1
        }
        indexingTask = task
        await task.value
    }

    // MARK: Persistence

    private func folderItemsDidChange(_ items: [ImageItem]) {
        selection.retainOnly(available: Set(items.map(\.url)))
        if selection.isEmpty, let anchor = selection.anchorID, !items.contains(where: { $0.url == anchor }) {
            selection.clear()
        }
        refreshPreviewAfterFolderChange()
        scheduleSmartIndexing()
    }

    private func restoreFolderPreferences(for url: URL) {
        isRestoringPreferences = true
        defer { isRestoringPreferences = false }
        let defaults = UserDefaults.standard
        let path = url.standardizedFileURL.path
        if let stored = defaults.object(forKey: PreferenceKey.density(for: path)) as? Int {
            density = min(max(stored, 1), 10)
        } else {
            density = defaults.object(forKey: PreferenceKey.defaultDensity) as? Int ?? PreferenceDefaults.density
        }
        if let raw = defaults.string(forKey: PreferenceKey.sortKey(for: path)),
           let key = GallerySortKey(rawValue: raw) {
            sortFilter.sortKey = key
        } else {
            sortFilter.sortKey = GallerySortKey(rawValue: defaults.string(forKey: PreferenceKey.defaultSortKey) ?? "") ?? .name
        }
        if let raw = defaults.string(forKey: PreferenceKey.sortDirection(for: path)),
           let direction = SortDirection(rawValue: raw) {
            sortFilter.direction = direction
        } else {
            sortFilter.direction = SortDirection(rawValue: defaults.string(forKey: PreferenceKey.defaultSortDirection) ?? "") ?? .ascending
        }
        sortFilter.grouping = GalleryGrouping(rawValue: defaults.string(forKey: PreferenceKey.grouping(for: path)) ?? "") ?? .none
    }

    private func persistDensity() {
        guard !isRestoringPreferences, let url = folderStore.folderURL else { return }
        UserDefaults.standard.set(density, forKey: PreferenceKey.density(for: url.standardizedFileURL.path))
    }

    private func persistSortFilter() {
        guard !isRestoringPreferences, let url = folderStore.folderURL else { return }
        let path = url.standardizedFileURL.path
        let defaults = UserDefaults.standard
        defaults.set(sortFilter.sortKey.rawValue, forKey: PreferenceKey.sortKey(for: path))
        defaults.set(sortFilter.direction.rawValue, forKey: PreferenceKey.sortDirection(for: path))
        defaults.set(sortFilter.grouping.rawValue, forKey: PreferenceKey.grouping(for: path))
    }

    // MARK: Keyboard

    func installKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let window = galleryWindow, NSApp.keyWindow === window else { return false }
        guard !Self.isTextEditing(in: window) else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let character = event.charactersIgnoringModifiers?.lowercased()
        // The standard Edit menu's Select All does not always travel the
        // responder chain through the AppKit-backed grid, so handle it first.
        if flags == .command, character == "a", previewURL == nil, !isComparePresented {
            selectAll()
            return true
        }
        if flags == [.command, .shift], character == "a", previewURL == nil, !isComparePresented {
            clearSelection()
            return true
        }
        return handleGalleryKey(event)
    }

    /// Keyboard navigation and image actions that are not backed by menu key equivalents.
    func handleGalleryKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.intersection([.command, .control, .option]).isEmpty else { return false }
        if isComparePresented {
            if event.keyCode == 53 {
                closeCompare()
                return true
            }
            return false
        }
        if isSlideshowActive {
            return handleSlideshowKey(event)
        }
        if previewURL != nil {
            return handlePreviewKey(event)
        }
        let order = orderedItems.map(\.url)
        let extending = flags.contains(.shift)
        switch event.keyCode {
        case 123: // left
            selection.moveFocus(delta: -1, in: order, extendingSelection: extending)
            return !order.isEmpty
        case 124: // right
            selection.moveFocus(delta: 1, in: order, extendingSelection: extending)
            return !order.isEmpty
        case 125: // down
            selection.moveFocus(delta: density, in: order, extendingSelection: extending)
            return !order.isEmpty
        case 126: // up
            selection.moveFocus(delta: -density, in: order, extendingSelection: extending)
            return !order.isEmpty
        case 36: // return
            if let url = selectedItems.first?.url ?? orderedItems.first?.url {
                openPreview(for: url)
                return true
            }
            return false
        case 49: // space
            if let url = selectedItems.first?.url ?? orderedItems.first?.url {
                openPreview(for: url)
                return true
            }
            return false
        case 51, 117: // delete, forward delete
            if !event.isARepeat {
                Task { await self.trashSelection() }
            }
            return true
        case 53: // escape
            if previewURL != nil {
                closePreview()
            } else if !selection.isEmpty {
                clearSelection()
            }
            return true
        default:
            guard !event.isARepeat, flags.isEmpty,
                  let characters = event.charactersIgnoringModifiers,
                  let character = characters.first
            else { return false }
            if character == "p" || character == "P" {
                Task { await self.setFlag(.pick) }
                return true
            }
            if character == "x" || character == "X" {
                Task { await self.setFlag(.reject) }
                return true
            }
            if let rating = Int(String(character)), (0...5).contains(rating) {
                Task { await self.setRating(rating) }
                return true
            }
            if let number = Int(String(character)), (6...9).contains(number) {
                let labels: [FinderColorLabel] = [.red, .yellow, .green, .blue]
                Task { await self.setLabel(labels[number - 6]) }
                return true
            }
            return false
        }
    }

    static func isTextEditing(in window: NSWindow) -> Bool {
        if let textView = window.firstResponder as? NSTextView, textView.isFieldEditor {
            return true
        }
        if window.firstResponder is NSTextField { return true }
        return false
    }
}

extension Notification.Name {
    static let galeriaFocusSearch = Notification.Name("galeria.focusSearch")
    static let galeriaShowFilters = Notification.Name("galeria.showFilters")
    static let galeriaShowShortcuts = Notification.Name("galeria.showShortcuts")
}
