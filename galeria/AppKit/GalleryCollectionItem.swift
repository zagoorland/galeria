import AppKit
import QuartzCore

/// A reusable square image tile.
final class GalleryCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("GalleryCollectionItem")
    let tileView = GalleryTileView(frame: .zero)
    private(set) var currentURL: URL?
    private var currentModifiedAt: Date?
    private var loadedPixelSize = 0
    private var loadTask: Task<Void, Never>?

    override func loadView() {
        view = tileView
    }

    deinit {
        loadTask?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentURL = nil
        currentModifiedAt = nil
        loadedPixelSize = 0
        tileView.item = nil
        tileView.clearThumbnail()
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    func configure(
        item: ImageItem,
        selected: Bool,
        selectMode: Bool,
        showsMetadata: Bool,
        maxPixel: Int,
        thumbnailService: ThumbnailService
    ) {
        let itemChanged = currentURL != item.url || currentModifiedAt != item.modifiedAt
        if itemChanged || loadedPixelSize != maxPixel {
            currentURL = item.url
            currentModifiedAt = item.modifiedAt
            // Keep the previous image onscreen while a differently sized
            // variant loads. Only a new item clears the tile immediately.
            if itemChanged {
                tileView.clearThumbnail()
            }
            loadTask?.cancel()
            loadedPixelSize = maxPixel
            if let cached = thumbnailService.cachedImage(for: item, maxPixel: maxPixel) {
                tileView.setThumbnail(cached)
                loadTask = nil
            } else {
                let requestedURL = item.url
                let requestedModifiedAt = item.modifiedAt
                loadTask = Task { [weak self] in
                    let image = await thumbnailService.thumbnail(for: item, maxPixel: maxPixel)
                    guard !Task.isCancelled,
                          let self,
                          self.currentURL == requestedURL,
                          self.currentModifiedAt == requestedModifiedAt
                    else { return }
                    if let image {
                        self.tileView.setThumbnail(image)
                    } else if self.tileView.displayedImage == nil {
                        self.tileView.thumbnailMissing = true
                        self.tileView.needsDisplay = true
                    }
                }
            }
        }

        tileView.item = item
        tileView.selectMode = selectMode
        tileView.showsMetadata = showsMetadata
        tileView.selectionState = selected
        if isSelected != selected {
            isSelected = selected
        }
        tileView.updateAccessibility(selected: selected)
    }

    private func updateSelectionAppearance() {
        tileView.selectionState = isSelected
        tileView.updateAccessibility(selected: isSelected)
    }

    override var draggingImageComponents: [NSDraggingImageComponent] {
        guard let thumbnail = tileView.displayedImage else {
            return super.draggingImageComponents
        }
        let dragImage = DragImageRenderer.makeImage(thumbnail: thumbnail,
                                                    selectionCount: collectionView?.selectionIndexPaths.count ?? 1)
        let component = NSDraggingImageComponent(key: NSDraggingItem.ImageComponentKey.icon)
        component.contents = dragImage
        component.frame = NSRect(x: 0, y: 0, width: 104, height: 104)
        return [component]
    }
}

private enum DragImageRenderer {
    static func makeImage(thumbnail: NSImage, selectionCount: Int) -> NSImage {
        let side: CGFloat = 104
        let image = NSImage(size: NSSize(width: side + 12, height: side + 12), flipped: false) { rect in
            let stackOffset: CGFloat = selectionCount > 1 ? 6 : 0
            if stackOffset > 0 {
                NSColor.black.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: NSRect(x: 10, y: 4, width: side - 2, height: side - 2),
                             xRadius: 7, yRadius: 7).fill()
                NSColor.white.withAlphaComponent(0.35).setFill()
                NSBezierPath(roundedRect: NSRect(x: 5, y: 8, width: side - 2, height: side - 2),
                             xRadius: 7, yRadius: 7).fill()
            }
            let tileRect = NSRect(x: 0, y: 12, width: side, height: side)
            NSColor.black.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: tileRect.insetBy(dx: -1, dy: -1), xRadius: 8, yRadius: 8).fill()
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: tileRect, xRadius: 7, yRadius: 7).fill()

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: tileRect, xRadius: 7, yRadius: 7).addClip()
            thumbnail.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()

            if selectionCount > 1 {
                let badgeRect = NSRect(x: side - 24, y: 6, width: 28, height: 28)
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: badgeRect).fill()
                let text = "\(selectionCount)" as NSString
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: NSColor.alternateSelectedControlTextColor,
                    .paragraphStyle: paragraph
                ]
                let textSize = text.size(withAttributes: attributes)
                text.draw(in: NSRect(x: badgeRect.minX,
                                     y: badgeRect.midY - textSize.height / 2,
                                     width: badgeRect.width,
                                     height: textSize.height),
                          withAttributes: attributes)
            }
            return true
        }
        return image
    }
}
