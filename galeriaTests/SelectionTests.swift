import Foundation
import Testing
@testable import galeria

@MainActor
struct SelectionTests {
    private let a = URL(fileURLWithPath: "/tmp/a.jpg")
    private let b = URL(fileURLWithPath: "/tmp/b.jpg")
    private let c = URL(fileURLWithPath: "/tmp/c.jpg")
    private let d = URL(fileURLWithPath: "/tmp/d.jpg")
    private let e = URL(fileURLWithPath: "/tmp/e.jpg")

    private var order: [URL] { [a, b, c, d, e] }

    @Test("Plain, shift, and command clicks follow Finder semantics")
    func clickSemantics() {
        let selection = SelectionModel()
        selection.click(b, modifiers: [], in: order, selectMode: false)
        #expect(selection.selectedIDs == [b])
        #expect(selection.anchorID == b)

        selection.click(d, modifiers: [.shift], in: order, selectMode: false)
        #expect(selection.selectedIDs == [b, c, d])

        selection.click(a, modifiers: [.command], in: order, selectMode: false)
        #expect(selection.selectedIDs == [a, b, c, d])
        #expect(selection.anchorID == a)

        selection.click(c, modifiers: [.shift], in: order, selectMode: false)
        #expect(selection.selectedIDs == [a, b, c])
    }

    @Test("Command-click toggles and Select mode ignores modifiers")
    func toggling() {
        let selection = SelectionModel()
        selection.click(b, modifiers: [], in: order, selectMode: true)
        #expect(selection.selectedIDs == [b])
        selection.click(c, modifiers: [], in: order, selectMode: true)
        #expect(selection.selectedIDs == [b, c])
        selection.click(b, modifiers: [], in: order, selectMode: true)
        #expect(selection.selectedIDs == [c])

        selection.setSelectMode(false)
        selection.click(e, modifiers: [.command], in: order, selectMode: false)
        #expect(selection.selectedIDs == [c, e])
        selection.click(c, modifiers: [.command], in: order, selectMode: false)
        #expect(selection.selectedIDs == [e])
    }

    @Test("Range with additive modifier preserves other selections")
    func additiveRange() {
        let selection = SelectionModel()
        selection.selectOnly(a)
        selection.click(e, modifiers: [.shift], in: order, selectMode: false)
        #expect(selection.selectedIDs == Set(order))
        selection.click(b, modifiers: [.command], in: order, selectMode: false)
        #expect(!selection.selectedIDs.contains(b))
        selection.click(d, modifiers: [.shift, .command], in: order, selectMode: false)
        #expect(selection.selectedIDs.contains(b))
        #expect(selection.selectedIDs.contains(a))
    }

    @Test("Selection retains only available items")
    func retention() {
        let selection = SelectionModel()
        selection.selectAll(order)
        selection.retainOnly(available: [a, c, e])
        #expect(selection.selectedIDs == [a, c, e])
        #expect(selection.anchorID == a)
    }

    @Test("Delete selection advances like Finder")
    func nextAfterDeletion() {
        let selection = SelectionModel()
        #expect(selection.selectionAfterRemoving([b], in: order) == c)
        #expect(selection.selectionAfterRemoving([d, e], in: order) == c)
        #expect(selection.selectionAfterRemoving([c, d, e], in: order) == b)
        #expect(selection.selectionAfterRemoving(Set(order), in: order) == nil)
    }

    @Test("Keyboard focus moves within bounds")
    func focusMovement() {
        let selection = SelectionModel()
        selection.moveFocus(delta: 1, in: order)
        #expect(selection.selectedIDs == [a])
        selection.moveFocus(delta: 2, in: order)
        #expect(selection.selectedIDs == [c])
        selection.moveFocus(delta: -100, in: order)
        #expect(selection.selectedIDs == [a])
        selection.moveFocus(delta: 100, in: order)
        #expect(selection.selectedIDs == [e])
    }
}
