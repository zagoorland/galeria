import AppKit
import SwiftUI

struct PreviewView: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let item = model.previewCurrentItem {
                PreviewTopBar(item: item)
                    .zIndex(2)
                HStack(spacing: 0) {
                    ZStack {
                        PreviewImageHost(item: item)
                        PreviewNavigationArrows(item: item)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    if model.previewInfoVisible {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1)
                        PreviewInfoPanel(item: item)
                            .frame(width: 324)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                if model.previewShowFilmstrip {
                    FilmstripView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(2)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Opening Preview…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.18), value: model.previewInfoVisible)
        .animation(.easeInOut(duration: 0.18), value: model.previewShowFilmstrip)
        .onExitCommand {
            model.closePreview()
        }
        .accessibilityIdentifier("preview.overlay")
    }
}

private struct PreviewTopBar: View {
    @Environment(GalleryModel.self) private var model
    let item: ImageItem

    var body: some View {
        HStack(spacing: 7) {
            Button {
                model.closePreview()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Close Preview (Esc)")
            .accessibilityLabel("Close Preview")

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\((model.previewIndex ?? 0) + 1) of \(max(model.previewItems.count, 1))")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .monospacedDigit()
            }
            .frame(maxWidth: 250, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                zoomButton("minus.magnifyingglass") { model.zoomPreview(by: 0.8) }
                    .help("Zoom Out (−)")
                Menu {
                    Button("Fit to Window") { model.setPreviewFit() }
                    Button("Actual Size (100%)") { model.setPreviewActualSize() }
                    Divider()
                    Button("Zoom In") { model.zoomPreview(by: 1.25) }
                    Button("Zoom Out") { model.zoomPreview(by: 0.8) }
                } label: {
                    Text(model.previewIsFit ? "Fit · \(model.previewZoomPercent)%" : "\(model.previewZoomPercent)%")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 56)
                        .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Zoom Level")
                zoomButton("plus.magnifyingglass") { model.zoomPreview(by: 1.25) }
                    .help("Zoom In (+)")
            }
            .padding(.horizontal, 4)
            .frame(height: 28)
            .background(Color.white.opacity(0.08), in: Capsule())

            topButton("rectangle.bottomthird.inset.filled", help: model.previewShowFilmstrip ? "Hide Filmstrip" : "Show Filmstrip") {
                model.togglePreviewFilmstrip()
            }
            .opacity(model.previewShowFilmstrip ? 1 : 0.65)

            topButton("info.circle", help: "Photo Info (⌘I)") {
                model.togglePreviewInfo()
            }
            .opacity(model.previewInfoVisible ? 1 : 0.65)

            topButton("text.viewfinder", help: "Live Text") {
                model.togglePreviewLiveText()
            }
            .opacity(model.previewLiveTextEnabled ? 1 : 0.65)

            topButton("square.and.arrow.up", help: "Share") {
                model.shareSelection()
            }

            Menu {
                Menu("Rotate") {
                    Button("Rotate Left") { Task { await model.rotateSelection(.left) } }
                    Button("Rotate Right") { Task { await model.rotateSelection(.right) } }
                }
                Menu("Rating") {
                    ForEach(0...5, id: \.self) { rating in
                        Button(rating == 0 ? "No Rating" : "\(rating) \(rating == 1 ? "Star" : "Stars")") {
                            Task { await model.setRating(rating) }
                        }
                    }
                }
                Menu("Label") {
                    Button("None") { Task { await model.setLabel(nil) } }
                    ForEach(FinderColorLabel.allCases) { label in
                        Button(label.displayName) { Task { await model.setLabel(label) } }
                    }
                }
                Divider()
                Button("Reveal in Finder") { model.revealSelection() }
                Button("Copy Image") { model.copySelectionAsImage() }
                Button("Copy File") { model.copySelectionFiles() }
                Button("Start Slideshow") { model.startSlideshow() }
                Button("Cull Images") { model.startCullMode() }
                if model.canCompareSelection {
                    Button("Compare Selected") { model.openCompare() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(.white)
            .help("More Preview Actions")
            .accessibilityLabel("More Preview Actions")

            Button {
                Task { await model.trashSelection() }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Move to Trash (Delete)")
            .accessibilityLabel("Move to Trash")
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color.black.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
        .buttonStyle(.plain)
    }

    private func topButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help(help)
        .accessibilityLabel(help)
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

struct PreviewImageHost: View {
    @Environment(GalleryModel.self) private var model
    let item: ImageItem
    @State private var payloads: [String: PreviewImagePayload] = [:]
    @State private var failedIdentities: Set<String> = []

    var body: some View {
        let identity = Self.identity(for: item)
        let payload = payloads[identity]
        let loadError = payload == nil && failedIdentities.contains(identity)

        ZStack {
            Color.black
            if let payload {
                GeometryReader { geometry in
                    let fit = Self.fitScale(imageSize: payload.image.size, in: geometry.size)
                    PreviewCanvas(
                        image: payload.image,
                        identity: identity,
                        fileName: item.name,
                        isAnimated: payload.isAnimated,
                        fileURL: item.url,
                        previousImage: neighborPayload(offset: -1)?.image,
                        nextImage: neighborPayload(offset: 1)?.image,
                        fitScale: fit,
                        isFitMode: Binding(get: { model.previewIsFit },
                                           set: { model.previewIsFit = $0 }),
                        absoluteScale: Binding(get: { model.previewZoomScale },
                                               set: { model.previewZoomScale = $0 }),
                        liveTextEnabled: model.previewLiveTextEnabled,
                        onDragOperation: { operation in
                            model.refreshAfterDrag(operation: operation)
                        },
                        onSwipe: { action in
                            switch action {
                            case .previous:
                                model.navigatePreview(by: -1)
                            case .next:
                                model.navigatePreview(by: 1)
                            case .close:
                                model.closePreview()
                            }
                        }
                    )
                    .onAppear { model.updatePreviewFitScale(fit) }
                    .onChange(of: fit) { _, newValue in model.updatePreviewFitScale(newValue) }
                }
                .padding(10)
            }

            if payload == nil && !loadError {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .padding(14)
                    .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if loadError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30, weight: .light))
                    Text("Could Not Open Image")
                        .font(.headline)
                    Text("The file may be unreadable or its format is not supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    .buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
            }
        }
        .task(id: identity) {
            await loadCurrent(item, identity: identity)
        }
        .task(id: "\(identity)|neighbors") {
            await loadNeighbors(around: item)
        }
        .accessibilityElement(children: .contain)
        .clipped()
    }

    private func loadCurrent(_ item: ImageItem, identity: String) async {
        prunePayloads(around: item)
        failedIdentities.remove(identity)
        guard payloads[identity] == nil else { return }
        let loaded = await model.previewImageService.image(for: item)
        guard !Task.isCancelled else { return }
        if let loaded {
            payloads[identity] = loaded
            model.preloadPreviewNeighbors()
        } else {
            failedIdentities.insert(identity)
        }
    }

    /// Keep the immediate neighbors ready so a paging gesture has real images
    /// to reveal instead of a blank page.
    private func loadNeighbors(around item: ImageItem) async {
        guard let index = model.previewItems.firstIndex(where: { $0.url == item.url }) else { return }
        let allowed = identitiesAround(item)
        for offset in [-2, -1, 1, 2] {
            let neighborIndex = index + offset
            guard neighborIndex >= 0, neighborIndex < model.previewItems.count else { continue }
            let neighbor = model.previewItems[neighborIndex]
            let neighborIdentity = Self.identity(for: neighbor)
            guard allowed.contains(neighborIdentity), payloads[neighborIdentity] == nil else { continue }
            if let loaded = await model.previewImageService.image(for: neighbor) {
                guard !Task.isCancelled, identitiesAround(item).contains(neighborIdentity) else { return }
                payloads[neighborIdentity] = loaded
            }
        }
    }

    private func prunePayloads(around item: ImageItem) {
        let allowed = identitiesAround(item)
        payloads = payloads.filter { allowed.contains($0.key) }
        failedIdentities = failedIdentities.intersection(allowed)
    }

    private func identitiesAround(_ item: ImageItem) -> Set<String> {
        guard let index = model.previewItems.firstIndex(where: { $0.url == item.url }) else {
            return [Self.identity(for: item)]
        }
        let lower = max(0, index - 2)
        let upper = min(model.previewItems.count - 1, index + 2)
        guard lower <= upper else { return [Self.identity(for: item)] }
        return Set(model.previewItems[lower...upper].map(Self.identity(for:)))
    }

    private func neighborPayload(offset: Int) -> PreviewImagePayload? {
        guard let index = model.previewItems.firstIndex(where: { $0.url == item.url }) else { return nil }
        let neighborIndex = index + offset
        guard neighborIndex >= 0, neighborIndex < model.previewItems.count else { return nil }
        return payloads[Self.identity(for: model.previewItems[neighborIndex])]
    }

    nonisolated private static func identity(for item: ImageItem) -> String {
        "\(item.url.path)|\(item.modifiedAt.timeIntervalSince1970)"
    }

    private static func fitScale(imageSize: NSSize, in available: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              available.width > 0, available.height > 0 else { return 1 }
        return min(available.width / imageSize.width, available.height / imageSize.height)
    }
}

private struct PreviewNavigationArrows: View {
    @Environment(GalleryModel.self) private var model
    let item: ImageItem

    var body: some View {
        HStack {
            navButton("chevron.left", disabled: (model.previewIndex ?? 0) <= 0) {
                model.navigatePreview(by: -1)
            }
            Spacer()
            navButton("chevron.right", disabled: (model.previewIndex ?? 0) >= model.previewItems.count - 1) {
                model.navigatePreview(by: 1)
            }
        }
        .padding(.horizontal, 16)
        .opacity(model.previewInfoVisible ? 0.82 : 1)
    }

    private func navButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.46), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.25 : 1)
        .help(symbol == "chevron.left" ? "Previous Image (←)" : "Next Image (→)")
        .accessibilityLabel(symbol == "chevron.left" ? "Previous Image" : "Next Image")
    }
}

private struct FilmstripView: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(model.previewItems) { item in
                        FilmstripCell(item: item, selected: item.url == model.previewURL)
                            .id(item.url)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .environment(\.horizontalScrollIndicatorVisibility, .never)
            .frame(height: 78)
            .background(Color.black.opacity(0.82))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            }
            .onAppear {
                if let url = model.previewURL {
                    proxy.scrollTo(url, anchor: .center)
                }
            }
            .onChange(of: model.previewURL) { _, url in
                guard let url else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(url, anchor: .center)
                }
            }
        }
    }
}

private struct FilmstripCell: View {
    @Environment(GalleryModel.self) private var model
    let item: ImageItem
    let selected: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.white.opacity(0.08))
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 60, height: 60)
        .clipped()
        .overlay {
            Rectangle()
                .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.12),
                              lineWidth: selected ? 2.5 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.jumpPreview(to: item.url)
        }
        .help(item.name)
        .accessibilityLabel("\(item.name), image \(item.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: "\(item.url.path)|\(item.modifiedAt.timeIntervalSince1970)") {
            image = await model.thumbnailService.thumbnail(for: item, maxPixel: 256)
        }
        .id(item.url)
    }
}
