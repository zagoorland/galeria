import AppKit

/// A custom collection layout with square Instagram tiles or justified rows in
/// original-aspect mode. Section headers pin to the top while scrolling.
final class GalleryGridLayout: NSCollectionViewLayout {
    var columns = 3 {
        didSet { if oldValue != columns { rebuild() } }
    }
    var usesOriginalAspect = false {
        didSet { if oldValue != usesOriginalAspect { rebuild() } }
    }
    var showsSectionHeaders = false {
        didSet { if oldValue != showsSectionHeaders { rebuild() } }
    }
    var aspectRatioProvider: ((IndexPath) -> CGFloat)?

    private let spacing: CGFloat = 2
    private let sectionSpacing: CGFloat = 14
    private let headerHeight: CGFloat = 34
    private var itemAttributes: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    private var headerAttributes: [Int: NSCollectionViewLayoutAttributes] = [:]
    private var sectionRanges: [(section: Int, start: CGFloat, end: CGFloat)] = []
    private var cachedKey: String?
    private var contentWidth: CGFloat = 0
    private var contentHeight: CGFloat = 0

    override var collectionViewContentSize: NSSize {
        NSSize(width: contentWidth, height: contentHeight)
    }

    /// Forces item frames to be recalculated when item aspect ratios or counts change.
    func rebuild() {
        cachedKey = nil
        invalidateLayout()
    }

    override func prepare() {
        super.prepare()
        guard let collectionView, let dataSource = collectionView.dataSource else { return }
        let width = collectionView.bounds.width
        guard width > 0 else { return }
        let sectionCount = dataSource.numberOfSections?(in: collectionView) ?? 1
        let counts = (0..<sectionCount).map { dataSource.collectionView(collectionView, numberOfItemsInSection: $0) }
        let key = "\(width)|\(columns)|\(usesOriginalAspect)|\(showsSectionHeaders)|\(counts)"
        if key == cachedKey, !itemAttributes.isEmpty || counts.allSatisfy({ $0 == 0 }) {
            return
        }

        cachedKey = key
        contentWidth = width
        itemAttributes.removeAll(keepingCapacity: true)
        headerAttributes.removeAll(keepingCapacity: true)
        sectionRanges.removeAll(keepingCapacity: true)

        var y: CGFloat = 0
        for section in 0..<sectionCount {
            let itemCount = counts[section]
            guard itemCount > 0 else { continue }
            let sectionStart = y
            if showsSectionHeaders {
                let attrs = NSCollectionViewLayoutAttributes(
                    forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                    with: IndexPath(item: 0, section: section)
                )
                attrs.frame = NSRect(x: 0, y: y, width: width, height: headerHeight)
                headerAttributes[section] = attrs
                y += headerHeight
            }

            if usesOriginalAspect {
                y = layoutJustifiedRows(section: section, count: itemCount, width: width, startY: y)
            } else {
                y = layoutSquares(section: section, count: itemCount, width: width, startY: y)
            }

            sectionRanges.append((section, sectionStart, y))
            y += sectionSpacing
        }

        contentHeight = max(0, y - (sectionRanges.isEmpty ? 0 : sectionSpacing))
    }

    private func layoutSquares(section: Int, count: Int, width: CGFloat, startY: CGFloat) -> CGFloat {
        let columns = max(1, self.columns)
        let itemWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        for index in 0..<count {
            let column = index % columns
            let row = index / columns
            let x = CGFloat(column) * (itemWidth + spacing)
            let y = startY + CGFloat(row) * (itemWidth + spacing)
            let indexPath = IndexPath(item: index, section: section)
            let attrs = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attrs.frame = NSRect(x: x, y: y, width: itemWidth, height: itemWidth)
            itemAttributes[indexPath] = attrs
        }
        let rows = Int(ceil(Double(count) / Double(columns)))
        return startY + CGFloat(rows) * itemWidth + CGFloat(max(rows - 1, 0)) * spacing
    }

    private func layoutJustifiedRows(section: Int, count: Int, width: CGFloat, startY: CGFloat) -> CGFloat {
        let columns = max(1, self.columns)
        let targetHeight = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var index = 0
        var y = startY

        while index < count {
            var row: [(index: Int, ratio: CGFloat)] = []
            var ratioSum: CGFloat = 0
            var rowHeight = targetHeight

            while index < count {
                let indexPath = IndexPath(item: index, section: section)
                let ratio = max(0.1, min(aspectRatioProvider?(indexPath) ?? 1, 20))
                row.append((index, ratio))
                ratioSum += ratio
                let available = max(1, width - spacing * CGFloat(row.count - 1))
                let candidate = available / ratioSum
                rowHeight = candidate
                index += 1
                if candidate <= targetHeight && row.count >= 2 { break }
                if candidate <= targetHeight * 0.65 { break }
            }

            if row.count == 1 {
                rowHeight = targetHeight
            }
            var x: CGFloat = 0
            for (position, entry) in row.enumerated() {
                var itemWidth = entry.ratio * rowHeight
                if position == row.count - 1, row.count > 1 {
                    itemWidth = max(1, width - x)
                }
                let indexPath = IndexPath(item: entry.index, section: section)
                let attrs = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
                attrs.frame = NSRect(x: x, y: y, width: itemWidth, height: rowHeight)
                itemAttributes[indexPath] = attrs
                x += itemWidth + spacing
            }
            y += rowHeight + spacing
        }
        return max(startY, y - spacing)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        var result = itemAttributes.values.filter { $0.frame.intersects(rect) }
        if showsSectionHeaders {
            result.append(contentsOf: visibleHeaderAttributes(in: rect))
        }
        return result
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        itemAttributes[indexPath]
    }

    override func layoutAttributesForSupplementaryView(
        ofKind elementKind: NSCollectionView.SupplementaryElementKind,
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        guard elementKind == NSCollectionView.elementKindSectionHeader,
              let attrs = headerAttributes[indexPath.section] else { return nil }
        let copy = attrs.copy() as? NSCollectionViewLayoutAttributes
        pinHeader(copy, section: indexPath.section)
        return copy
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        if abs(newBounds.width - contentWidth) > 0.5 { return true }
        return showsSectionHeaders
    }

    private func visibleHeaderAttributes(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard showsSectionHeaders, let collectionView else { return [] }
        let visible = collectionView.visibleRect
        let activeSection = sectionRanges.last(where: { visible.minY + 0.5 >= $0.start && visible.minY + 0.5 < $0.end })?.section
        var result: [NSCollectionViewLayoutAttributes] = []
        for (section, attrs) in headerAttributes {
            var frame = attrs.frame
            guard frame.intersects(rect) || section == activeSection else { continue }
            if section == activeSection {
                let range = sectionRanges.first(where: { $0.section == section })
                let maxY = max(frame.minY, (range?.end ?? frame.maxY) - headerHeight)
                frame.origin.y = min(max(frame.minY, visible.minY), maxY)
            }
            if let copy = attrs.copy() as? NSCollectionViewLayoutAttributes {
                copy.frame = frame
                copy.zIndex = 10
                result.append(copy)
            }
        }
        return result
    }

    private func pinHeader(_ attrs: NSCollectionViewLayoutAttributes?, section: Int) {
        guard let attrs, showsSectionHeaders, let collectionView else { return }
        let visible = collectionView.visibleRect
        let active = sectionRanges.last(where: { visible.minY + 0.5 >= $0.start && visible.minY + 0.5 < $0.end })?.section
        guard active == section, let range = sectionRanges.first(where: { $0.section == section }) else {
            attrs.zIndex = 10
            return
        }
        attrs.frame.origin.y = min(max(attrs.frame.minY, visible.minY), max(attrs.frame.minY, range.end - headerHeight))
        attrs.zIndex = 10
    }
}
