import Foundation
import Observation

/// A UI-free description of modifier keys used by selection logic.
struct SelectionModifiers: OptionSet, Sendable {
    let rawValue: Int
    static let shift = SelectionModifiers(rawValue: 1 << 0)
    static let command = SelectionModifiers(rawValue: 1 << 1)
}

/// Owns selected image IDs, the range anchor, and Finder-style range/toggle logic.
@Observable
@MainActor
final class SelectionModel {
    private(set) var selectedIDs: Set<URL> = []
    private(set) var anchorID: URL?
    private(set) var selectMode = false

    var isEmpty: Bool { selectedIDs.isEmpty }
    var count: Int { selectedIDs.count }

    func setSelectMode(_ enabled: Bool) {
        guard selectMode != enabled else { return }
        selectMode = enabled
        if !enabled {
            anchorID = selectedIDs.count == 1 ? selectedIDs.first : anchorID
        }
    }

    func isSelected(_ id: URL) -> Bool { selectedIDs.contains(id) }

    /// Applies a click using Finder semantics. In Select mode an unmodified click toggles.
    func click(_ id: URL, modifiers: SelectionModifiers, in order: [URL], selectMode: Bool) {
        if selectMode && modifiers.isEmpty {
            toggle(id)
            anchorID = id
            return
        }

        if modifiers.contains(.shift) {
            applyRange(to: id, adding: modifiers.contains(.command), in: order)
            return
        }

        if modifiers.contains(.command) {
            toggle(id)
            anchorID = id
            return
        }

        selectedIDs = [id]
        anchorID = id
    }

    /// Applies a range from the anchor to `id`, optionally preserving an existing selection.
    func applyRange(to id: URL, adding: Bool = false, in order: [URL]) {
        guard let target = order.firstIndex(of: id) else { return }
        let anchor: Int
        if let anchorID, let anchorIndex = order.firstIndex(of: anchorID) {
            anchor = anchorIndex
        } else {
            anchor = target
            anchorID = id
        }
        let bounds = min(anchor, target)...max(anchor, target)
        let range = Set(order[bounds])
        selectedIDs = adding ? selectedIDs.union(range) : range
    }

    func toggle(_ id: URL) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func selectOnly(_ id: URL) {
        selectedIDs = [id]
        anchorID = id
    }

    /// Replaces the selection from a model-driven undo, restore, or external action.
    func setSelection(_ ids: Set<URL>, anchor: URL? = nil) {
        selectedIDs = ids
        if let anchor, ids.contains(anchor) {
            anchorID = anchor
        } else {
            anchorID = ids.first
        }
    }

    func selectAll(_ ids: [URL]) {
        selectedIDs = Set(ids)
        if let currentAnchor = anchorID, selectedIDs.contains(currentAnchor) {
            // Keep the existing anchor.
        } else {
            anchorID = ids.first
        }
    }

    func clear() {
        selectedIDs.removeAll()
        anchorID = nil
    }

    /// Mirrors a selection made by NSCollectionView's native mouse handling.
    func syncFromCollectionView(_ ids: Set<URL>, order: [URL]) {
        selectedIDs = ids
        if ids.count == 1 {
            anchorID = ids.first
        } else if let anchorID, !ids.contains(anchorID) {
            self.anchorID = order.first(where: ids.contains)
        }
    }

    func retainOnly(available: Set<URL>) {
        selectedIDs.formIntersection(available)
        if let anchorID, !available.contains(anchorID) {
            self.anchorID = selectedIDs.first
        }
    }

    /// Returns the item Finder would select after deleting `deleted`: the first
    /// survivor after the deleted range, otherwise the nearest survivor before it.
    func selectionAfterRemoving(_ deleted: Set<URL>, in order: [URL]) -> URL? {
        guard !order.isEmpty else { return nil }
        let deletedIndices = deleted.compactMap { order.firstIndex(of: $0) }
        guard let firstIndex = deletedIndices.min() else { return nil }
        if firstIndex < order.count {
            for index in firstIndex..<order.count where !deleted.contains(order[index]) {
                return order[index]
            }
        }
        if firstIndex > 0 {
            for index in stride(from: firstIndex - 1, through: 0, by: -1) where !deleted.contains(order[index]) {
                return order[index]
            }
        }
        return nil
    }

    func moveFocus(delta: Int, in order: [URL], extendingSelection: Bool = false) {
        guard !order.isEmpty else { return }
        let current: Int
        if let anchorID, let index = order.firstIndex(of: anchorID) {
            current = index
        } else if let first = order.firstIndex(where: selectedIDs.contains) {
            current = first
        } else {
            current = delta >= 0 ? -1 : order.count
        }
        let next = min(max(current + delta, 0), order.count - 1)
        let id = order[next]
        if extendingSelection {
            applyRange(to: id, adding: true, in: order)
        } else {
            selectedIDs = [id]
            anchorID = id
        }
    }
}
