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
}
