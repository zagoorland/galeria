import AppKit
import QuartzCore
import SwiftUI
import VisionKit

enum PreviewSwipeAction: Equatable {
    case previous
    case next
    case close
}

enum PreviewSwipeAxis: Equatable {
    case horizontal
    case vertical
}

enum PreviewSwipeClassifier {
    static func axis(horizontal x: CGFloat, vertical y: CGFloat) -> PreviewSwipeAxis? {
        let x = abs(x)
        let y = abs(y)
        guard max(x, y) >= 12 else { return nil }
        if x >= y * 1.1 { return .horizontal }
        if y >= x * 1.35 { return .vertical }
        return nil
    }

    static func action(horizontal x: CGFloat, vertical y: CGFloat) -> PreviewSwipeAction? {
        if abs(x) > max(44, abs(y) * 1.35) {
            return x < 0 ? .next : .previous
        }
        if y > max(60, abs(x) * 1.35) {
            return .close
        }
        return nil
    }

    static func pageAction(
        offset: CGFloat,
        width: CGFloat,
        velocity: CGFloat,
        hasPrevious: Bool,
        hasNext: Bool
    ) -> PreviewSwipeAction? {
        let threshold = max(44, max(width, 1) * 0.2)
        if offset <= -threshold, hasNext { return .next }
        if offset >= threshold, hasPrevious { return .previous }

        // A quick flick should page even when the finger only travelled a
        // short distance, matching the feel of a native pager.
        if abs(offset) >= 56, abs(velocity) >= 1_200 {
            if velocity < 0, hasNext { return .next }
            if velocity > 0, hasPrevious { return .previous }
        }
        return nil
    }
}

/// The interactive photo canvas for Quick Preview. It handles fit/actual-size
/// zoom, scroll panning, double-click zoom, Live Text, trackpad swipes, and
/// drag-out.
struct PreviewCanvas: NSViewRepresentable {
    let image: NSImage?
    let identity: String
    let fileName: String
    let isAnimated: Bool
    let fileURL: URL?
    let previousImage: NSImage?
    let nextImage: NSImage?
    let fitScale: CGFloat
    @Binding var isFitMode: Bool
    @Binding var absoluteScale: CGFloat
    let liveTextEnabled: Bool
    var onZoomChanged: (() -> Void)?
    var onDragOperation: ((NSDragOperation) -> Void)?
    var onSwipe: ((PreviewSwipeAction) -> Void)?
    var onPagingChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PreviewCanvasView {
        let view = PreviewCanvasView()
        view.onZoomChanged = { [weak coordinator = context.coordinator] newScale, fit in
            guard let coordinator else { return }
            coordinator.parent.absoluteScale = newScale
            coordinator.parent.isFitMode = fit
            coordinator.parent.onZoomChanged?()
        }
        view.onDragOperation = { [weak coordinator = context.coordinator] operation in
            coordinator?.parent.onDragOperation?(operation)
        }
        view.onSwipe = { [weak coordinator = context.coordinator] action in
            coordinator?.parent.onSwipe?(action)
        }
        view.onPagingChanged = { [weak coordinator = context.coordinator] isPaging in
            coordinator?.parent.onPagingChanged?(isPaging)
        }
        return view
    }

    func updateNSView(_ view: PreviewCanvasView, context: Context) {
        context.coordinator.parent = self
        view.update(
            image: image,
            identity: identity,
            fileName: fileName,
            isAnimated: isAnimated,
            fileURL: fileURL,
            previousImage: previousImage,
            nextImage: nextImage,
            fitScale: fitScale,
            isFitMode: isFitMode,
            absoluteScale: absoluteScale,
            liveTextEnabled: liveTextEnabled
        )
    }

    static func dismantleNSView(_ view: PreviewCanvasView, coordinator: Coordinator) {
        view.prepareForRemoval()
    }

    @MainActor
    final class Coordinator {
        var parent: PreviewCanvas

        init(_ parent: PreviewCanvas) {
            self.parent = parent
        }
    }
}

final class PreviewCanvasView: NSView, NSDraggingSource {
    var onZoomChanged: ((CGFloat, Bool) -> Void)?
    var onDragOperation: ((NSDragOperation) -> Void)?
    var onSwipe: ((PreviewSwipeAction) -> Void)?
    var onPagingChanged: ((Bool) -> Void)?

    private let imageView = NonInteractiveImageView()
    private let previousImageView = NonInteractiveImageView()
    private let nextImageView = NonInteractiveImageView()
    private let liveTextOverlay = ImageAnalysisOverlayView(frame: .zero)
    private var scrollMonitor: Any?
    private var magnificationGesture: NSMagnificationGestureRecognizer?
    private var analysisTask: Task<Void, Never>?
    private var imageIdentity = ""
    private var fileName = ""
    private var fileURL: URL?
    private var previousImage: NSImage?
    private var nextImage: NSImage?
    private var pageOffsetX: CGFloat = 0
    private var swipeAxis: PreviewSwipeAxis?
    private var swipeStartTime: TimeInterval = 0
    private var pageCommitPending = false
    private var pageAnimationTimer: Timer?
    private var pageAnimationStartOffset: CGFloat = 0
    private var pageAnimationTargetOffset: CGFloat = 0
    private var pageAnimationStartTime: TimeInterval = 0
    private var pageAnimationDuration: TimeInterval = 0
    private var pageAnimationAction: PreviewSwipeAction?
    private var isPageAnimating = false
    private var isIgnoringSwipe = false
    private var fitScale: CGFloat = 1
    private var isFitMode = true
    private var absoluteScale: CGFloat = 1
    private var liveTextEnabled = false
    private var pan: CGPoint = .zero
    private var pinchStartScale: CGFloat?
    private var dragOrigin: NSPoint?
    private var didStartDrag = false
    private var swipeAccumulatedX: CGFloat = 0
    private var swipeAccumulatedY: CGFloat = 0
    private var isTrackingSwipe = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        for view in [previousImageView, nextImageView] {
            view.imageScaling = .scaleProportionallyUpOrDown
            view.imageFrameStyle = .none
            view.wantsLayer = true
            view.isHidden = true
            addSubview(view)
        }

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .none
        imageView.wantsLayer = true
        addSubview(imageView)

        liveTextOverlay.wantsLayer = true
        liveTextOverlay.trackingImageView = imageView
        liveTextOverlay.preferredInteractionTypes = .textSelection
        liveTextOverlay.isHidden = true
        addSubview(liveTextOverlay)

        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Image Preview")

        let gesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        addGestureRecognizer(gesture)
        magnificationGesture = gesture
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        analysisTask?.cancel()
        pageAnimationTimer?.invalidate()
        removeScrollMonitor()
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeScrollMonitor()
        guard window != nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else { return event }
            if self.isFitMode, self.handleSwipeScroll(event) { return nil }
            self.panBy(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
            return nil
        }
    }

    func prepareForRemoval() {
        analysisTask?.cancel()
        cancelPageAnimation(resetOffset: false)
        removeScrollMonitor()
    }

    func update(
        image: NSImage?,
        identity: String,
        fileName: String,
        isAnimated: Bool,
        fileURL: URL?,
        previousImage: NSImage?,
        nextImage: NSImage?,
        fitScale: CGFloat,
        isFitMode: Bool,
        absoluteScale: CGFloat,
        liveTextEnabled: Bool
    ) {
        let imageChanged = identity != imageIdentity
        if imageChanged {
            imageIdentity = identity
            self.fileName = fileName
            self.fileURL = fileURL
            pan = .zero
            cancelPageAnimation(resetOffset: false)
            pageOffsetX = 0
            pageCommitPending = false
            isIgnoringSwipe = false
            resetSwipeTracking()
            onPagingChanged?(false)
            imageView.image = image
            imageView.animates = isAnimated
            setAccessibilityLabel("\(fileName), image preview")
            if liveTextEnabled { analyzeLiveText(image) }
        } else {
            self.fileURL = fileURL
            if imageView.image !== image {
                imageView.image = image
            }
        }
        self.previousImage = previousImage
        self.nextImage = nextImage
        previousImageView.image = previousImage
        nextImageView.image = nextImage
        let fitChanged = abs(self.fitScale - fitScale) > 0.0001
        let fitModeChanged = self.isFitMode != isFitMode
        self.fitScale = max(fitScale, 0.0001)
        self.isFitMode = isFitMode
        self.absoluteScale = max(absoluteScale, 0.01)
        if fitModeChanged {
            resetSwipeTracking()
            if !isFitMode {
                pageOffsetX = 0
                pageCommitPending = false
            }
        }
        updateLiveTextVisibility()
        if self.liveTextEnabled != liveTextEnabled {
            self.liveTextEnabled = liveTextEnabled
            updateLiveTextVisibility()
            if liveTextEnabled {
                analyzeLiveText(image)
            } else {
                analysisTask?.cancel()
                liveTextOverlay.analysis = nil
            }
        }
        if imageChanged || fitChanged || isFitMode {
            needsLayout = true
        }
        layoutImage()
    }

    override func layout() {
        super.layout()
        layoutImage()
    }

    private var effectiveScale: CGFloat {
        isFitMode ? fitScale : absoluteScale
    }

    private func layoutImage() {
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else {
            imageView.frame = .zero
            liveTextOverlay.frame = .zero
            return
        }
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }
        let displayWidth = sourceSize.width * effectiveScale
        let displayHeight = sourceSize.height * effectiveScale
        clampPan(displayWidth: displayWidth, displayHeight: displayHeight)
        let offset = isFitMode ? pageOffsetX : 0
        let origin = NSPoint(
            x: (bounds.width - displayWidth) / 2 + pan.x + offset,
            y: (bounds.height - displayHeight) / 2 + pan.y
        )
        imageView.frame = NSRect(x: origin.x, y: origin.y, width: displayWidth, height: displayHeight)
        liveTextOverlay.frame = imageView.frame
        layoutAdjacentImage(previousImageView, image: previousImage, direction: -1)
        layoutAdjacentImage(nextImageView, image: nextImage, direction: 1)
    }

    private func layoutAdjacentImage(_ view: NSImageView, image: NSImage?, direction: CGFloat) {
        guard isFitMode, let image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            view.isHidden = true
            view.frame = .zero
            return
        }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        let x = (bounds.width - width) / 2 + direction * bounds.width + pageOffsetX
        let y = (bounds.height - height) / 2
        view.frame = NSRect(x: x, y: y, width: width, height: height)
        view.isHidden = false
    }

    private func clampPan(displayWidth: CGFloat, displayHeight: CGFloat) {
        let maxX = max(0, (displayWidth - bounds.width) / 2)
        let maxY = max(0, (displayHeight - bounds.height) / 2)
        pan.x = min(max(pan.x, -maxX), maxX)
        pan.y = min(max(pan.y, -maxY), maxY)
    }

    private func panBy(dx: CGFloat, dy: CGFloat) {
        guard bounds.width > 0 else { return }
        if isFitMode {
            // Panning a fitting image has no useful range; leave it centered.
            return
        }
        let multiplier: CGFloat = 1
        pan.x += dx * multiplier
        pan.y += dy * multiplier
        layoutImage()
    }

    // MARK: Trackpad swipes

    /// Handles the two-finger scroll stream produced by a trackpad at fit
    /// scale. The current image follows the fingers and the adjacent image
    /// slides in from the side; release snaps to the next page or back.
    /// Zoomed images keep using the scroll stream for panning.
    private func handleSwipeScroll(_ event: NSEvent) -> Bool {
        guard isFitMode, event.hasPreciseScrollingDeltas else { return false }
        let phase = event.phase
        // Ignore the momentum tail, but do not ignore an ended event merely
        // because macOS attached a momentum phase to it.
        if phase.isEmpty, !event.momentumPhase.isEmpty { return true }
        if phase.contains(.mayBegin) { return true }

        if phase.contains(.began) {
            if isPageAnimating || pageCommitPending {
                isIgnoringSwipe = true
                return true
            }
            isIgnoringSwipe = false
            resetSwipeTracking()
            pageOffsetX = 0
            pageCommitPending = false
            isTrackingSwipe = true
            swipeStartTime = CACurrentMediaTime()
            updateLiveTextVisibility()
        }
        if isIgnoringSwipe {
            if phase.contains(.ended) || phase.contains(.cancelled) {
                isIgnoringSwipe = false
            }
            return true
        }
        guard isTrackingSwipe else { return false }

        let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let deltaX = event.scrollingDeltaX * direction
        let deltaY = event.scrollingDeltaY * direction
        swipeAccumulatedX += deltaX
        swipeAccumulatedY += deltaY

        if swipeAxis == nil,
           let axis = PreviewSwipeClassifier.axis(horizontal: swipeAccumulatedX,
                                                  vertical: swipeAccumulatedY) {
            swipeAxis = axis
            if axis == .horizontal { onPagingChanged?(true) }
        }

        if swipeAxis == .horizontal {
            // Apply deltas incrementally. If a neighbor image finishes loading
            // during the gesture, its page can resume smoothly instead of
            // jumping to the entire accumulated distance at once.
            pageOffsetX = boundedPageOffset(for: pageOffsetX + deltaX)
            layoutImage()
        }

        if phase.contains(.cancelled) {
            cancelSwipe()
            return true
        }
        if phase.contains(.ended) {
            finishSwipe()
            return true
        }
        return true
    }

    private func boundedPageOffset(for raw: CGFloat) -> CGFloat {
        let hasTarget = raw < 0 ? nextImage != nil : previousImage != nil
        guard hasTarget else {
            let magnitude = min(abs(raw) * 0.22, 28)
            return raw < 0 ? -magnitude : magnitude
        }
        let limit = max(bounds.width, 1)
        return min(max(raw, -limit), limit)
    }

    private func finishSwipe() {
        guard isTrackingSwipe else { return }
        isTrackingSwipe = false

        if swipeAxis == .horizontal {
            let width = max(bounds.width, 1)
            let elapsed = max(CACurrentMediaTime() - swipeStartTime, 0.01)
            let velocity = swipeAccumulatedX / elapsed
            let action = PreviewSwipeClassifier.pageAction(
                offset: pageOffsetX,
                width: width,
                velocity: velocity,
                hasPrevious: previousImage != nil,
                hasNext: nextImage != nil
            )
            if let action {
                snapPage(to: action == .next ? -width : width, action: action)
            } else {
                snapPage(to: 0, action: nil)
            }
            return
        }

        if swipeAxis == .vertical,
           PreviewSwipeClassifier.action(horizontal: swipeAccumulatedX,
                                         vertical: swipeAccumulatedY) == .close {
            resetSwipeTracking()
            updateLiveTextVisibility()
            onSwipe?(.close)
            return
        }

        resetSwipeTracking()
        updateLiveTextVisibility()
    }

    private func cancelSwipe() {
        guard isTrackingSwipe || pageOffsetX != 0 else {
            resetSwipeTracking()
            updateLiveTextVisibility()
            return
        }
        isTrackingSwipe = false
        resetSwipeTracking()
        snapPage(to: 0, action: nil)
    }

    /// Drives snapping from the run loop rather than layering a Core Animation
    /// on top of the frames. SwiftUI can update the canvas during a gesture
    /// (for example when a neighbor preview finishes loading); a model-driven
    /// timer keeps every layout pass at the same interpolated offset.
    private func snapPage(to targetOffset: CGFloat, action: PreviewSwipeAction?) {
        let width = max(bounds.width, 1)
        let target = min(max(targetOffset, -width), width)
        guard abs(target - pageOffsetX) > 0.5 else {
            if let action {
                pageCommitPending = true
                updateLiveTextVisibility()
                onSwipe?(action)
            } else {
                pageOffsetX = 0
                pageCommitPending = false
                resetSwipeTracking()
                layoutImage()
                updateLiveTextVisibility()
                onPagingChanged?(false)
            }
            return
        }

        pageAnimationTimer?.invalidate()
        pageAnimationStartOffset = pageOffsetX
        pageAnimationTargetOffset = target
        pageAnimationStartTime = CACurrentMediaTime()
        pageAnimationDuration = action == nil ? 0.19 : 0.23
        pageAnimationAction = action
        isPageAnimating = true
        pageCommitPending = false
        updateLiveTextVisibility()

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.stepPageAnimation()
        }
        timer.tolerance = 0.001
        RunLoop.main.add(timer, forMode: .common)
        pageAnimationTimer = timer
    }

    private func stepPageAnimation() {
        guard isPageAnimating else {
            pageAnimationTimer?.invalidate()
            pageAnimationTimer = nil
            return
        }
        let elapsed = CACurrentMediaTime() - pageAnimationStartTime
        let progress = min(1, max(0, elapsed / max(pageAnimationDuration, 0.001)))
        let eased = 1 - pow(1 - progress, 3)
        pageOffsetX = pageAnimationStartOffset
            + (pageAnimationTargetOffset - pageAnimationStartOffset) * eased
        layoutImage()
        if progress >= 1 {
            finishPageAnimation()
        }
    }

    private func finishPageAnimation() {
        pageAnimationTimer?.invalidate()
        pageAnimationTimer = nil
        isPageAnimating = false
        pageOffsetX = pageAnimationTargetOffset
        layoutImage()
        let action = pageAnimationAction
        pageAnimationAction = nil
        if let action {
            pageCommitPending = true
            updateLiveTextVisibility()
            onSwipe?(action)
        } else {
            pageOffsetX = 0
            pageCommitPending = false
            resetSwipeTracking()
            layoutImage()
            updateLiveTextVisibility()
            onPagingChanged?(false)
        }
    }

    private func cancelPageAnimation(resetOffset: Bool) {
        pageAnimationTimer?.invalidate()
        pageAnimationTimer = nil
        isPageAnimating = false
        pageAnimationAction = nil
        if resetOffset {
            pageOffsetX = 0
            pageCommitPending = false
            layoutImage()
            updateLiveTextVisibility()
            onPagingChanged?(false)
        }
    }

    private func resetSwipeTracking() {
        swipeAccumulatedX = 0
        swipeAccumulatedY = 0
        swipeAxis = nil
        isTrackingSwipe = false
    }

    private func updateLiveTextVisibility() {
        liveTextOverlay.isHidden = !liveTextEnabled
            || isTrackingSwipe
            || pageOffsetX != 0
            || pageCommitPending
            || isPageAnimating
    }

    /// Native swipe events use the documented direction for swipe-down. The
    /// horizontal paging path is deliberately driven only by the continuous
    /// trackpad scroll stream so a single gesture cannot commit twice.
    override func swipe(with event: NSEvent) {
        guard isFitMode else {
            super.swipe(with: event)
            return
        }
        if abs(event.deltaY) >= abs(event.deltaX), event.deltaY < 0 {
            onSwipe?(.close)
        } else {
            super.swipe(with: event)
        }
    }

    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartScale = effectiveScale
        case .changed:
            guard let start = pinchStartScale else { return }
            let next = min(max(start * (1 + gesture.magnification), 0.02), 12)
            isFitMode = false
            absoluteScale = next
            onZoomChanged?(next, false)
            layoutImage()
        default:
            pinchStartScale = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            if isFitMode {
                isFitMode = false
                absoluteScale = 1
                pan = .zero
                onZoomChanged?(1, false)
            } else {
                isFitMode = true
                pan = .zero
                onZoomChanged?(fitScale, true)
            }
            layoutImage()
            return
        }
        dragOrigin = convert(event.locationInWindow, from: nil)
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !liveTextEnabled, let origin = dragOrigin, !didStartDrag, let url = fileURL else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - origin.x, point.y - origin.y) < 4 { return }
        didStartDrag = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let dragSize = NSSize(width: 112, height: 112)
        let dragRect = NSRect(x: point.x - dragSize.width / 2, y: point.y - dragSize.height / 2,
                              width: dragSize.width, height: dragSize.height)
        if let image = imageView.image {
            item.setDraggingFrame(dragRect, contents: image)
        } else {
            item.setDraggingFrame(dragRect, contents: NSImage(systemSymbolName: "photo", accessibilityDescription: nil))
        }
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        didStartDrag = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragOperation?(operation)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }

    private func analyzeLiveText(_ image: NSImage?) {
        analysisTask?.cancel()
        guard let image, liveTextEnabled else {
            liveTextOverlay.analysis = nil
            return
        }
        updateLiveTextVisibility()
        let analyzer = ImageAnalyzer()
        let configuration = ImageAnalyzer.Configuration(.text)
        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let analysis = try await analyzer.analyze(image, orientation: .up, configuration: configuration)
                guard !Task.isCancelled else { return }
                self.liveTextOverlay.analysis = analysis
            } catch {
                self.liveTextOverlay.analysis = nil
            }
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }
}

private final class NonInteractiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
