import Foundation
import Testing
@testable import galeria

@MainActor
struct UndoJournalTests {
    @Test("Undo and redo return inverse entries")
    func undoRedo() async throws {
        let journal = UndoJournal()
        let state = TestState()
        state.value = 1

        journal.record(UndoJournal.Entry(name: "Set Value") {
            state.value = 0
            return UndoJournal.Entry(name: "Set Value") {
                state.value = 1
                return nil
            }
        })
        #expect(try await journal.undo())
        #expect(state.value == 0)
        #expect(journal.canRedo)
        #expect(try await journal.redo())
        #expect(state.value == 1)
    }

    @Test("A failing undo stays on the undo stack")
    func failingUndo() async {
        struct Failure: Error {}
        let journal = UndoJournal()
        journal.record(UndoJournal.Entry(name: "Fail") {
            throw Failure()
        })
        await #expect(throws: Failure.self) {
            try await journal.undo()
        }
        #expect(journal.canUndo)
        #expect(!journal.canRedo)
    }

    @MainActor
    private final class TestState {
        var value = 0
    }
}
