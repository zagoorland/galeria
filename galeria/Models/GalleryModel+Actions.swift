import AppKit
import Foundation
import ImageIO

// MARK: - Trash and undo

extension GalleryModel {
    /// Items the current command should act on: selection first, then the preview image.
    var actionItems: [ImageItem] {
        if !selectedItems.isEmpty { return selectedItems }
        if let previewURL, let item = folderStore.item(for: previewURL) { return [item] }
        return []
    }

    func confirmTrash(count: Int) -> Bool {
        let threshold = max(1, UserDefaults.standard.integer(forKey: PreferenceKey.confirmationThreshold))
        guard count > threshold else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = count == 1 ? "Move This Image to the Trash?" : "Move \(count) Images to the Trash?"
        alert.informativeText = "You can restore them with Undo. Confirmation appears above \(threshold) items and can be changed in Settings."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        if let button = alert.buttons.first {
            button.hasDestructiveAction = true
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    func trashSelection() async {
        let items = actionItems
        let urls = items.map(\.url)
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        guard confirmTrash(count: urls.count) else { return }
        do {
            let mappings = try await trashService.trash(urls)
            guard !mappings.isEmpty else {
                presentedError = GalleryError(title: "Nothing to Trash",
                                              message: "The selected files were no longer available.")
                return
            }
            applyTrashResult(mappings)
            undoJournal.record(makeTrashRestoreEntry(mappings))
        } catch {
            presentedError = GalleryError(title: "Could Not Move to Trash", message: error.localizedDescription)
        }
    }

    private func applyTrashResult(_ mappings: [TrashMapping]) {
        let deleted = Set(mappings.map(\.originalURL))
        let orderBefore = orderedItems.map(\.url)
        let candidate = selection.selectionAfterRemoving(deleted, in: orderBefore)
        let wasPreviewing = previewURL != nil
        let oldPreviewURL = previewURL
        folderStore.removeItems(with: deleted)
        let remaining = orderedItems
        let available = remaining.map(\.url)
        let nextURL: URL?
        if let candidate, available.contains(candidate) {
            nextURL = candidate
        } else {
            nextURL = available.first
        }
        if let nextURL {
            selection.selectOnly(nextURL)
        } else {
            selection.clear()
        }
        if wasPreviewing {
            if let nextURL, let index = remaining.firstIndex(where: { $0.url == nextURL }) {
                previewItems = remaining
                previewIndex = index
                previewURL = nextURL
                resetPreviewZoom()
                preloadPreviewNeighbors()
            } else {
                closePreview()
            }
        } else if let oldPreviewURL, deleted.contains(oldPreviewURL) {
            closePreview()
        }
    }

    private func makeTrashRestoreEntry(_ mappings: [TrashMapping]) -> UndoJournal.Entry {
        let urls = mappings.map(\.originalURL)
        let name = "Trash \(urls.count) \(urls.count == 1 ? "Image" : "Images")"
        return UndoJournal.Entry(name: name) { [weak self] in
            guard let self else { return nil }
            try await self.trashService.restore(mappings)
            await self.folderStore.refresh()
            let restored = Set(urls).intersection(self.folderStore.availableURLs)
            if !restored.isEmpty {
                self.selection.setSelection(restored, anchor: urls.first)
            }
            return self.makeTrashAgainEntry(urls: urls, name: name)
        }
    }

    private func makeTrashAgainEntry(urls: [URL], name: String) -> UndoJournal.Entry {
        UndoJournal.Entry(name: name) { [weak self] in
            guard let self else { return nil }
            let mappings = try await self.trashService.trash(urls)
            guard !mappings.isEmpty else { return nil }
            self.applyTrashResult(mappings)
            return self.makeTrashRestoreEntry(mappings)
        }
    }

    func performUndo() async {
        do {
            if try await undoJournal.undo() == false {
                NSSound.beep()
            }
        } catch {
            presentedError = GalleryError(title: "Could Not Undo", message: error.localizedDescription)
        }
    }

    func performRedo() async {
        do {
            if try await undoJournal.redo() == false {
                NSSound.beep()
            }
        } catch {
            presentedError = GalleryError(title: "Could Not Redo", message: error.localizedDescription)
        }
    }
}

// MARK: - Ratings, flags, labels

extension GalleryModel {
    func setRating(_ rating: Int) async {
        let items = actionItems
        guard !items.isEmpty else { return }
        let clamped = min(max(rating, 0), 5)
        let changes = items.map { item in
            TagChange(url: item.url, oldTags: item.tags,
                      newTags: FinderTagCodec.applyingRating(clamped, to: item.tags))
        }
        let name = clamped == 0 ? "Clear Rating" : "Rate \(clamped) \(clamped == 1 ? "Star" : "Stars")"
        await applyTagBatch(TagChangeBatch(name: name, changes: changes))
    }

    func setFlag(_ flag: ImageFlag) async {
        let items = actionItems
        guard !items.isEmpty else { return }
        let changes = items.map { item in
            TagChange(url: item.url, oldTags: item.tags,
                      newTags: FinderTagCodec.applyingFlag(flag, to: item.tags))
        }
        let name: String
        switch flag {
        case .pick: name = "Flag as Pick"
        case .reject: name = "Flag as Reject"
        case .none: name = "Clear Flag"
        }
        await applyTagBatch(TagChangeBatch(name: name, changes: changes))
    }

    func setLabel(_ label: FinderColorLabel?) async {
        let items = actionItems
        guard !items.isEmpty else { return }
        let changes = items.map { item in
            TagChange(url: item.url, oldTags: item.tags,
                      newTags: FinderTagCodec.applyingLabel(label, to: item.tags))
        }
        await applyTagBatch(TagChangeBatch(name: "Set Color Label", changes: changes))
    }

    private func applyTagBatch(_ batch: TagChangeBatch) async {
        var successful: [TagChange] = []
        var failures: [String] = []
        for change in batch.changes where change.oldTags != change.newTags {
            do {
                let written = try await tagService.apply(tags: change.newTags, to: change.url)
                folderStore.updateTags(for: change.url, tags: written)
                successful.append(TagChange(url: change.url, oldTags: change.oldTags, newTags: written))
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        if !successful.isEmpty {
            let old = Dictionary(uniqueKeysWithValues: successful.map { ($0.url, $0.oldTags) })
            let new = Dictionary(uniqueKeysWithValues: successful.map { ($0.url, $0.newTags) })
            undoJournal.record(makeTagEntry(name: batch.name, target: old, inverse: new))
        }
        if !failures.isEmpty {
            presentedError = GalleryError(title: "Some Tags Could Not Be Saved",
                                          message: failures.first ?? "The file is not writable.")
        }
    }

    private func makeTagEntry(name: String, target: [URL: [String]], inverse: [URL: [String]]) -> UndoJournal.Entry {
        UndoJournal.Entry(name: name) { [weak self] in
            guard let self else { return nil }
            try await self.applyTagsForUndo(target)
            return self.makeTagEntry(name: name, target: inverse, inverse: target)
        }
    }

    private func applyTagsForUndo(_ tagsByURL: [URL: [String]]) async throws {
        for (url, tags) in tagsByURL {
            let written = try await tagService.apply(tags: tags, to: url)
            folderStore.updateTags(for: url, tags: written)
        }
    }
}

// MARK: - Move and copy

extension GalleryModel {
    var quickMoveDestinations: [BookmarkRecord] {
        _ = sidebarRevision
        var seen = Set<String>()
        return (bookmarkService.favoriteFolders() + bookmarkService.moveDestinations()).filter {
            seen.insert($0.path).inserted
        }
        .prefix(9)
        .map { $0 }
    }

    func chooseMoveDestination() {
        chooseDestination(for: .move, remember: true)
    }

    func chooseCopyDestination() {
        chooseDestination(for: .copy, remember: false)
    }

    private func chooseDestination(for mode: TransferMode, remember: Bool) {
        let panel = NSOpenPanel()
        panel.title = mode == .move ? "Move Images To" : "Copy Images To"
        panel.prompt = mode == .move ? "Move Here" : "Copy Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        if remember {
            try? bookmarkService.addMoveDestination(url: destination)
            sidebarRevision += 1
        }
        Task { await transferSelection(to: destination, mode: mode) }
    }

    func transferSelection(to record: BookmarkRecord, mode: TransferMode) async {
        guard let resolved = bookmarkService.resolvedURL(for: record) else {
            presentedError = GalleryError(title: "Destination Unavailable",
                                          message: "Choose this destination again to restore access.")
            return
        }
        await transferSelection(to: resolved.0, mode: mode)
    }

    func transferSelection(to destination: URL, mode: TransferMode) async {
        let items = selectedItems
        let urls = items.map(\.url)
        guard !urls.isEmpty else { return }
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        do {
            let mappings = try await fileTransferService.transfer(urls, to: destination, mode: mode)
            if mode == .move {
                applyMoveResult(mappings)
                undoJournal.record(makeMoveBackEntry(mappings, destination: destination))
            }
            if let error = folderStore.error {
                presentedError = error
            }
        } catch {
            presentedError = GalleryError(title: "Could Not \(mode.displayName) Images",
                                          message: error.localizedDescription)
        }
    }

    private func applyMoveResult(_ mappings: [TransferMapping]) {
        let moved = Set(mappings.map(\.originalURL))
        let orderBefore = orderedItems.map(\.url)
        let candidate = selection.selectionAfterRemoving(moved, in: orderBefore)
        folderStore.removeItems(with: moved)
        let available = folderStore.items.map(\.url)
        if let candidate, available.contains(candidate) {
            selection.selectOnly(candidate)
        } else if let next = available.first {
            selection.selectOnly(next)
        } else {
            selection.clear()
        }
        if let previewURL, moved.contains(previewURL) { closePreview() }
    }

    private func makeMoveBackEntry(_ mappings: [TransferMapping], destination: URL) -> UndoJournal.Entry {
        let originalURLs = mappings.map(\.originalURL)
        let name = "Move \(mappings.count) \(mappings.count == 1 ? "Image" : "Images")"
        return UndoJournal.Entry(name: name) { [weak self] in
            guard let self else { return nil }
            let access = destination.startAccessingSecurityScopedResource()
            defer { if access { destination.stopAccessingSecurityScopedResource() } }
            try await self.fileTransferService.moveBack(mappings)
            await self.folderStore.refresh()
            let restored = Set(originalURLs).intersection(self.folderStore.availableURLs)
            if !restored.isEmpty {
                self.selection.setSelection(restored, anchor: originalURLs.first)
            }
            return self.makeMoveForwardEntry(urls: originalURLs, destination: destination, name: name)
        }
    }

    private func makeMoveForwardEntry(urls: [URL], destination: URL, name: String) -> UndoJournal.Entry {
        UndoJournal.Entry(name: name) { [weak self] in
            guard let self else { return nil }
            let access = destination.startAccessingSecurityScopedResource()
            defer { if access { destination.stopAccessingSecurityScopedResource() } }
            let mappings = try await self.fileTransferService.transfer(urls, to: destination, mode: .move)
            self.applyMoveResult(mappings)
            return self.makeMoveBackEntry(mappings, destination: destination)
        }
    }
}

// MARK: - Share, copy, reveal, menu

extension GalleryModel {
    func revealSelection() {
        let urls = actionItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copySelectionFiles() {
        let urls = Set(actionItems.map(\.url))
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
    }

    func copySelectionAsImage() {
        guard let item = actionItems.first else { return }
        Task {
            do {
                try await ClipboardImageWriter.copyImage(at: item.url)
            } catch {
                presentedError = GalleryError(title: "Could Not Copy Image", message: error.localizedDescription)
            }
        }
    }

    func shareSelection(from view: NSView? = nil) {
        let urls = actionItems.map { $0.url as NSURL }
        guard !urls.isEmpty else { return }
        let anchor = view ?? galleryWindow?.contentView
        guard let anchor else { return }
        let picker = NSSharingServicePicker(items: urls)
        sharingPicker = picker
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    func showInfo(for url: URL) {
        infoItem = folderStore.item(for: url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openExternally(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func copyFileURLs(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
    }

    func refreshAfterDrag(operation: NSDragOperation) {
        guard operation.contains(.move) || operation.contains(.delete) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            await folderStore.refresh()
        }
    }

    func contextMenu(for url: URL, in view: NSView) -> NSMenu {
        guard let modelItem = folderStore.item(for: url) else { return NSMenu() }
        let selected = selectedItems
        let targets = selected.isEmpty ? [modelItem] : selected
        let menu = NSMenu(title: modelItem.name)
        menu.addItem(ClosureMenuItem(title: "Quick Look") { [weak self] in self?.openPreview(for: url) })
        menu.addItem(ClosureMenuItem(title: "Open in Default App") { [weak self] in self?.openExternally(url) })
        menu.addItem(ClosureMenuItem(title: "Reveal in Finder") { [weak self] in self?.revealInFinder(url) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: targets.count > 1 ? "Copy \(targets.count) Files" : "Copy File") { [weak self] in
            self?.copyFileURLs(Set(targets.map(\.url)))
        })
        menu.addItem(ClosureMenuItem(title: "Copy as Image") { [weak self] in self?.copySelectionAsImage() })
        menu.addItem(ClosureMenuItem(title: "Share…") { [weak self] in
            self?.shareSelection(from: view)
        })

        let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        openWithItem.submenu = makeOpenWithMenu(for: url)
        menu.addItem(openWithItem)
        menu.addItem(ClosureMenuItem(title: "Show Info") { [weak self] in self?.showInfo(for: url) })
        menu.addItem(.separator())

        let moveItem = NSMenuItem(title: "Move to…", action: nil, keyEquivalent: "")
        moveItem.submenu = makeDestinationMenu(mode: .move)
        menu.addItem(moveItem)
        let copyItem = NSMenuItem(title: "Copy to…", action: nil, keyEquivalent: "")
        copyItem.submenu = makeDestinationMenu(mode: .copy)
        menu.addItem(copyItem)

        let rotateItem = NSMenuItem(title: "Rotate", action: nil, keyEquivalent: "")
        let rotateMenu = NSMenu()
        rotateMenu.addItem(ClosureMenuItem(title: "Rotate Left") { [weak self] in
            Task { await self?.rotateSelection(.left) }
        })
        rotateMenu.addItem(ClosureMenuItem(title: "Rotate Right") { [weak self] in
            Task { await self?.rotateSelection(.right) }
        })
        rotateItem.submenu = rotateMenu
        menu.addItem(rotateItem)

        let pick = ClosureMenuItem(title: "Pick") { [weak self] in Task { await self?.setFlag(.pick) } }
        pick.state = modelItem.isPick ? .on : .off
        menu.addItem(pick)
        let reject = ClosureMenuItem(title: "Reject") { [weak self] in Task { await self?.setFlag(.reject) } }
        reject.state = modelItem.isReject ? .on : .off
        menu.addItem(reject)

        let ratingItem = NSMenuItem(title: "Rating", action: nil, keyEquivalent: "")
        let ratingMenu = NSMenu()
        for value in 0...5 {
            let title = value == 0 ? "No Rating" : "\(value) \(value == 1 ? "Star" : "Stars")"
            let rateItem = ClosureMenuItem(title: title) { [weak self] in
                Task { await self?.setRating(value) }
            }
            rateItem.state = modelItem.rating == value ? .on : .off
            ratingMenu.addItem(rateItem)
        }
        ratingItem.submenu = ratingMenu
        menu.addItem(ratingItem)

        let labelItem = NSMenuItem(title: "Label", action: nil, keyEquivalent: "")
        let labelMenu = NSMenu()
        let none = ClosureMenuItem(title: "None") { [weak self] in Task { await self?.setLabel(nil) } }
        none.state = modelItem.label == nil ? .on : .off
        labelMenu.addItem(none)
        for label in FinderColorLabel.allCases {
            let result = ClosureMenuItem(title: label.displayName) { [weak self] in
                Task { await self?.setLabel(label) }
            }
            result.state = modelItem.label == label ? .on : .off
            labelMenu.addItem(result)
        }
        labelItem.submenu = labelMenu
        menu.addItem(labelItem)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Move to Trash") { [weak self] in
            Task { await self?.trashSelection() }
        })
        return menu
    }

    private func makeDestinationMenu(mode: TransferMode) -> NSMenu {
        let menu = NSMenu()
        let chooseItem = ClosureMenuItem(title: "Choose Folder…") { [weak self] in
            if mode == .move { self?.chooseMoveDestination() } else { self?.chooseCopyDestination() }
        }
        menu.addItem(chooseItem)
        let destinations = quickMoveDestinations
        if !destinations.isEmpty {
            menu.addItem(.separator())
            for record in destinations {
                menu.addItem(ClosureMenuItem(title: record.name) { [weak self] in
                    Task { await self?.transferSelection(to: record, mode: mode) }
                })
            }
        }
        return menu
    }

    private func makeOpenWithMenu(for url: URL) -> NSMenu {
        let menu = NSMenu()
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        for app in apps.prefix(10) {
            let name = FileManager.default.displayName(atPath: app.path)
            menu.addItem(ClosureMenuItem(title: name) { [weak self] in
                NSWorkspace.shared.open([url], withApplicationAt: app,
                                        configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error {
                        Task { @MainActor in
                            self?.presentedError = GalleryError(title: "Could Not Open Image",
                                                               message: error.localizedDescription)
                        }
                    }
                }
            })
        }
        if apps.isEmpty {
            let item = NSMenuItem(title: "No Applications", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }
}

// MARK: - Helpers

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}

enum ClipboardImageWriter {
    enum CopyError: LocalizedError {
        case unreadable
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: "The image could not be read."
            case .encodingFailed: "The image could not be encoded for the clipboard."
            }
        }
    }

    static func copyImage(at url: URL) async throws {
        let payload = try await Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 12000
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { throw CopyError.unreadable }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let tiff = rep.tiffRepresentation,
                  let png = rep.representation(using: .png, properties: [:])
            else { throw CopyError.encodingFailed }
            return (tiff, png)
        }.value
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(payload.0, forType: .tiff)
        NSPasteboard.general.setData(payload.1, forType: .png)
    }
}

// MARK: - Rotation

extension GalleryModel {
    func rotateSelection(_ direction: RotationDirection) async {
        let items = actionItems
        guard !items.isEmpty else { return }
        let unsupported = items.filter { $0.format.isRaw || $0.format == .gif }
        if !unsupported.isEmpty {
            presentedError = GalleryError(
                title: "Rotation Not Available",
                message: "RAW files and animated GIFs cannot be rotated without losing data. Rotate JPEG, HEIC, PNG, TIFF, WebP, or BMP images instead."
            )
            return
        }
        let requiresReencode = await rotationService.requiresReencode(items: items, direction: direction)
        if requiresReencode {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Re-encode \(items.count == 1 ? "This Image" : "These Images") to Rotate?"
            alert.informativeText = "JPEGs with a usable EXIF orientation rotate losslessly. The others are re-encoded at the highest quality; metadata and Finder tags are preserved."
            alert.addButton(withTitle: "Rotate")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        var failures: [String] = []
        for item in items {
            do {
                try await rotationService.rotate(item.url, format: item.format, direction: direction)
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
            }
        }
        await folderStore.refresh()
        if let first = items.first, let refreshed = folderStore.item(for: first.url) {
            if infoItem?.url == first.url { infoItem = refreshed }
        }
        if !failures.isEmpty {
            presentedError = GalleryError(title: "Some Images Could Not Be Rotated",
                                          message: failures.prefix(3).joined(separator: "\n"))
        }
    }
}

// MARK: - Sidebar drops

extension GalleryModel {
    /// A sidebar drop receives image URLs from the grid and moves them to that folder.
    func moveDroppedURLs(_ urls: [URL], to destination: URL) async {
        let available = Set(urls.filter { folderStore.availableURLs.contains($0) })
        guard !available.isEmpty else { return }
        selection.setSelection(available, anchor: urls.first)
        await transferSelection(to: destination, mode: .move)
    }

    func moveDroppedURLs(_ urls: [URL], to record: BookmarkRecord) async {
        let available = Set(urls.filter { folderStore.availableURLs.contains($0) })
        guard !available.isEmpty else { return }
        selection.setSelection(available, anchor: urls.first)
        await transferSelection(to: record, mode: .move)
    }
}

extension GalleryModel {
    func presentDuplicateFinder() {
        guard folderStore.folderURL != nil else { return }
        showDuplicateFinder = true
    }

    /// Selects and trashes arbitrary URLs, using the normal confirmation and undo path.
    func trashURLs(_ urls: [URL]) async {
        let valid = Set(urls.filter { folderStore.availableURLs.contains($0) })
        guard !valid.isEmpty else {
            NSSound.beep()
            return
        }
        selection.setSelection(valid, anchor: urls.first)
        await trashSelection()
    }
}
