import AppKit
import SwiftUI

struct ImageInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GalleryModel.self) private var model
    let item: ImageItem

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    infoGroup("File") {
                        row("Dimensions", item.dimensionsDescription)
                        row("File Size", ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        row("Type", item.format.displayName)
                        row("Created", item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        row("Modified", item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        row("Added", item.addedAt.formatted(date: .abbreviated, time: .shortened))
                        if let exifCaptureDate = item.exifCaptureDate {
                            row("Captured", exifCaptureDate.formatted(date: .abbreviated, time: .shortened))
                        }
                    }

                    if item.cameraMake != nil || item.lens != nil || item.iso != nil {
                        infoGroup("Camera") {
                            if let camera = item.cameraDescription { row("Camera", camera) }
                            if let lens = item.lens { row("Lens", lens) }
                            if let iso = item.iso { row("ISO", "\(iso)") }
                            if let aperture = item.apertureDescription { row("Aperture", aperture) }
                            if let exposure = item.exposureDescription { row("Shutter", exposure) }
                            if let focal = item.focalLengthDescription { row("Focal Length", focal) }
                        }
                    }

                    if item.hasLocation, let latitude = item.latitude, let longitude = item.longitude {
                        infoGroup("Location") {
                            PhotoLocationMap(latitude: latitude, longitude: longitude, title: item.name)
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            row("Latitude", String(format: "%.5f", latitude))
                            row("Longitude", String(format: "%.5f", longitude))
                            Button("Open in Maps") {
                                let url = URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(latitude),\(longitude)")
                                if let url { NSWorkspace.shared.open(url) }
                            }
                            .controlSize(.small)
                        }
                    }

                    if !item.tags.isEmpty {
                        infoGroup("Finder Tags") {
                            Text(item.tags.joined(separator: " · "))
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(16)
            }

            Divider()
            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 430, height: 540)
    }

    private func infoGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}
