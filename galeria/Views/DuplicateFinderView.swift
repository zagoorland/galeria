import AppKit
import SwiftUI

struct DuplicateFinderView: View {
    @Environment(GalleryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: DuplicateMode = .exact
    @State private var threshold = 0.35
    @State private var groups: [DuplicateGroup] = []
    @State private var keepers: [UUID: URL] = [:]
    @State private var isScanning = false
    @State private var progress: Double = 0
    @State private var status = "Ready to scan"
    @State private var scanTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find Duplicates")
                        .font(.headline)
                    Text("Review identical or visually similar images before removing anything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    scanTask?.cancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
            }
            .padding(16)
            Divider()

            HStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    ForEach(DuplicateMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .disabled(isScanning)

                if mode == .similar {
                    Text("Threshold")
                        .font(.callout)
                    Slider(value: $threshold, in: 0.05...1.0)
                        .frame(width: 110)
                        .disabled(isScanning)
                    Text(String(format: "%.2f", threshold))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                }

                Spacer()
                Button(isScanning ? "Cancel" : "Scan") {
                    if isScanning {
                        scanTask?.cancel()
                        isScanning = false
                    } else {
                        startScan()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.folderStore.items.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if isScanning {
                VStack(spacing: 12) {
                    ProgressView(value: progress) {
                        Text(status)
                            .font(.callout)
                    } currentValueLabel: {
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                    }
                    .progressViewStyle(.linear)
                    Text("Large folders take longer. You can cancel at any time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Scan Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { startScan() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                ContentUnavailableView {
                    Label(status == "Ready to scan" ? "Find Duplicates" : "No Duplicates Found", systemImage: "square.on.square")
                } description: {
                    Text(status == "Ready to scan"
                         ? "Scan this folder for exact copies or similar photos."
                         : status)
                } actions: {
                    if status != "Ready to scan" {
                        Button("Scan Again") { startScan() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            groupCard(group, number: index + 1)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
            HStack {
                Text("\(groups.count) groups · \(duplicateCount) to remove")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    scanTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Trash \(duplicateCount) Duplicates") {
                    trashDuplicates()
                }
                .buttonStyle(.borderedProminent)
                .disabled(groups.isEmpty || isScanning || duplicateCount == 0)
            }
            .padding(12)
        }
        .frame(width: 720, height: 620)
        .task {
            if groups.isEmpty && !isScanning {
                startScan()
            }
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private var duplicateCount: Int {
        groups.reduce(0) { total, group in
            total + max(0, group.items.count - 1)
        }
    }

    private func groupCard(_ group: DuplicateGroup, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Group \(number)")
                    .font(.callout.weight(.semibold))
                Text("\(group.items.count) \(group.items.count == 1 ? "image" : "images")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let distance = group.smallestDistance, group.mode == .similar {
                    Text("distance \(String(format: "%.2f", distance))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Click an image to keep it")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            VStack(spacing: 4) {
                ForEach(group.items) { item in
                    duplicateRow(item, group: group)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func duplicateRow(_ item: ImageItem, group: DuplicateGroup) -> some View {
        let isKeeper = keepers[group.id] == item.url
        return Button {
            keepers[group.id] = item.url
        } label: {
            HStack(spacing: 10) {
                DuplicateThumbnail(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(item.dimensionsDescription) · \(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isKeeper ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isKeeper ? Color.accentColor : Color.secondary)
                Text(isKeeper ? "Keep" : "Remove")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isKeeper ? Color.accentColor : Color.secondary)
                    .frame(width: 48, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isKeeper ? Color.accentColor.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(isKeeper ? "keep" : "remove")")
    }

    private func startScan() {
        scanTask?.cancel()
        groups = []
        keepers = [:]
        errorMessage = nil
        isScanning = true
        progress = 0
        status = "Starting scan…"
        let items = model.folderStore.items
        let mode = mode
        let threshold = threshold
        let finder = model.duplicateFinder
        scanTask = Task {
            do {
                let results = try await finder.find(in: items, mode: mode, threshold: threshold) { fraction, message in
                    progress = fraction
                    status = message
                }
                guard !Task.isCancelled else { return }
                groups = results
                isScanning = false
                status = results.isEmpty ? "No duplicates found" : "Found \(results.count) groups"
                for group in results {
                    keepers[group.id] = group.items.first?.url
                }
            } catch is CancellationError {
                isScanning = false
                status = "Scan cancelled"
            } catch {
                isScanning = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func trashDuplicates() {
        let urls = groups.flatMap { group -> [URL] in
            guard let keeper = keepers[group.id] else { return [] }
            return group.items.filter { $0.url != keeper }.map(\.url)
        }
        scanTask?.cancel()
        dismiss()
        Task {
            await model.trashURLs(urls)
        }
    }
}


private struct DuplicateThumbnail: View {
    @Environment(GalleryModel.self) private var model
    let item: ImageItem
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.10))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .task(id: "\(item.url.path)|\(item.modifiedAt.timeIntervalSince1970)") {
            image = await model.thumbnailService.thumbnail(for: item, maxPixel: 160)
        }
    }
}
