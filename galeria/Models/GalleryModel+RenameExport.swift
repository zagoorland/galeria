import AppKit
import Foundation

extension GalleryModel {
    func presentBatchRename() {
        let items = selectedItems
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        renameTargets = items
        showRenameSheet = true
    }

    func existingFilePaths() -> Set<String> {
        guard let folder = folderStore.folderURL else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(contents.map { folder.appendingPathComponent($0).path.lowercased() })
    }

    @discardableResult
    func performBatchRename(_ plan: RenamePlan) async -> Bool {
        guard plan.canApply else { return false }
        do {
            try await batchRenamer.apply(plan.effectiveChanges)
            await folderStore.refresh()
            let newURLs = Set(plan.effectiveChanges.map(\.renamedURL))
            let available = newURLs.intersection(folderStore.availableURLs)
            selection.setSelection(available, anchor: plan.effectiveChanges.first?.renamedURL)
            undoJournal.record(makeRenameRestoreEntry(changes: plan.effectiveChanges, name: "Rename \(plan.effectiveChanges.count) Images"))
            return true
        } catch {
            presentedError = GalleryError(title: "Rename Failed", message: error.localizedDescription)
            return false
        }
    }

    private func makeRenameRestoreEntry(changes: [RenameChange], name: String) -> UndoJournal.Entry {
        UndoJournal.Entry(name: name) { [weak self] in
            guard let self else { return nil }
            let inverse = changes.map { RenameChange(originalURL: $0.renamedURL, renamedURL: $0.originalURL) }
            try await self.batchRenamer.apply(inverse)
            await self.folderStore.refresh()
            let restored = Set(inverse.map(\.renamedURL)).intersection(self.folderStore.availableURLs)
            self.selection.setSelection(restored, anchor: inverse.first?.renamedURL)
            return self.makeRenameForwardEntry(changes: changes, name: name)
        }
    }

    private func makeRenameForwardEntry(changes: [RenameChange], name: String) -> UndoJournal.Entry {
        UndoJournal.Entry(name: name) { [weak self] in
            guard let self else { return nil }
            try await self.batchRenamer.apply(changes)
            await self.folderStore.refresh()
            let renamed = Set(changes.map(\.renamedURL)).intersection(self.folderStore.availableURLs)
            self.selection.setSelection(renamed, anchor: changes.first?.renamedURL)
            return self.makeRenameRestoreEntry(changes: changes, name: name)
        }
    }
}

extension GalleryModel {
    func presentExport() {
        let items = selectedItems
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        exportTargets = items
        showExportSheet = true
    }
}
