import Foundation
import Observation

/// An undo entry performs one side of an operation and returns the entry for
/// the opposite stack. That makes async, file-system operations redoable without
/// relying on Foundation's synchronous undo manager.
@MainActor
@Observable
final class UndoJournal {
    struct Entry {
        let name: String
        let action: @MainActor () async throws -> Entry?
    }

    private(set) var undoStack: [Entry] = []
    private(set) var redoStack: [Entry] = []
    private let limit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoTitle: String? { undoStack.last?.name }
    var redoTitle: String? { redoStack.last?.name }

    func record(_ entry: Entry) {
        undoStack.append(entry)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    @discardableResult
    func undo() async throws -> Bool {
        guard let entry = undoStack.popLast() else { return false }
        do {
            if let inverse = try await entry.action() {
                redoStack.append(inverse)
            }
            return true
        } catch {
            undoStack.append(entry)
            throw error
        }
    }

    @discardableResult
    func redo() async throws -> Bool {
        guard let entry = redoStack.popLast() else { return false }
        do {
            if let inverse = try await entry.action() {
                undoStack.append(inverse)
            }
            return true
        } catch {
            redoStack.append(entry)
            throw error
        }
    }
}
