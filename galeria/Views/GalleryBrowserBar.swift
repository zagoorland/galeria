import SwiftUI

struct GalleryBrowserBar: View {
    @Environment(GalleryModel.self) private var model
    @FocusState private var searchFocused: Bool
    @State private var showingFilters = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BreadcrumbView(folder: model.folderStore.folderURL)
                    .frame(maxWidth: .infinity, alignment: .leading)

                searchField

                Button {
                    showingFilters.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 14))
                            .frame(width: 26, height: 24)
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.system(size: 8, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Color(nsColor: .alternateSelectedControlTextColor))
                                .frame(minWidth: 13, minHeight: 13)
                                .background(Color.accentColor, in: Circle())
                                .offset(x: 3, y: -3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Filter Images (⇧⌘L)")
                .accessibilityLabel("Filter Images")
                .accessibilityValue(activeFilterCount == 0 ? "No filters" : "\(activeFilterCount) filters active")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)

            if model.sortFilter.filter.isActive {
                activeFilterChips
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.separator.opacity(0.7)).frame(height: 1)
        }
        .animation(.easeOut(duration: 0.15), value: model.sortFilter.filter.isActive)
        .onReceive(NotificationCenter.default.publisher(for: .galeriaFocusSearch)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .galeriaShowFilters)) { _ in
            showingFilters = true
        }
        .popover(isPresented: $showingFilters, arrowEdge: .bottom) {
            FiltersPopover()
                .environment(model)
        }
    }

    private var activeFilterCount: Int {
        model.sortFilter.filter.activeChips.count
    }

    private var searchBinding: Binding<String> {
        Binding(get: { model.sortFilter.filter.searchText },
                set: { model.sortFilter.filter.searchText = $0 })
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search Images", text: searchBinding)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($searchFocused)
                .accessibilityLabel("Search Images")
            if !model.sortFilter.filter.searchText.isEmpty {
                Button {
                    model.sortFilter.filter.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 190, height: 24)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(searchFocused ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5),
                              lineWidth: searchFocused ? 2 : 1)
        }
        .onTapGesture { searchFocused = true }
    }

    private var activeFilterChips: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(Array(model.activeFilterChips.prefix(3).enumerated()), id: \.offset) { _, chip in
                Text(chip)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
            if model.activeFilterChips.count > 3 {
                Text("+\(model.activeFilterChips.count - 3)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Clear All") {
                model.clearFilters()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(.tint)
            .help("Clear All Filters")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
    }
}

private struct BreadcrumbView: View {
    @Environment(GalleryModel.self) private var model
    let folder: URL?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let folder {
                let components = pathComponents(for: folder)
                if components.count > 3 {
                    Menu {
                        ForEach(components.dropLast(3)) { component in
                            Button(component.name) {
                                Task { await model.openFolder(component.url) }
                            }
                        }
                    } label: {
                        Text("…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                ForEach(Array(components.suffix(3))) { component in
                    if component.url != components.suffix(3).first?.url {
                        Image(systemName: "chevron.compact.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(component.name) {
                        Task { await model.openFolder(component.url) }
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(component.url.path)
                    .accessibilityLabel("Open \(component.name)")
                }
            } else {
                Text("No Folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Folder path")
    }

    private func pathComponents(for url: URL) -> [PathComponent] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let components: [PathComponent]
        if url.standardizedFileURL.path.hasPrefix(home.standardizedFileURL.path) {
            let relative = String(url.standardizedFileURL.path.dropFirst(home.path.count))
            var current = home
            var result: [PathComponent] = [PathComponent(name: "~", url: home)]
            for part in relative.split(separator: "/") where !part.isEmpty {
                current.appendPathComponent(String(part))
                result.append(PathComponent(name: String(part), url: current))
            }
            components = result
        } else {
            var current = URL(fileURLWithPath: "/")
            var result: [PathComponent] = [PathComponent(name: "/", url: current)]
            for part in url.pathComponents where part != "/" {
                current.appendPathComponent(part)
                result.append(PathComponent(name: part, url: current))
            }
            components = result
        }
        return components.enumerated().map { PathComponent(id: "\($0.offset)-\($0.element.url.path)",
                                                           name: $0.element.name,
                                                           url: $0.element.url) }
    }
}

private struct PathComponent: Identifiable, Hashable {
    var id: String
    let name: String
    let url: URL

    init(name: String, url: URL) {
        self.id = url.path
        self.name = name
        self.url = url
    }

    init(id: String, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }
}
