import CoreGraphics
import Testing
@testable import galeria

struct PreviewGestureTests {
    @Test("A left swipe advances and a right swipe goes back")
    func horizontalDirections() {
        #expect(PreviewSwipeClassifier.action(horizontal: -90, vertical: 5) == .next)
        #expect(PreviewSwipeClassifier.action(horizontal: 90, vertical: 5) == .previous)
    }

    @Test("A downward gesture closes and upward gestures do not")
    func verticalDirections() {
        #expect(PreviewSwipeClassifier.action(horizontal: 5, vertical: 90) == .close)
        #expect(PreviewSwipeClassifier.action(horizontal: 5, vertical: -90) == nil)
    }

    @Test("Short or diagonal gestures are ignored")
    func thresholds() {
        #expect(PreviewSwipeClassifier.action(horizontal: 20, vertical: 2) == nil)
        #expect(PreviewSwipeClassifier.action(horizontal: 55, vertical: 50) == nil)
        #expect(PreviewSwipeClassifier.action(horizontal: -55, vertical: 50) == nil)
    }

    @Test("Paging requires the distance threshold and an adjacent image")
    func pageThreshold() {
        #expect(PreviewSwipeClassifier.pageAction(offset: -100, width: 1000, velocity: 0,
                                                   hasPrevious: true, hasNext: true) == nil)
        #expect(PreviewSwipeClassifier.pageAction(offset: -220, width: 1000, velocity: 0,
                                                   hasPrevious: true, hasNext: true) == .next)
        #expect(PreviewSwipeClassifier.pageAction(offset: 220, width: 1000, velocity: 0,
                                                   hasPrevious: true, hasNext: true) == .previous)
        #expect(PreviewSwipeClassifier.pageAction(offset: -220, width: 1000, velocity: 0,
                                                   hasPrevious: true, hasNext: false) == nil)
    }

    @Test("A fast short flick pages even below the distance threshold")
    func flickThreshold() {
        #expect(PreviewSwipeClassifier.pageAction(offset: -80, width: 1000, velocity: -1500,
                                                   hasPrevious: true, hasNext: true) == .next)
        #expect(PreviewSwipeClassifier.pageAction(offset: -80, width: 1000, velocity: -300,
                                                   hasPrevious: true, hasNext: true) == nil)
    }

    @Test("The gesture locks to a clear horizontal or vertical axis")
    func axisLock() {
        #expect(PreviewSwipeClassifier.axis(horizontal: 40, vertical: 5) == .horizontal)
        #expect(PreviewSwipeClassifier.axis(horizontal: 5, vertical: 40) == .vertical)
        #expect(PreviewSwipeClassifier.axis(horizontal: 20, vertical: 20) == nil)
        #expect(PreviewSwipeClassifier.axis(horizontal: 5, vertical: 5) == nil)
    }
}
