import AppKit
import SwiftUI

struct PreviewInfoPanel: View {
    @Environment(GalleryModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let item: ImageItem

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Info")
                    .font(.headline)
                Spacer()
                Button {
                    model.togglePreviewInfo()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Hide Info (⌘I)")
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.callout.weight(.semibold))
                            .textSelection(.enabled)
                        Text(item.url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if item.hasLocation, let latitude = item.latitude, let longitude = item.longitude {
                        PhotoLocationMap(latitude: latitude, longitude: longitude, title: item.name)
                            .frame(height: 138)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            }
                    }

                    section("File") {
                        row("Dimensions", item.dimensionsDescription)
                        row("Size", ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        row("Type", item.format.displayName)
                        row("Created", item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        row("Modified", item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        if let capture = item.exifCaptureDate {
                            row("Captured", capture.formatted(date: .abbreviated, time: .shortened))
                        }
                    }

                    let hasCamera = item.cameraMake != nil || item.lens != nil || item.iso != nil
                    if hasCamera {
                        section("Camera") {
                            if let camera = item.cameraDescription { row("Camera", camera) }
                            if let lens = item.lens { row("Lens", lens) }
                            if let iso = item.iso { row("ISO", "\(iso)") }
                            if let aperture = item.apertureDescription { row("Aperture", aperture) }
                            if let exposure = item.exposureDescription { row("Shutter", exposure) }
                            if let focal = item.focalLengthDescription { row("Focal", focal) }
                        }
                    }

                    if !item.tags.isEmpty {
                        section("Tags") {
                            Text(item.tags.joined(separator: " · "))
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }

                    section("Status") {
                        row("Rating", item.rating == 0 ? "None" : String(repeating: "★", count: item.rating))
                        row("Flag", item.flag.displayName)
                        row("Label", item.label?.displayName ?? "None")
                    }

                    if item.hasLocation, let latitude = item.latitude, let longitude = item.longitude {
                        section("Location") {
                            row("Latitude", String(format: "%.5f", latitude))
                            row("Longitude", String(format: "%.5f", longitude))
                            Button("Open in Maps") {
                                guard let url = URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(latitude),\(longitude)") else { return }
                                NSWorkspace.shared.open(url)
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.92))
        .environment(\.colorScheme, .dark)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
