import Combine
import Foundation
import SwiftUI

/// SwiftUI Commands do not observe @Observable models. The app observes this
/// small ObservableObject and rebuilds its menus from the published snapshot.
@MainActor
final class MenuState: ObservableObject {
    struct Snapshot: Equatable {
        var hasFolder = false
        var hasImages = false
        var selectionCount = 0
        var canCompare = false
        var canUndo = false
        var undoTitle: String?
        var canRedo = false
        var redoTitle: String?
        var hasPreview = false
        var previewInfoVisible = false
        var filmstripVisible = true
        var liveTextEnabled = false
        var isSlideshow = false
        var hasGPS = false
        var isCulling = false
        var canRename = false
        var includeSubfolders = false

        var hasSelection: Bool { selectionCount > 0 }

        init() {}

        @MainActor
        init(model: GalleryModel) {
            hasFolder = model.folderStore.folderURL != nil
            hasImages = !model.folderStore.items.isEmpty
            selectionCount = model.selection.count
            canCompare = (2...4).contains(model.selection.count)
            canUndo = model.undoJournal.canUndo
            undoTitle = model.undoJournal.undoTitle
            canRedo = model.undoJournal.canRedo
            redoTitle = model.undoJournal.redoTitle
            hasPreview = model.previewURL != nil
            previewInfoVisible = model.previewInfoVisible
            filmstripVisible = model.previewShowFilmstrip
            liveTextEnabled = model.previewLiveTextEnabled
            isSlideshow = model.isSlideshowActive
            hasGPS = !model.geotaggedItems.isEmpty
            isCulling = model.isCullMode
            canRename = !model.selection.isEmpty
            includeSubfolders = model.includeSubfolders
        }
    }

    static let shared = MenuState()

    @Published private(set) var snapshot = Snapshot()

    private init() {}

    func apply(_ snapshot: Snapshot) {
        guard snapshot != self.snapshot else { return }
        self.snapshot = snapshot
    }
}
