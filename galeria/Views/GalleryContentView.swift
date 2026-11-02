import AppKit
import SwiftUI

struct GalleryContentView: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.folderStore.folderURL != nil {
                GalleryBrowserBar()
            }
            if !model.selection.isEmpty {
                SelectionActionBar()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.folderStore.folderURL != nil {
                StatusBarView()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $model.infoItem) { item in
            ImageInfoSheet(item: item)
        }
        .sheet(isPresented: $model.showRenameSheet) {
            BatchRenameView(items: model.renameTargets)
                .environment(model)
        }
        .sheet(isPresented: $model.showExportSheet) {
            ExportSheet(items: model.exportTargets)
                .environment(model)
        }
        .sheet(isPresented: $model.showDuplicateFinder) {
            DuplicateFinderView()
                .environment(model)
        }
        .sheet(isPresented: $model.showMapView) {
            PhotoMapView()
                .environment(model)
        }
        .animation(.easeOut(duration: 0.16), value: model.selection.isEmpty)
        .onChange(of: model.sortFilter.filter) { _, _ in
            model.reconcileSelectionWithVisibleItems()
        }
        .navigationTitle(model.folderDisplayName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    model.openFolderPanel()
                } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                }
                .help("Open Folder (⌘O)")
                .keyboardShortcut("o", modifiers: .command)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                DensityToolbarItem()
                    .padding(.leading, 8)
                    .disabled(model.folderStore.folderURL == nil)
                Button {
                    model.usesOriginalAspect.toggle()
                } label: {
                    Label("Original Aspect Ratio", systemImage: "aspectratio")
                }
                .help("Show Original Aspect Ratio")
                .disabled(model.folderStore.folderURL == nil)
                .buttonStyle(.borderless)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(model.usesOriginalAspect ? Color.accentColor.opacity(0.16) : .clear)
                )
                .accessibilityValue(model.usesOriginalAspect ? "On" : "Off")

                Button {
                    model.selection.setSelectMode(!model.selection.selectMode)
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                .help("Selection Mode")
                .disabled(model.folderStore.folderURL == nil)
                .buttonStyle(.borderless)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(model.selection.selectMode ? Color.accentColor.opacity(0.16) : .clear)
                )
                .accessibilityValue(model.selection.selectMode ? "On" : "Off")
                .padding(.trailing, 8)

                SortMenu()
                    .disabled(model.folderStore.folderURL == nil)

                if model.canCompareSelection {
                    Button {
                        model.openCompare()
                    } label: {
                        Label("Compare", systemImage: "rectangle.split.2x1")
                    }
                    .help("Compare Selected Images Side by Side")
                }

                Button {
                    model.startCullMode()
                } label: {
                    Label("Cull", systemImage: "checklist")
                }
                .help("Cull Images")
                .disabled(model.folderStore.items.isEmpty)

                if !model.geotaggedItems.isEmpty {
                    Button {
                        model.showMapView = true
                    } label: {
                        Label("Map", systemImage: "map")
                    }
                    .help("Show Photo Map")
                }

                Button {
                    model.toggleFavoriteCurrentFolder()
                } label: {
                    Label(model.isCurrentFolderFavorite ? "Unpin Folder" : "Pin Folder",
                          systemImage: model.isCurrentFolderFavorite ? "star.fill" : "star")
                }
                .help(model.isCurrentFolderFavorite ? "Remove from Favorites" : "Add to Favorites")
                .disabled(model.folderStore.folderURL == nil)

                if model.folderStore.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .help("Loading images")
                }
            }
        }
        .toolbarRole(.editor)
    }

    @ViewBuilder
    private var content: some View {
        if model.folderStore.folderURL == nil {
            WelcomeView()
        } else if let error = model.folderStore.error, model.folderStore.items.isEmpty {
            FolderErrorView(error: error)
        } else if model.folderStore.items.isEmpty && model.folderStore.isScanning {
            LoadingFolderView()
        } else if model.folderStore.items.isEmpty {
            EmptyFolderView()
        } else if model.filteredItemCount == 0 {
            NoResultsView()
        } else {
            GalleryGridView(
                model: model,
                sections: model.sections,
                selectedIDs: model.selection.selectedIDs,
                selectMode: model.selection.selectMode,
                columns: model.density,
                usesOriginalAspect: model.usesOriginalAspect,
                showsMetadata: model.showMetadataOverlays,
                showsSectionHeaders: model.sections.contains { $0.title != nil }
            )
            .accessibilityIdentifier("gallery.grid")
            .overlay(alignment: .top) {
                if let error = model.folderStore.error {
                    InlineFolderErrorBanner(error: error)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var subtitle: String {
        guard model.folderStore.folderURL != nil else { return "" }
        let count = model.filteredItemCount
        return "\(count) \(count == 1 ? "image" : "images")"
    }
}

private struct DensityToolbarItem: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: Binding(
                get: { Double(model.density) },
                set: { model.setDensity(Int($0.rounded())) }
            ), in: 1...10, step: 1) {
                Text("Density")
            }
            .labelsHidden()
            .frame(width: 104)
            .help("Grid density: \(model.density) columns. Pinch on the grid to change.")
            Text("\(model.density)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
                .accessibilityLabel("\(model.density) columns")
        }
        .controlSize(.small)
    }
}

private struct SortMenu: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        Menu {
            Picker("Sort By", selection: Binding(
                get: { model.sortFilter.sortKey },
                set: { model.sortFilter.sortKey = $0 }
            )) {
                ForEach(GallerySortKey.allCases) { key in
                    Text(key.displayName).tag(key)
                }
            }
            .pickerStyle(.inline)

            Picker("Order", selection: Binding(
                get: { model.sortFilter.direction },
                set: { model.sortFilter.direction = $0 }
            )) {
                ForEach(SortDirection.allCases, id: \.self) { direction in
                    Label(direction.displayName, systemImage: direction.systemImage).tag(direction)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("Group By", selection: Binding(
                get: { model.sortFilter.grouping },
                set: { model.sortFilter.grouping = $0 }
            )) {
                ForEach(GalleryGrouping.allCases) { grouping in
                    Text(grouping.displayName).tag(grouping)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort and Group")
        .disabled(model.folderStore.items.isEmpty)
    }
}

private struct WelcomeView: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Browse a Folder of Images", systemImage: "photo.stack")
        } description: {
            Text("Choose a folder, or drop one onto this window. Galeria brings Finder's images into a fast, keyboard-driven grid.")
        } actions: {
            Button("Open Folder…") {
                model.openFolderPanel()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            Text("⌘O to open · Drag a folder here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .accessibilityIdentifier("empty.welcome")
    }
}

private struct EmptyFolderView: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No Images Here", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("This folder contains no supported images. Drag images here to add them, or choose another folder.")
        } actions: {
            HStack {
                Button("Open Another Folder…") {
                    model.openFolderPanel()
                }
                if let url = model.folderStore.folderURL {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
        .accessibilityIdentifier("empty.folder")
    }
}

private struct LoadingFolderView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Reading Folder…")
                .font(.headline)
            Text("Thumbnails load as you scroll.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("loading.folder")
    }
}

private struct NoResultsView: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No Matching Images", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(model.activeFilterChips.isEmpty
                 ? "No images match the current view."
                 : "Active filters: \(model.activeFilterChips.joined(separator: " · "))")
        } actions: {
            Button("Clear Filters") {
                model.clearFilters()
            }
            .disabled(!model.sortFilter.filter.isActive)
        }
        .accessibilityIdentifier("empty.results")
    }
}

private struct FolderErrorView: View {
    @Environment(GalleryModel.self) private var model
    let error: GalleryError

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
        } actions: {
            HStack {
                switch error.recovery {
                case .retry:
                    Button("Try Again") { Task { await model.retryFolder() } }
                case .chooseFolder, .none:
                    Button("Choose Folder…") { model.chooseAnotherFolder() }
                }
                if let url = model.folderStore.folderURL {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
        .accessibilityIdentifier("error.folder")
    }
}

private struct InlineFolderErrorBanner: View {
    @Environment(GalleryModel.self) private var model
    let error: GalleryError

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(.callout.weight(.semibold))
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if error.recovery == .retry {
                Button("Try Again") { Task { await model.retryFolder() } }
                    .controlSize(.small)
            } else {
                Button("Choose Folder…") { model.chooseAnotherFolder() }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}
