import SwiftUI

struct CullView: View {
    @Environment(GalleryModel.self) private var model
    @State private var isPaging = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let item = model.previewCurrentItem {
                HStack(spacing: 14) {
                    Button {
                        model.exitCullMode()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .help("Finish Culling (Esc)")
                    .accessibilityLabel("Finish Culling")

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cull Mode")
                            .font(.headline)
                        Text("P picks · X rejects · arrow keys navigate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(model.cullReviewedCount) of \(model.previewItems.count) reviewed")
                                .font(.callout.monospacedDigit())
                            if model.cullAllReviewed {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        ProgressView(value: Double(model.cullReviewedCount),
                                     total: Double(max(model.previewItems.count, 1)))
                            .progressViewStyle(.linear)
                            .frame(width: 170)
                    }

                    Button("Review Rejected (\(model.cullRejectedItems.count))") {
                        model.showRejectedReview = true
                    }
                    .disabled(model.cullRejectedItems.isEmpty)
                    .help("Review Images Marked Reject")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(Color.black.opacity(0.78))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
                }

                PreviewImageHost(item: item, isPaging: $isPaging)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(model.cullReviewedCount) reviewed · \(model.cullRejectedItems.count) rejected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.flag != .none {
                        Button("Clear Flag") {
                            Task { await model.clearCurrentCullFlag() }
                        }
                        .help("Clear Pick or Reject Flag")
                    }
                    Button {
                        Task { await model.markCullDecision(.pick) }
                    } label: {
                        Label("Keep", systemImage: "checkmark")
                    }
                    .tint(.green)
                    .help("Keep (P)")
                    Button {
                        Task { await model.markCullDecision(.reject) }
                    } label: {
                        Label("Reject", systemImage: "xmark")
                    }
                    .tint(.red)
                    .help("Reject (X)")
                    Button("Finish") {
                        model.exitCullMode()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 58)
                .background(Color.black.opacity(0.82))
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
                }
            } else {
                ContentUnavailableView("No Images to Cull", systemImage: "photo")
                    .foregroundStyle(.white)
            }
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $model.showRejectedReview) {
            RejectedReviewView()
                .environment(model)
        }
        .accessibilityIdentifier("cull.overlay")
    }
}

struct RejectedReviewView: View {
    @Environment(GalleryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isTrashing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rejected Images")
                        .font(.headline)
                    Text("\(model.cullRejectedItems.count) marked for removal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()

            if model.cullRejectedItems.isEmpty {
                ContentUnavailableView("No Rejected Images", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.cullRejectedItems) { item in
                            HStack(spacing: 10) {
                                RejectedThumbnail(item: item)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.callout)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(item.dimensionsDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Divider()
            HStack {
                Text("Trashing cannot be undone after the Trash is emptied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }
                Button("Move Rejected to Trash") {
                    guard !isTrashing else { return }
                    isTrashing = true
                    let urls = model.cullRejectedItems.map(\.url)
                    dismiss()
                    Task {
                        await model.trashURLs(urls)
                        isTrashing = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.cullRejectedItems.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 520, height: 460)
    }
}

private struct RejectedThumbnail: View {
    @Environment(GalleryModel.self) private var model
    let item: ImageItem
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.12))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .task(id: "\(item.url.path)|\(item.modifiedAt.timeIntervalSince1970)") {
            image = await model.thumbnailService.thumbnail(for: item, maxPixel: 120)
        }
    }
}
