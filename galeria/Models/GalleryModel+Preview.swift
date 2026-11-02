import AppKit
import Foundation

// MARK: - Opening and navigating

extension GalleryModel {
    var previewCurrentItem: ImageItem? {
        guard let previewIndex, previewIndex >= 0, previewIndex < previewItems.count else {
            guard let previewURL else { return nil }
            return folderStore.item(for: previewURL)
        }
        return previewItems[previewIndex]
    }

    var previewNeighborItems: [ImageItem] {
        guard let previewIndex, !previewItems.isEmpty else { return [] }
        var result: [ImageItem] = []
        for offset in -2...2 where offset != 0 {
            let index = previewIndex + offset
            if index >= 0, index < previewItems.count {
                result.append(previewItems[index])
            }
        }
        return result
    }

    var previewEffectiveScale: CGFloat {
        previewIsFit ? previewFitScale : previewZoomScale
    }

    var previewZoomPercent: Int {
        max(1, Int((previewEffectiveScale * 100).rounded()))
    }

    var isPreviewVisible: Bool { previewURL != nil }

    func openPreview(for url: URL) {
        let list = orderedItems
        guard !list.isEmpty else { return }
        let fallback = list.firstIndex(where: { selection.isSelected($0.url) }) ?? 0
        let index = list.firstIndex(where: { $0.url == url }) ?? fallback
        previewItems = list
        previewIndex = index
        previewURL = list[index].url
        selection.selectOnly(list[index].url)
        resetPreviewZoom()
        previewInfoVisible = false
        preloadPreviewNeighbors()
    }

    func closePreview() {
        if isSlideshowActive {
            stopSlideshow()
        }
        previewURL = nil
        previewItems = []
        previewIndex = nil
        previewInfoVisible = false
        isCullMode = false
        showRejectedReview = false
    }

    func closeAllOverlays() {
        if isSlideshowActive {
            isSlideshowActive = false
            isSlideshowPlaying = false
            slideshowEnteredFullscreen = false
        }
        previewURL = nil
        previewItems = []
        previewIndex = nil
        previewInfoVisible = false
        isComparePresented = false
        compareItems = []
        isCullMode = false
        showRejectedReview = false
    }

    func navigatePreview(by delta: Int, wrap: Bool = false) {
        guard !previewItems.isEmpty else { return }
        let current = previewIndex ?? 0
        var next = current + delta
        if wrap {
            if next < 0 { next = previewItems.count - 1 }
            if next >= previewItems.count { next = 0 }
        } else {
            next = min(max(next, 0), previewItems.count - 1)
        }
        guard next != current || previewURL == nil else { return }
        previewIndex = next
        previewURL = previewItems[next].url
        selection.selectOnly(previewItems[next].url)
        resetPreviewZoom()
        if previewInfoVisible { previewInfoVisible = true }
        preloadPreviewNeighbors()
    }

    func resetPreviewZoom() {
        previewIsFit = true
        previewZoomScale = 1
    }

    func preloadPreviewNeighbors() {
        let neighbors = previewNeighborItems
        guard !neighbors.isEmpty else { return }
        let service = previewImageService
        Task { await service.preload(items: neighbors) }
    }

    func refreshPreviewAfterFolderChange() {
        guard previewURL != nil else { return }
        let sorted = sections.flatMap(\.items)
        guard !sorted.isEmpty else {
            closePreview()
            return
        }
        if let current = previewURL, let index = sorted.firstIndex(where: { $0.url == current }) {
            previewItems = sorted
            previewIndex = index
        } else {
            let fallbackIndex = min(previewIndex ?? 0, sorted.count - 1)
            previewItems = sorted
            previewIndex = fallbackIndex
            previewURL = sorted[fallbackIndex].url
            selection.selectOnly(sorted[fallbackIndex].url)
            resetPreviewZoom()
        }
    }

    // MARK: - Zoom

    func setPreviewFit() {
        previewIsFit = true
        previewZoomScale = 1
    }

    func setPreviewActualSize() {
        previewIsFit = false
        previewZoomScale = 1
    }

    func zoomPreview(by factor: CGFloat) {
        let base = previewIsFit ? max(previewFitScale, 0.01) : previewZoomScale
        let next = min(max(base * factor, 0.02), 12)
        previewZoomScale = next
        previewIsFit = false
    }

    func togglePreviewInfo() {
        guard previewURL != nil else { return }
        previewInfoVisible.toggle()
    }

    func togglePreviewFilmstrip() {
        previewShowFilmstrip.toggle()
    }

    func togglePreviewLiveText() {
        previewLiveTextEnabled.toggle()
    }

    // MARK: - Slideshow

    func startSlideshow() {
        if previewURL == nil {
            guard let url = selectedItems.first?.url ?? orderedItems.first?.url else { return }
            openPreview(for: url)
        }
        guard previewURL != nil else { return }
        previewInfoVisible = false
        if let window = galleryWindow, !window.styleMask.contains(.fullScreen) {
            slideshowEnteredFullscreen = true
            window.toggleFullScreen(nil)
        }
        isSlideshowActive = true
        isSlideshowPlaying = true
    }

    func stopSlideshow() {
        isSlideshowPlaying = false
        isSlideshowActive = false
        if slideshowEnteredFullscreen, let window = galleryWindow,
           window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        slideshowEnteredFullscreen = false
    }

    func toggleSlideshowPlaying() {
        guard isSlideshowActive else { return }
        isSlideshowPlaying.toggle()
    }

    func handleSlideshowKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 49: // space
            toggleSlideshowPlaying()
            return true
        case 53: // escape
            stopSlideshow()
            return true
        case 123, 126:
            navigatePreview(by: -1, wrap: true)
            return true
        case 124, 125:
            navigatePreview(by: 1, wrap: true)
            return true
        default:
            return false
        }
    }

    // MARK: - Compare

    var canCompareSelection: Bool {
        (2...4).contains(selectedItems.count)
    }

    func openCompare() {
        let items = selectedItems
        guard (2...4).contains(items.count) else {
            NSSound.beep()
            return
        }
        compareItems = items
        isComparePresented = true
    }

    func closeCompare() {
        isComparePresented = false
        compareItems = []
    }

    // MARK: - Keyboard

    func handlePreviewKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123, 126: // left, up
            navigatePreview(by: -1)
            return true
        case 124, 125: // right, down
            navigatePreview(by: 1)
            return true
        case 49: // space toggles Quick Look
            closePreview()
            return true
        case 53: // escape
            closePreview()
            return true
        case 36: // return closes the preview
            closePreview()
            return true
        case 51, 117: // delete
            if !event.isARepeat {
                Task { await trashSelection() }
            }
            return true
        default:
            guard !event.isARepeat, let character = event.charactersIgnoringModifiers?.first else { return false }
            switch character {
            case "p", "P":
                if isCullMode {
                    Task { await markCullDecision(.pick) }
                } else {
                    Task { await setFlag(.pick) }
                }
                return true
            case "x", "X":
                if isCullMode {
                    Task { await markCullDecision(.reject) }
                } else {
                    Task { await setFlag(.reject) }
                }
                return true
            case "0":
                setPreviewFit()
                return true
            case "+", "=":
                zoomPreview(by: 1.25)
                return true
            case "-", "_":
                zoomPreview(by: 0.8)
                return true
            case "i", "I":
                togglePreviewInfo()
                return true
            case "f", "F":
                togglePreviewFilmstrip()
                return true
            case "l", "L":
                togglePreviewLiveText()
                return true
            default:
                if let rating = Int(String(character)), (1...5).contains(rating) {
                    Task { await setRating(rating) }
                    return true
                }
                if let number = Int(String(character)), (6...9).contains(number) {
                    let labels: [FinderColorLabel] = [.red, .yellow, .green, .blue]
                    Task { await setLabel(labels[number - 6]) }
                    return true
                }
                return false
            }
        }
    }
}

extension GalleryModel {
    func jumpPreview(to url: URL) {
        guard let index = previewItems.firstIndex(where: { $0.url == url }) else { return }
        previewIndex = index
        previewURL = url
        selection.selectOnly(url)
        resetPreviewZoom()
        preloadPreviewNeighbors()
    }

    func updatePreviewFitScale(_ value: CGFloat) {
        let clamped = max(value, 0.0001)
        guard abs(previewFitScale - clamped) > 0.0005 else { return }
        previewFitScale = clamped
    }
}

// MARK: - Culling

extension GalleryModel {
    var cullReviewedCount: Int {
        previewItems.filter { $0.isPick || $0.isReject }.count
    }

    var cullRejectedItems: [ImageItem] {
        previewItems.filter(\.isReject)
    }

    var cullAllReviewed: Bool {
        !previewItems.isEmpty && cullReviewedCount == previewItems.count
    }

    func startCullMode() {
        let order = orderedItems
        guard !order.isEmpty else {
            NSSound.beep()
            return
        }
        if isComparePresented { closeCompare() }
        previewItems = order
        let firstUnreviewed = order.firstIndex { $0.flag == .none } ?? 0
        previewIndex = firstUnreviewed
        previewURL = order[firstUnreviewed].url
        selection.selectOnly(order[firstUnreviewed].url)
        previewInfoVisible = false
        resetPreviewZoom()
        isCullMode = true
        isSlideshowActive = false
        isSlideshowPlaying = false
        preloadPreviewNeighbors()
    }

    func exitCullMode() {
        isCullMode = false
        showRejectedReview = false
        closePreview()
    }

    func markCullDecision(_ flag: ImageFlag) async {
        guard isCullMode, let current = previewCurrentItem else { return }
        await setFlag(flag)
        guard isCullMode else { return }
        if let index = previewItems.firstIndex(where: { $0.url == current.url }),
           index < previewItems.count - 1 {
            navigatePreview(by: 1)
        } else if let nextUnreviewed = previewItems.firstIndex(where: { $0.flag == .none && $0.url != current.url }) {
            jumpPreview(to: previewItems[nextUnreviewed].url)
        }
    }

    func clearCurrentCullFlag() async {
        await setFlag(.none)
    }
}

extension GalleryModel {
    var geotaggedItems: [ImageItem] {
        folderStore.items.filter(\.hasLocation)
    }

    func jumpToImageInGrid(_ url: URL) {
        showMapView = false
        closeCompare()
        if previewURL != nil { closePreview() }
        selection.selectOnly(url)
        if let item = folderStore.item(for: url) {
            infoItem = nil
            _ = item
        }
    }
}
