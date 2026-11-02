import AppKit
import SwiftUI

struct GalleryCommands: Commands {
    let model: GalleryModel
    let state: MenuState.Snapshot

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") {
                model.openFolderPanel()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Enclosing Folder") {
                model.openParentFolder()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(!state.hasFolder)

            Divider()

            Button("Move Selected Images…") {
                model.chooseMoveDestination()
            }
            .disabled(!state.hasSelection)

            Button("Copy Selected Images…") {
                model.chooseCopyDestination()
            }
            .disabled(!state.hasSelection)
        }

        CommandGroup(replacing: .undoRedo) {
            Button(undoTitle) {
                performUndo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!state.canUndo)

            Button(redoTitle) {
                performRedo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!state.canRedo)
        }

        CommandGroup(after: .textEditing) {
            Button("Search Images") {
                model.focusSearchRequested()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!state.hasFolder)

            Button("Show Filters") {
                NotificationCenter.default.post(name: .galeriaShowFilters, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(!state.hasFolder)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Selection Mode") {
                model.selection.setSelectMode(!model.selection.selectMode)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Original Aspect Ratio") {
                model.usesOriginalAspect.toggle()
            }

            Toggle("Include Subfolders", isOn: Binding(
                get: { model.includeSubfolders },
                set: { newValue in
                    Task { await model.setIncludeSubfolders(newValue) }
                }
            ))

            Button("Show Ratings, Labels and Flags") {
                model.showMetadataOverlays.toggle()
            }

            Divider()

        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") {
                NotificationCenter.default.post(name: .galeriaShowShortcuts, object: nil)
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
        }

        CommandMenu("Image") {
            Button("Quick Preview") {
                if let url = model.selectedItems.first?.url ?? model.orderedItems.first?.url {
                    model.openPreview(for: url)
                }
            }
            .disabled(!state.hasImages)

            Button("Deselect All") {
                model.clearSelection()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!state.hasSelection)

            Button(state.hasPreview ? "Toggle Preview Info" : "Get Info") {
                if state.hasPreview {
                    model.togglePreviewInfo()
                } else if let url = model.selectedItems.first?.url {
                    model.showInfo(for: url)
                }
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(!state.hasSelection && !state.hasPreview)

            Button("Toggle Filmstrip") {
                model.togglePreviewFilmstrip()
            }
            .disabled(!state.hasPreview)

            Button("Toggle Live Text") {
                model.togglePreviewLiveText()
            }
            .disabled(!state.hasPreview)

            Divider()

            Button("Start Slideshow") {
                model.startSlideshow()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(!state.hasImages)

            Button("Compare Selected Images") {
                model.openCompare()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(!state.canCompare)

            Button("Cull Folder") {
                model.startCullMode()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(!state.hasImages)

            Button("Show Photo Map") {
                model.showMapView = true
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(!state.hasGPS)

            Divider()

            Button("Move to Trash") {
                guard !isEditingText else { return }
                Task { await model.trashSelection() }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!state.hasSelection)

            Button("Close Preview") {
                model.closePreview()
            }
            .disabled(!state.hasPreview)

            Button("Reveal in Finder") {
                model.revealSelection()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!state.hasSelection)

            Button("Share…") {
                model.shareSelection()
            }
            .disabled(!state.hasSelection)

            Button("Copy as Image") {
                model.copySelectionAsImage()
            }
            .disabled(!state.hasSelection)

            Divider()

            Button("Rotate Left") {
                Task { await model.rotateSelection(.left) }
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(!state.hasSelection)

            Button("Rotate Right") {
                Task { await model.rotateSelection(.right) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!state.hasSelection)

            Divider()

            Button("Batch Rename…") {
                model.presentBatchRename()
            }
            .disabled(!state.hasSelection)

            Button("Export Selected Images…") {
                model.presentExport()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!state.hasSelection)

            Button("Find Duplicates…") {
                model.presentDuplicateFinder()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(!state.hasImages)

            Menu("Rating") {
                ForEach(0...5, id: \.self) { rating in
                    Button(rating == 0 ? "No Rating" : "\(rating) \(rating == 1 ? "Star" : "Stars")") {
                        Task { await model.setRating(rating) }
                    }
                }
            }
            .disabled(!state.hasSelection)

            Menu("Flag") {
                Button("Pick") { Task { await model.setFlag(.pick) } }
                Button("Reject") { Task { await model.setFlag(.reject) } }
                Button("Clear Flag") { Task { await model.setFlag(.none) } }
            }
            .disabled(!state.hasSelection)

            Menu("Color Label") {
                Button("None") { Task { await model.setLabel(nil) } }
                ForEach(FinderColorLabel.allCases) { label in
                    Button(label.displayName) { Task { await model.setLabel(label) } }
                }
            }
            .disabled(!state.hasSelection)
        }
    }

    private var undoTitle: String {
        state.undoTitle.map { "Undo \($0)" } ?? "Undo"
    }

    private var redoTitle: String {
        state.redoTitle.map { "Redo \($0)" } ?? "Redo"
    }

    private var isEditingText: Bool {
        guard let window = NSApp.keyWindow else { return false }
        return GalleryModel.isTextEditing(in: window)
    }

    private func performUndo() {
        if isEditingText {
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.undo()
        } else {
            Task { await model.performUndo() }
        }
    }

    private func performRedo() {
        if isEditingText {
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.redo()
        } else {
            Task { await model.performRedo() }
        }
    }
}
