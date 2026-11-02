import SwiftUI

struct SubfolderTreeView: View {
    @Environment(GalleryModel.self) private var model
    let root: URL
    @ObservedObject var tree: SubfolderTreeModel

    var body: some View {
        Group {
            if tree.isLoading && tree.topLevel.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading Subfolders…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if tree.topLevel.isEmpty {
                Text("No Subfolders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tree.topLevel) { child in
                    SidebarSubfolderRow(subfolder: child, level: 0, tree: tree)
                }
            }
        }
        .task(id: root) {
            await tree.loadTop(root: root, loader: model.subfolderLoader)
        }
    }
}

private struct SidebarSubfolderRow: View {
    @Environment(GalleryModel.self) private var model
    let subfolder: SidebarSubfolder
    let level: Int
    @ObservedObject var tree: SubfolderTreeModel

    @State private var expanded = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    expanded.toggle()
                    if expanded, tree.children(for: subfolder.url) == nil {
                        Task { await tree.loadChildren(parent: subfolder.url, loader: model.subfolderLoader) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(expanded ? "Collapse Folder" : "Expand Folder")

                Button {
                    Task { await model.openFolder(subfolder.url) }
                } label: {
                    Label(subfolder.name, systemImage: isDropTargeted ? "arrow.down.doc" : "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help(subfolder.url.path)

                Spacer(minLength: 0)
                if expanded, tree.loadingParents.contains(subfolder.url) {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.leading, CGFloat(level) * 12)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isDropTargeted ? Color.accentColor.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())

            if expanded, let children = tree.children(for: subfolder.url) {
                if children.isEmpty {
                    Text("No Subfolders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, CGFloat(level + 1) * 12 + 24)
                } else {
                    ForEach(children) { child in
                        SidebarSubfolderRow(subfolder: child, level: level + 1, tree: tree)
                            .transition(.opacity)
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard model.folderStore.folderURL != nil else { return false }
            Task { await model.moveDroppedURLs(urls, to: subfolder.url) }
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .accessibilityElement(children: .contain)
    }
}
