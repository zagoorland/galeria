import AppKit
import SwiftUI

/// SwiftUI wrapper around an NSCollectionView. AppKit owns scrolling, native
/// Shift/Cmd selection, rectangle selection and multi-file drag-out.
struct GalleryGridView: NSViewRepresentable {
    let model: GalleryModel
    let sections: [GallerySection]
    let selectedIDs: Set<URL>
    let selectMode: Bool
    let columns: Int
    let usesOriginalAspect: Bool
    let showsMetadata: Bool
    let showsSectionHeaders: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let collectionView = GalleryCollectionView()
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.focusRingType = .none
        collectionView.autoresizingMask = [.width]
        collectionView.collectionViewLayout = GalleryGridLayout()
        collectionView.register(GalleryCollectionItem.self,
                                forItemWithIdentifier: GalleryCollectionItem.reuseIdentifier)
        collectionView.register(GallerySectionHeaderView.self,
                                forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: GallerySectionHeaderView.reuseIdentifier)
        // Dragging always copies out of Galeria. This keeps Finder, the
        // desktop, and other apps from moving files out of the library.
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        scrollView.documentView = collectionView

        context.coordinator.attach(collectionView: collectionView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let collectionView = scrollView.documentView as? GalleryCollectionView else { return }
        context.coordinator.update(
            sections: sections,
            selectedIDs: selectedIDs,
            selectMode: selectMode,
            columns: columns,
            usesOriginalAspect: usesOriginalAspect,
            showsMetadata: showsMetadata,
            showsSectionHeaders: showsSectionHeaders
        )
        _ = collectionView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let collectionView = scrollView.documentView as? GalleryCollectionView else { return }
        coordinator.detach(collectionView: collectionView)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDelegate, NSCollectionViewPrefetching {
        private weak var model: GalleryModel?
        private weak var collectionView: GalleryCollectionView?
        private var dataSource: NSCollectionViewDiffableDataSource<String, URL>?
        private var layout: GalleryGridLayout?
        private var currentSections: [GallerySection] = []
        private var itemsByURL: [URL: ImageItem] = [:]
        private var currentSelectedIDs: Set<URL> = []
        private var currentSelectMode = false
        private var currentShowsMetadata = true
        private var currentColumns = 3
        private var currentUsesOriginalAspect = false
        private var currentShowsSectionHeaders = false
        private var isApplyingSelection = false
        private var hasAppliedInitialSnapshot = false
        private var prefetchQueue: [URL] = []
        private var prefetchQueuedURLs: Set<URL> = []
        private var prefetchWorker: Task<Void, Never>?
        private var warmTask: Task<Void, Never>?
        private var warmSignature = ""
        private var lastMaxPixel = 0
        private var magnificationStartDensity = 3
        private var lastMagnification = 0.0
        private var isMagnifying = false

        init(model: GalleryModel) {
            self.model = model
        }

        func attach(collectionView: GalleryCollectionView, scrollView: NSScrollView) {
            self.collectionView = collectionView
            guard let layout = collectionView.collectionViewLayout as? GalleryGridLayout else { return }
            self.layout = layout
            collectionView.delegate = self
            collectionView.prefetchDataSource = self
            collectionView.interactionDelegate = self
            layout.aspectRatioProvider = { [weak self] indexPath in
                self?.item(for: indexPath)?.aspectRatio ?? 1
            }

            let dataSource = NSCollectionViewDiffableDataSource<String, URL>(collectionView: collectionView) { [weak self] collectionView, indexPath, url in
                guard let self, let item = self.itemsByURL[url] else { return nil }
                let cell = collectionView.makeItem(withIdentifier: GalleryCollectionItem.reuseIdentifier, for: indexPath)
                guard let itemCell = cell as? GalleryCollectionItem else { return cell }
                itemCell.configure(
                    item: item,
                    selected: self.currentSelectedIDs.contains(url),
                    selectMode: self.currentSelectMode,
                    showsMetadata: self.currentShowsMetadata,
                    maxPixel: self.thumbnailPixelSize(for: item),
                    thumbnailService: self.model?.thumbnailService ?? ThumbnailService()
                )
                itemCell.tileView.accessibilityPressHandler = { [weak self] in
                    self?.handleAccessibilityPress(url: url)
                }
                itemCell.tileView.accessibilityPreviewHandler = { [weak self] in
                    self?.model?.openPreview(for: url)
                }
                itemCell.tileView.accessibilityTrashHandler = { [weak self] in
                    guard let self, let model = self.model else { return }
                    Task { await model.trashURLs([url]) }
                }
                itemCell.tileView.accessibilityRevealHandler = { [weak self] in
                    self?.model?.revealInFinder(url)
                }
                return itemCell
            }
            dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
                guard kind == NSCollectionView.elementKindSectionHeader else { return nil }
                let view = collectionView.makeSupplementaryView(
                    ofKind: kind,
                    withIdentifier: GallerySectionHeaderView.reuseIdentifier,
                    for: indexPath
                )
                if let header = view as? GallerySectionHeaderView {
                    let title = self?.title(for: indexPath) ?? ""
                    header.configure(title: title)
                    return header
                }
                return nil
            }
            self.dataSource = dataSource

            let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
            collectionView.addGestureRecognizer(magnify)
        }

        func detach(collectionView: GalleryCollectionView) {
            prefetchWorker?.cancel()
            prefetchWorker = nil
            prefetchQueue.removeAll()
            prefetchQueuedURLs.removeAll()
            warmTask?.cancel()
            warmTask = nil
            collectionView.delegate = nil
            collectionView.prefetchDataSource = nil
            collectionView.interactionDelegate = nil
            collectionView.copyHandler = nil
            collectionView.selectAllHandler = nil
            collectionView.trashHandler = nil
            collectionView.escapeHandler = nil
        }

        func update(
            sections: [GallerySection],
            selectedIDs: Set<URL>,
            selectMode: Bool,
            columns: Int,
            usesOriginalAspect: Bool,
            showsMetadata: Bool,
            showsSectionHeaders: Bool
        ) {
            guard let collectionView, let layout else { return }
            let oldSelected = currentSelectedIDs
            let structureChanged = !Self.sameStructure(currentSections, sections)
            let contentChanged = currentSections != sections

            currentSections = sections
            itemsByURL = Dictionary(uniqueKeysWithValues: sections.flatMap(\.items).map { ($0.url, $0) })
            currentSelectedIDs = selectedIDs
            currentSelectMode = selectMode
            currentShowsMetadata = showsMetadata
            collectionView.selectMode = selectMode

            if currentColumns != columns || currentUsesOriginalAspect != usesOriginalAspect || currentShowsSectionHeaders != showsSectionHeaders {
                currentColumns = columns
                currentUsesOriginalAspect = usesOriginalAspect
                currentShowsSectionHeaders = showsSectionHeaders
                layout.columns = columns
                layout.usesOriginalAspect = usesOriginalAspect
                layout.showsSectionHeaders = showsSectionHeaders
                layout.rebuild()
            } else if contentChanged {
                layout.rebuild()
            }

            let pixel = thumbnailPixelSize(for: nil)
            if pixel != lastMaxPixel {
                lastMaxPixel = pixel
                refreshVisibleCells()
            }

            if collectionView.selectionIndexPaths.isEmpty && dataSource?.snapshot().numberOfItems == 0 {
                hasAppliedInitialSnapshot = false
            }

            if structureChanged || !hasAppliedInitialSnapshot {
                applySnapshot(sections: sections, animated: hasAppliedInitialSnapshot)
            } else {
                if contentChanged {
                    refreshVisibleCells()
                }
                syncSelection(selectedIDs, previous: oldSelected)
            }
            collectionView.interactionDelegate = self
            scheduleThumbnailWarmup(sections: sections)
        }

        /// Desktop photo browsers warm a small local thumbnail cache in the
        /// background. This makes a fast scrollbar jump hit disk-cached
        /// thumbnails instead of decoding each original JPEG on demand.
        private func scheduleThumbnailWarmup(sections: [GallerySection]) {
            guard let model else { return }
            let items = sections.flatMap(\.items)
            guard !items.isEmpty else { return }
            let pixel = thumbnailPixelSize(for: nil)
            guard pixel > 0 else { return }
            let signature = "\(model.folderStore.folderURL?.path ?? ""):\(items.count):\(pixel)"
            guard signature != warmSignature else { return }
            warmSignature = signature
            warmTask?.cancel()
            warmTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, let model = self.model else { return }
                await model.thumbnailService.warmCache(for: items, maxPixel: pixel)
            }
        }

        private func applySnapshot(sections: [GallerySection], animated: Bool) {
            guard let dataSource else { return }
            var snapshot = NSDiffableDataSourceSnapshot<String, URL>()
            for section in sections {
                snapshot.appendSections([section.id])
                snapshot.appendItems(section.items.map(\.url), toSection: section.id)
            }
            hasAppliedInitialSnapshot = true
            dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
                guard let self else { return }
                self.syncSelection(self.currentSelectedIDs, previous: [])
                self.refreshVisibleCells()
            }
        }

        private func syncSelection(_ selectedIDs: Set<URL>, previous: Set<URL>) {
            guard let collectionView, let dataSource else { return }
            var indexPaths = Set<IndexPath>()
            for url in selectedIDs {
                if let indexPath = dataSource.indexPath(for: url) {
                    indexPaths.insert(indexPath)
                }
            }
            if collectionView.selectionIndexPaths != indexPaths {
                isApplyingSelection = true
                collectionView.selectionIndexPaths = indexPaths
                isApplyingSelection = false
            }
            if selectedIDs != previous, selectedIDs.count == 1, let indexPath = indexPaths.first {
                if let attrs = collectionView.layoutAttributesForItem(at: indexPath),
                   !collectionView.visibleRect.intersects(attrs.frame) {
                    collectionView.scrollToItems(at: Set([indexPath]), scrollPosition: [.nearestVerticalEdge, .nearestHorizontalEdge])
                }
            }
            refreshSelectionAppearance()
        }

        private func refreshSelectionAppearance() {
            for case let cell as GalleryCollectionItem in collectionView?.visibleItems() ?? [] {
                if let url = cell.currentURL {
                    cell.configure(
                        item: cell.tileView.item ?? itemsByURL[url] ?? ImageItem.placeholder(url: url),
                        selected: currentSelectedIDs.contains(url),
                        selectMode: currentSelectMode,
                        showsMetadata: currentShowsMetadata,
                        maxPixel: thumbnailPixelSize(for: itemsByURL[url]),
                        thumbnailService: model?.thumbnailService ?? ThumbnailService()
                    )
                }
            }
        }

        private func refreshVisibleCells() {
            guard let collectionView, let dataSource else { return }
            for indexPath in collectionView.indexPathsForVisibleItems() {
                guard let url = dataSource.itemIdentifier(for: indexPath),
                      let item = itemsByURL[url],
                      let cell = collectionView.item(at: indexPath) as? GalleryCollectionItem
                else { continue }
                cell.configure(
                    item: item,
                    selected: currentSelectedIDs.contains(url),
                    selectMode: currentSelectMode,
                    showsMetadata: currentShowsMetadata,
                    maxPixel: thumbnailPixelSize(for: item),
                    thumbnailService: model?.thumbnailService ?? ThumbnailService()
                )
            }
        }

        private func thumbnailPixelSize(for item: ImageItem?) -> Int {
            guard let model, let collectionView else { return 512 }
            let width = collectionView.bounds.width
            guard width > 0 else { return 512 }
            let columns = max(1, currentColumns)
            let tile = max(1, (width - CGFloat(columns - 1) * 2) / CGFloat(columns))
            let backingScale = collectionView.window?.backingScaleFactor ?? 2
            let requested = Int(ceil(tile * backingScale))
            let qualityLimit = model.thumbnailQuality.maxPixelSize
            return ThumbnailService.pixelBucket(min(requested, qualityLimit))
        }

        private func item(for indexPath: IndexPath) -> ImageItem? {
            guard indexPath.section >= 0, indexPath.section < currentSections.count else { return nil }
            let items = currentSections[indexPath.section].items
            guard indexPath.item >= 0, indexPath.item < items.count else { return nil }
            return items[indexPath.item]
        }

        private func url(for indexPath: IndexPath) -> URL? {
            item(for: indexPath)?.url
        }

        private func indexPath(for url: URL) -> IndexPath? {
            dataSource?.indexPath(for: url)
        }

        private func title(for indexPath: IndexPath) -> String? {
            guard indexPath.section >= 0, indexPath.section < currentSections.count else { return nil }
            return currentSections[indexPath.section].title
        }

        private func handleAccessibilityPress(url: URL) {
            guard let model else { return }
            if let window = collectionView?.window {
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                if let collectionView {
                    window.makeFirstResponder(collectionView)
                }
            }
            if currentSelectMode {
                var selected = currentSelectedIDs
                if selected.contains(url) {
                    selected.remove(url)
                } else {
                    selected.insert(url)
                }
                model.updateSelectionFromGrid(selected)
                currentSelectedIDs = selected
            } else {
                model.updateSelectionFromGrid([url])
                currentSelectedIDs = [url]
                if let indexPath = indexPath(for: url) {
                    collectionView?.selectionIndexPaths = [indexPath]
                }
            }
            refreshSelectionAppearance()
        }

        private static func sameStructure(_ lhs: [GallerySection], _ rhs: [GallerySection]) -> Bool {
            guard lhs.count == rhs.count else { return false }
            for (left, right) in zip(lhs, rhs) {
                if left.id != right.id || left.title != right.title || left.items.map(\.url) != right.items.map(\.url) {
                    return false
                }
            }
            return true
        }

        // MARK: NSCollectionViewDelegate

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            reportNativeSelection()
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            reportNativeSelection()
        }

        private func reportNativeSelection() {
            guard !isApplyingSelection, !currentSelectMode, let collectionView else { return }
            let urls = Set(collectionView.selectionIndexPaths.compactMap { item(for: $0)?.url })
            guard urls != currentSelectedIDs else { return }
            currentSelectedIDs = urls
            model?.updateSelectionFromGrid(urls)
            refreshSelectionAppearance()
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
            guard let item = item(for: indexPath) else { return nil }
            if !currentSelectedIDs.contains(item.url) {
                model?.selection.selectOnly(item.url)
                currentSelectedIDs = [item.url]
            }
            return item.url as NSURL
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forItemsAt indexPaths: Set<IndexPath>
        ) {
            session.draggingFormation = .stack
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            dragOperation operation: NSDragOperation
        ) {
            model?.refreshAfterDrag(operation: operation)
        }

        // MARK: Prefetching

        func collectionView(_ collectionView: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            guard model != nil else { return }
            for indexPath in indexPaths {
                guard let item = item(for: indexPath), prefetchQueuedURLs.insert(item.url).inserted else { continue }
                prefetchQueue.append(item.url)
            }
            startPrefetchWorkerIfNeeded()
        }

        func collectionView(_ collectionView: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            let canceled = Set(indexPaths.compactMap { url(for: $0) })
            guard !canceled.isEmpty else { return }
            prefetchQueuedURLs.subtract(canceled)
            prefetchQueue.removeAll { canceled.contains($0) }
            if prefetchQueue.isEmpty {
                prefetchWorker?.cancel()
                prefetchWorker = nil
            }
        }

        /// A single, cancellable preheat worker. Spawning one detached load
        /// per prefetched index path during fast scrolling made the visible
        /// cells compete with dozens of invisible decodes.
        private func startPrefetchWorkerIfNeeded() {
            guard prefetchWorker == nil, !prefetchQueue.isEmpty, let model else { return }
            prefetchWorker = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled, !self.prefetchQueue.isEmpty {
                    let url = self.prefetchQueue.removeFirst()
                    self.prefetchQueuedURLs.remove(url)
                    guard let item = self.itemsByURL[url] else { continue }
                    _ = await model.thumbnailService.thumbnail(
                        for: item,
                        maxPixel: self.thumbnailPixelSize(for: item)
                    )
                }
                self.prefetchWorker = nil
                if !Task.isCancelled {
                    self.startPrefetchWorkerIfNeeded()
                }
            }
        }

        // MARK: Magnification

        @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
            guard let model else { return }
            switch gesture.state {
            case .began:
                magnificationStartDensity = model.density
                lastMagnification = 0
                isMagnifying = true
            case .changed:
                let delta = gesture.magnification - lastMagnification
                lastMagnification = gesture.magnification
                let step = Int((gesture.magnification * 6).rounded())
                let newDensity = min(max(magnificationStartDensity - step, 1), 10)
                if newDensity != model.density {
                    model.setDensity(newDensity)
                }
                _ = delta
            case .ended, .cancelled:
                isMagnifying = false
            default:
                break
            }
        }
    }
}

extension GalleryGridView.Coordinator: GalleryCollectionViewInteractionDelegate {
    func collectionView(_ collectionView: GalleryCollectionView, itemDoubleClickedAt indexPath: IndexPath) {
        guard let item = item(for: indexPath) else { return }
        model?.openPreview(for: item.url)
    }

    func collectionView(_ collectionView: GalleryCollectionView, selectionChangedTo urls: Set<URL>) {
        currentSelectedIDs = urls
        model?.updateSelectionFromGrid(urls)
        refreshSelectionAppearance()
    }

    func collectionView(_ collectionView: GalleryCollectionView, contextMenuFor indexPath: IndexPath) -> NSMenu? {
        guard let item = item(for: indexPath) else { return nil }
        if !collectionView.selectionIndexPaths.contains(indexPath) {
            isApplyingSelection = true
            collectionView.selectionIndexPaths = [indexPath]
            isApplyingSelection = false
            currentSelectedIDs = [item.url]
            model?.updateSelectionFromGrid([item.url])
            refreshSelectionAppearance()
        }
        return model?.contextMenu(for: item.url, in: collectionView)
    }
}

// MARK: - Custom collection view

@MainActor
protocol GalleryCollectionViewInteractionDelegate: AnyObject {
    func collectionView(_ collectionView: GalleryCollectionView, itemDoubleClickedAt indexPath: IndexPath)
    func collectionView(_ collectionView: GalleryCollectionView, selectionChangedTo urls: Set<URL>)
    func collectionView(_ collectionView: GalleryCollectionView, contextMenuFor indexPath: IndexPath) -> NSMenu?
}

/// Adds Select-mode toggling and a native-feeling drag marquee on top of
/// NSCollectionView's standard selection and drag machinery.
final class GalleryCollectionView: NSCollectionView {
    weak var interactionDelegate: GalleryCollectionViewInteractionDelegate?
    var selectMode = false
    var copyHandler: (() -> Void)?
    var selectAllHandler: (() -> Void)?
    var trashHandler: (() -> Void)?
    var escapeHandler: (() -> Void)?

    private var marqueeView: MarqueeSelectionView?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    @objc func copy(_ sender: Any?) {
        copyHandler?()
    }

    override func selectAll(_ sender: Any?) {
        selectAllHandler?()
    }

    override func deleteBackward(_ sender: Any?) {
        trashHandler?()
    }

    override func cancelOperation(_ sender: Any?) {
        escapeHandler?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)

        if let indexPath {
            if selectMode {
                if event.clickCount >= 2 {
                    interactionDelegate?.collectionView(self, itemDoubleClickedAt: indexPath)
                    return
                }
                toggleSelection(at: indexPath)
                return
            }
            super.mouseDown(with: event)
            if event.clickCount == 2, let current = self.indexPathForItem(at: point) {
                interactionDelegate?.collectionView(self, itemDoubleClickedAt: current)
            }
            return
        }

        beginMarquee(event: event, startPoint: point)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: point) else { return nil }
        return interactionDelegate?.collectionView(self, contextMenuFor: indexPath)
    }

    private func toggleSelection(at indexPath: IndexPath) {
        var selected = selectionIndexPaths
        if selected.contains(indexPath) {
            selected.remove(indexPath)
        } else {
            selected.insert(indexPath)
        }
        selectionIndexPaths = selected
        let urls = Set(selected.compactMap { itemURL(at: $0) })
        interactionDelegate?.collectionView(self, selectionChangedTo: urls)
    }

    private func beginMarquee(event: NSEvent, startPoint: NSPoint) {
        guard let window else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let additive = flags.contains(.shift) || flags.contains(.command)
        let baseSelection = additive ? selectionIndexPaths : []
        if !additive {
            selectionIndexPaths = []
            interactionDelegate?.collectionView(self, selectionChangedTo: [])
        }

        if marqueeView == nil {
            let view = MarqueeSelectionView(frame: bounds)
            view.autoresizingMask = [.width, .height]
            addSubview(view)
            marqueeView = view
        }
        marqueeView?.selectionRect = .zero
        marqueeView?.isHidden = false

        var didDrag = false
        let threshold: CGFloat = 3
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp],
                           timeout: NSEvent.foreverDuration,
                           mode: .eventTracking) { [weak self] trackedEvent, stop in
            guard let self else {
                stop.pointee = true
                return
            }
            guard let trackedEvent else {
                stop.pointee = true
                return
            }
            let point = self.convert(trackedEvent.locationInWindow, from: nil)
            if trackedEvent.type == .leftMouseDragged {
                if !didDrag && hypot(point.x - startPoint.x, point.y - startPoint.y) < threshold {
                    return
                }
                didDrag = true
                let rect = NSRect(x: min(startPoint.x, point.x),
                                  y: min(startPoint.y, point.y),
                                  width: abs(point.x - startPoint.x),
                                  height: abs(point.y - startPoint.y))
                self.marqueeView?.selectionRect = rect
                self.updateMarqueeSelection(rect: rect, baseSelection: baseSelection)
            } else if trackedEvent.type == .leftMouseUp {
                if didDrag {
                    let rect = NSRect(x: min(startPoint.x, point.x),
                                      y: min(startPoint.y, point.y),
                                      width: abs(point.x - startPoint.x),
                                      height: abs(point.y - startPoint.y))
                    self.updateMarqueeSelection(rect: rect, baseSelection: baseSelection)
                }
                self.marqueeView?.isHidden = true
                stop.pointee = true
            }
        }
        marqueeView?.isHidden = true
    }

    private func updateMarqueeSelection(rect: NSRect, baseSelection: Set<IndexPath>) {
        let attributes = collectionViewLayout?.layoutAttributesForElements(in: rect) ?? []
        let hit = attributes.filter { $0.representedElementCategory == .item }.compactMap(\.indexPath)
        let selection = baseSelection.union(hit)
        guard selection != selectionIndexPaths else { return }
        selectionIndexPaths = selection
        let urls = Set(selection.compactMap { itemURL(at: $0) })
        interactionDelegate?.collectionView(self, selectionChangedTo: urls)
    }

    private func itemURL(at indexPath: IndexPath) -> URL? {
        if let item = item(at: indexPath) as? GalleryCollectionItem {
            return item.currentURL
        }
        guard let dataSource = dataSource as? NSCollectionViewDiffableDataSource<String, URL> else {
            return nil
        }
        return dataSource.itemIdentifier(for: indexPath)
    }
}

private final class MarqueeSelectionView: NSView {
    var selectionRect: NSRect = .zero {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !selectionRect.isEmpty else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        selectionRect.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: selectionRect.integral.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }
}

private extension ImageItem {
    static func placeholder(url: URL) -> ImageItem {
        ImageItem(url: url, name: url.lastPathComponent, fileSize: 0,
                  createdAt: .distantPast, modifiedAt: .distantPast, addedAt: .distantPast,
                  pixelWidth: 0, pixelHeight: 0, format: .other, tags: [],
                  exifCaptureDate: nil, cameraMake: nil, cameraModel: nil, lens: nil,
                  iso: nil, aperture: nil, exposureTime: nil, focalLength: nil,
                  latitude: nil, longitude: nil, orientation: 1)
    }
}
