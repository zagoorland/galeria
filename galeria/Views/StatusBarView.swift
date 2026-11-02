import AppKit
import SwiftUI

struct StatusBarView: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Text(itemCountText)
                .monospacedDigit()
            if model.selection.count > 0 {
                Text("·").foregroundStyle(.tertiary)
                Text(selectionText)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            if model.isIndexing {
                ProgressView(value: model.smartIndexProgress)
                    .frame(width: 54)
                    .controlSize(.mini)
                    .help("Indexing image content")
                Text("Indexing…")
                    .foregroundStyle(.secondary)
            }
            if model.folderStore.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .help("Updating folder")
                Text("Updating…")
                    .foregroundStyle(.secondary)
            }
            PathMenu()
                .frame(maxWidth: 380, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator.opacity(0.7))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var itemCountText: String {
        let count = model.filteredItemCount
        let total = model.folderStore.items.count
        if count == total {
            return "\(count) \(count == 1 ? "image" : "images")"
        }
        return "\(count) of \(total) images"
    }

    private var selectionText: String {
        let count = model.selection.count
        let size = ByteCountFormatter.string(fromByteCount: model.selectedTotalSize, countStyle: .file)
        return "\(count) selected · \(size)"
    }
}

private struct PathMenu: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        Menu {
            Button {
                model.openParentFolder()
            } label: {
                Label("Enclosing Folder", systemImage: "arrow.up")
            }
            .disabled(model.folderStore.folderURL?.path == "/")
            Divider()
            if let url = model.folderStore.folderURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal in Finder", systemImage: "finder")
                }
                Divider()
                Text(url.path)
            }
        } label: {
            Label(homeAbbreviatedPath, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .help(model.currentFolderPath)
        .accessibilityLabel("Current folder path")
    }

    private var homeAbbreviatedPath: String {
        let path = model.currentFolderPath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
