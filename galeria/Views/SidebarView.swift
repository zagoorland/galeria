import SwiftUI

struct SidebarView: View {
    @Environment(GalleryModel.self) private var model
    @StateObject private var subfolderTree = SubfolderTreeModel()
    @State private var showSubfolders = false

    var body: some View {
        List {
            Section {
                Button {
                    model.openFolderPanel()
                } label: {
                    Label("Open Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
            }

            Section("Current Folder") {
                if let folder = model.folderStore.folderURL {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(model.folderDisplayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 2)
                        if model.isCurrentFolderFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Pinned")
                        }
                    }
                    .help(folder.path)
                    .accessibilityElement(children: .combine)
                } else {
                    Text("No Folder Open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Favorites") {
                if model.favoriteRecords.isEmpty {
                    Text("Pin a folder with the star in the toolbar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                } else {
                    ForEach(model.favoriteRecords) { record in
                        SidebarFolderButton(record: record)
                    }
                }
            }

            Section("Recents") {
                if model.recentRecords.isEmpty {
                    Text("Recently opened folders appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.recentRecords.prefix(6)) { record in
                        SidebarFolderButton(record: record)
                    }
                }
            }

            Section("Browse") {
                DisclosureGroup(isExpanded: $showSubfolders) {
                    if let folder = model.folderStore.folderURL {
                        SubfolderTreeView(root: folder, tree: subfolderTree)
                            .padding(.top, 2)
                    } else {
                        Text("Open a folder to browse subfolders.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Subfolders", systemImage: "folder")
                        .foregroundStyle(model.folderStore.folderURL == nil ? .secondary : .primary)
                }
                .disabled(model.folderStore.folderURL == nil)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Galeria")
    }
}

private struct SidebarFolderButton: View {
    @Environment(GalleryModel.self) private var model
    let record: BookmarkRecord
    @State private var isDropTargeted = false

    var body: some View {
        Button {
            model.openBookmarkRecord(record)
        } label: {
            Label {
                Text(record.name.isEmpty ? URL(fileURLWithPath: record.path).lastPathComponent : record.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: isDropTargeted ? "arrow.down.doc" : "folder")
            }
        }
        .buttonStyle(.plain)
        .help(record.path)
        .accessibilityLabel("Open folder \(record.name)")
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isDropTargeted ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .dropDestination(for: URL.self) { urls, _ in
            guard model.folderStore.folderURL != nil else { return false }
            Task { await model.moveDroppedURLs(urls, to: record) }
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }
}
