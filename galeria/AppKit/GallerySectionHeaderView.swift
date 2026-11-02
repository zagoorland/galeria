import AppKit

final class GallerySectionHeaderView: NSView, NSCollectionViewElement {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("GallerySectionHeader")
    private let label = NSTextField(labelWithString: "")
    private let blurView = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        blurView.material = .headerView
        blurView.blendingMode = .withinWindow
        blurView.state = .active
        addSubview(blurView)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        blurView.frame = bounds
        label.frame = NSRect(x: 12, y: 1, width: max(0, bounds.width - 24), height: bounds.height - 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.6).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    func configure(title: String) {
        label.stringValue = title
        label.setAccessibilityLabel(title)
    }
}
