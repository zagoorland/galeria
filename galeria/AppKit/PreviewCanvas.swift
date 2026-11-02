import AppKit
import SwiftUI
import VisionKit

enum PreviewSwipeAction: Equatable {
    case previous
    case next
    case close
}

enum PreviewSwipeClassifier {
    static func action(horizontal x: CGFloat, vertical y: CGFloat) -> PreviewSwipeAction? {
        if abs(x) > max(44, abs(y) * 1.35) {
            return x < 0 ? .next : .previous
        }
        if y > max(60, abs(x) * 1.35) {
            return .close
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
    let fitScale: CGFloat
    @Binding var isFitMode: Bool
    @Binding var absoluteScale: CGFloat
    let liveTextEnabled: Bool
    var onZoomChanged: (() -> Void)?
    var onDragOperation: ((NSDragOperation) -> Void)?
    var onSwipe: ((PreviewSwipeAction) -> Void)?

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

    private let imageView = NonInteractiveImageView()
    private let liveTextOverlay = ImageAnalysisOverlayView(frame: .zero)
    private var scrollMonitor: Any?
    private var magnificationGesture: NSMagnificationGestureRecognizer?
    private var analysisTask: Task<Void, Never>?
    private var imageIdentity = ""
    private var fileName = ""
    private var fileURL: URL?
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
        removeScrollMonitor()
    }

    func update(
        image: NSImage?,
        identity: String,
        fileName: String,
        isAnimated: Bool,
        fileURL: URL?,
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
        let fitChanged = abs(self.fitScale - fitScale) > 0.0001
        let fitModeChanged = self.isFitMode != isFitMode
        self.fitScale = max(fitScale, 0.0001)
        self.isFitMode = isFitMode
        self.absoluteScale = max(absoluteScale, 0.01)
        if imageChanged || fitModeChanged {
            resetSwipeTracking()
        }
        if self.liveTextEnabled != liveTextEnabled {
            self.liveTextEnabled = liveTextEnabled
            liveTextOverlay.isHidden = !liveTextEnabled
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
        let origin = NSPoint(
            x: (bounds.width - displayWidth) / 2 + pan.x,
            y: (bounds.height - displayHeight) / 2 + pan.y
        )
        imageView.frame = NSRect(x: origin.x, y: origin.y, width: displayWidth, height: displayHeight)
        liveTextOverlay.frame = imageView.frame
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
    /// scale. Zoomed images keep using the scroll stream for panning.
    private func handleSwipeScroll(_ event: NSEvent) -> Bool {
        guard isFitMode, event.hasPreciseScrollingDeltas else { return false }
        if !event.momentumPhase.isEmpty { return true }

        let phase = event.phase
        if phase.contains(.mayBegin) { return true }
        if phase.contains(.began) {
            swipeAccumulatedX = 0
            swipeAccumulatedY = 0
            isTrackingSwipe = true
        }
        guard isTrackingSwipe else { return false }
        if phase.contains(.cancelled) {
            resetSwipeTracking()
            return true
        }

        // Normalize to physical finger direction. With the default "natural"
        // setting the deltas already follow the fingers; when the preference
        // is inverted they arrive in the opposite direction.
        let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        swipeAccumulatedX += event.scrollingDeltaX * direction
        swipeAccumulatedY += event.scrollingDeltaY * direction
        if phase.contains(.ended) {
            finishSwipe()
        }
        return true
    }

    private func finishSwipe() {
        let x = swipeAccumulatedX
        let y = swipeAccumulatedY
        resetSwipeTracking()
        guard isFitMode, let action = PreviewSwipeClassifier.action(horizontal: x, vertical: y) else { return }
        onSwipe?(action)
    }

    private func resetSwipeTracking() {
        swipeAccumulatedX = 0
        swipeAccumulatedY = 0
        isTrackingSwipe = false
    }

    /// Native swipe events (for trackpad settings that emit them) use the
    /// documented direction: positive X is a left swipe, negative Y is down.
    override func swipe(with event: NSEvent) {
        guard isFitMode else {
            super.swipe(with: event)
            return
        }
        if abs(event.deltaX) > abs(event.deltaY), event.deltaX != 0 {
            onSwipe?(event.deltaX > 0 ? .next : .previous)
        } else if event.deltaY < 0 {
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
        liveTextOverlay.isHidden = false
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
