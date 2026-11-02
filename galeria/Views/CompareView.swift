import SwiftUI

struct CompareView: View {
    @Environment(GalleryModel.self) private var model
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseZoom: CGFloat = 1
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    model.closeCompare()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Compare")
                        .font(.headline)
                    Text("\(model.compareItems.count) images · synchronized zoom and pan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    zoom = max(0.5, zoom - 0.2)
                    baseZoom = zoom
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Zoom Out")

                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.callout.monospacedDigit())
                    .frame(width: 52)

                Button {
                    zoom = min(8, zoom + 0.2)
                    baseZoom = zoom
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Zoom In")

                Button {
                    resetTransform()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset Zoom and Pan")
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.bar)

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(model.compareItems) { item in
                        ComparePane(item: item, zoom: zoom, offset: offset)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(max(baseZoom * value.magnification, 0.5), 8)
                        }
                        .onEnded { _ in baseZoom = zoom }
                        .simultaneously(with:
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(width: baseOffset.width + value.translation.width,
                                                    height: baseOffset.height + value.translation.height)
                                }
                                .onEnded { _ in baseOffset = offset }
                        )
                )
                .onTapGesture(count: 2, perform: resetTransform)
            }
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("compare.overlay")
    }

    private func resetTransform() {
        zoom = 1
        offset = .zero
        baseZoom = 1
        baseOffset = .zero
    }
}

private struct ComparePane: View {
    @Environment(GalleryModel.self) private var model
    let item: ImageItem
    let zoom: CGFloat
    let offset: CGSize
    @State private var payload: PreviewImagePayload?

    var body: some View {
        ZStack {
            Color.black
            if let payload {
                GeometryReader { geometry in
                    Image(nsImage: payload.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(zoom)
                        .offset(offset)
                        .clipped()
                }
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.rating > 0 {
                        Text(String(repeating: "★", count: item.rating))
                            .foregroundStyle(.yellow)
                    }
                    Spacer(minLength: 0)
                    Text(item.dimensionsDescription)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.black.opacity(0.58))
            }
        }
        .clipped()
        .task(id: "\(item.url.path)|\(item.modifiedAt.timeIntervalSince1970)") {
            payload = await model.previewImageService.image(for: item)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.dimensionsDescription)")
    }
}
