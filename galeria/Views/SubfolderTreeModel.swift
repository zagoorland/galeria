import Combine
import Foundation

/// Sidebar tree loading state lives above the List so structural updates do not
/// cancel and restart subfolder discovery.
@MainActor
final class SubfolderTreeModel: ObservableObject {
    @Published private(set) var topLevel: [SidebarSubfolder] = []
    @Published private(set) var childrenByParent: [URL: [SidebarSubfolder]] = [:]
    @Published private(set) var loadingParents: Set<URL> = []
    @Published private(set) var isLoading = false
    private var loadedRoot: URL?
    private var hasLoadedTop = false

    func loadTop(root: URL, loader: SubfolderLoader) async {
        if loadedRoot == root, hasLoadedTop { return }
        if isLoading, loadedRoot == root { return }
        loadedRoot = root
        isLoading = true
        let result = await loader.subfolders(of: root)
        guard loadedRoot == root else { return }
        topLevel = result
        hasLoadedTop = true
        isLoading = false
    }

    func loadChildren(parent: URL, loader: SubfolderLoader) async {
        if childrenByParent[parent] != nil || loadingParents.contains(parent) { return }
        loadingParents.insert(parent)
        let result = await loader.subfolders(of: parent)
        childrenByParent[parent] = result
        loadingParents.remove(parent)
    }

    func children(for parent: URL) -> [SidebarSubfolder]? {
        childrenByParent[parent]
    }
}
