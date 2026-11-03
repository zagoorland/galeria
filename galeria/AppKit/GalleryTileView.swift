import AppKit

/// Draws the tile's selection and metadata overlay above the thumbnail layer.
/// All chrome is drawn in one view, keeping scrolling light for large folders.
final class GalleryTileView: NSView {
    let imageView = NSView()
    private let overlayView = TileOverlayView()
    private var trackingArea: NSTrackingArea?

    var item: ImageItem?
    var showsMetadata = true
    var selectMode = false
    var selectionState = false
    var thumbnailMissing = false
    var accessibilityPressHandler: (() -> Void)?
    var accessibilityPreviewHandler: (() -> Void)?
    var accessibilityTrashHandler: (() -> Void)?
    var accessibilityRevealHandler: (() -> Void)?
    private(set) var displayedImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspectFill
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(imageView)

        overlayView.tile = self
        addSubview(overlayView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Quick Look") { [weak self] in
                guard let handler = self?.accessibilityPreviewHandler else { return false }
                handler()
                return true
            },
            NSAccessibilityCustomAction(name: "Move to Trash") { [weak self] in
                guard let handler = self?.accessibilityTrashHandler else { return false }
                handler()
                return true
            },
            NSAccessibilityCustomAction(name: "Reveal in Finder") { [weak self] in
                guard let handler = self?.accessibilityRevealHandler else { return false }
                handler()
                return true
            }
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        overlayView.frame = bounds
        imageView.layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        overlayView.isHovering = true
        overlayView.needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        overlayView.isHovering = false
        overlayView.needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        overlayView.needsDisplay = true
    }

    func setThumbnail(_ image: NSImage?) {
        thumbnailMissing = image == nil
        displayedImage = image
        if let image {
            var proposedRect = NSRect(origin: .zero, size: image.size)
            if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
                imageView.layer?.contents = cgImage
            } else {
                imageView.layer?.contents = image
            }
        } else {
            imageView.layer?.contents = nil
        }
        overlayView.needsDisplay = true
    }

    func clearThumbnail() {
        imageView.layer?.contents = nil
        displayedImage = nil
        thumbnailMissing = false
        overlayView.needsDisplay = true
    }

    override func accessibilityPerformPress() -> Bool {
        guard let accessibilityPressHandler else { return false }
        accessibilityPressHandler()
        return true
    }

    func updateAccessibility(selected: Bool) {
        guard let item else { return }
        var parts = [item.name, item.dimensionsDescription]
        if selected { parts.append("Selected") }
        if item.rating > 0 { parts.append("Rated \(item.rating)") }
        if item.isPick { parts.append("Pick") }
        if item.isReject { parts.append("Reject") }
        setAccessibilityLabel(parts.joined(separator: ", "))
        setAccessibilityHelp("Press Space to preview. Press Return to open. Use arrow keys to move.")
        setAccessibilityValue(selected ? "Selected" : "Not selected")
        overlayView.needsDisplay = true
    }
}

private final class TileOverlayView: NSView {
    weak var tile: GalleryTileView?
    var isHovering = false

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let tile, let item = tile.item else { return }
        let bounds = tile.bounds.insetBy(dx: 0.5, dy: 0.5)

        if tile.imageView.layer?.contents == nil {
            drawPlaceholder(in: bounds, failed: tile.thumbnailMissing)
        }

        if tile.selectionState {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            border.lineWidth = 3
            border.stroke()
        } else if isHovering {
            NSColor.white.withAlphaComponent(0.18).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            border.lineWidth = 1
            border.stroke()
        }

        if tile.selectMode {
            drawSelectionControl(in: bounds, selected: tile.selectionState)
        }

        guard tile.showsMetadata else { return }
        if item.rating > 0 {
            drawRating(item.rating, in: bounds)
        }
        if let label = item.label {
            drawLabel(label, in: bounds)
        }
        if item.flag != .none {
            drawFlag(item.flag, in: bounds)
        }
    }

    private func drawPlaceholder(in rect: NSRect, failed: Bool) {
        NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
        rect.fill()
        let symbolName = failed ? "exclamationmark.triangle" : "photo"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .light)
            let configured = image.withSymbolConfiguration(config) ?? image
            let size = configured.size
            let target = NSRect(x: rect.midX - size.width / 2,
                                y: rect.midY - size.height / 2,
                                width: size.width, height: size.height)
            configured.draw(in: target, from: .zero, operation: .sourceOver, fraction: failed ? 0.45 : 0.22)
        }
    }

    private func drawSelectionControl(in bounds: NSRect, selected: Bool) {
        let diameter: CGFloat = 19
        let circleRect = NSRect(x: 9, y: 9, width: diameter, height: diameter)
        let path = NSBezierPath(ovalIn: circleRect)
        if selected {
            NSColor.controlAccentColor.setFill()
            path.fill()
            NSColor.alternateSelectedControlTextColor.setStroke()
            let check = NSBezierPath()
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: circleRect.minX + 5, y: circleRect.minY + 9.5))
            check.line(to: NSPoint(x: circleRect.minX + 8, y: circleRect.minY + 12.5))
            check.line(to: NSPoint(x: circleRect.minX + 14, y: circleRect.minY + 6))
            check.stroke()
        } else {
            NSColor.black.withAlphaComponent(0.35).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawRating(_ rating: Int, in bounds: NSRect) {
        let text = "★ \(rating)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(x: 8, y: bounds.maxY - size.height - 12, width: size.width + 12, height: size.height + 4)
        drawScrim(in: rect, radius: 5)
        text.draw(at: NSPoint(x: rect.minX + 6, y: rect.minY + 2), withAttributes: attributes)
    }

    private func drawLabel(_ label: FinderColorLabel, in bounds: NSRect) {
        let color = Self.color(for: label)
        let dot = NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 18, y: 10, width: 9, height: 9))
        color.setFill()
        dot.fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        dot.lineWidth = 1
        dot.stroke()
    }

    private func drawFlag(_ flag: ImageFlag, in bounds: NSRect) {
        let diameter: CGFloat = 17
        let rect = NSRect(x: bounds.maxX - diameter - 8, y: bounds.maxY - diameter - 8,
                          width: diameter, height: diameter)
        let circle = NSBezierPath(ovalIn: rect)
        (flag == .pick ? NSColor.systemGreen : NSColor.systemRed).withAlphaComponent(0.92).setFill()
        circle.fill()
        NSColor.white.setStroke()
        let mark = NSBezierPath()
        mark.lineWidth = 1.8
        mark.lineCapStyle = .round
        if flag == .pick {
            mark.move(to: NSPoint(x: rect.minX + 5, y: rect.midY + 0.5))
            mark.line(to: NSPoint(x: rect.minX + 7.5, y: rect.midY + 3))
            mark.line(to: NSPoint(x: rect.minX + 12, y: rect.midY - 3))
        } else {
            mark.move(to: NSPoint(x: rect.minX + 5.5, y: rect.midY - 3.5))
            mark.line(to: NSPoint(x: rect.minX + 11.5, y: rect.midY + 2.5))
            mark.move(to: NSPoint(x: rect.minX + 11.5, y: rect.midY - 3.5))
            mark.line(to: NSPoint(x: rect.minX + 5.5, y: rect.midY + 2.5))
        }
        mark.stroke()
    }

    private func drawScrim(in rect: NSRect, radius: CGFloat) {
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    static func color(for label: FinderColorLabel) -> NSColor {
        switch label {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .gray: .systemGray
        }
    }
}
