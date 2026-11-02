import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ExportProgressState {
    var fraction: Double = 0
    var message = ""
    var isRunning = false
}

struct ExportSheet: View {
    @Environment(GalleryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let items: [ImageItem]

    @State private var format: ExportFormat = .jpeg
    @State private var quality = 0.9
    @State private var maximumDimension = 0
    @State private var stripMetadata = false
    @State private var destination: URL?
    @State private var exportTask: Task<Void, Never>?
    @State private var progress = ExportProgressState()
    @State private var exportedCount = 0
    @State private var errorMessage: String?
    @State private var didFinish = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Images")
                        .font(.headline)
                    Text("\(items.count) \(items.count == 1 ? "image" : "images")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if progress.isRunning {
                        exportTask?.cancel()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(progress.isRunning ? "Cancel Export" : "Close")
            }
            .padding(16)
            Divider()

            Form {
                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(progress.isRunning)

                    if format.supportsQuality {
                        HStack {
                            Text("Quality")
                            Slider(value: $quality, in: 0.3...1.0)
                            Text("\(Int(quality * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                        .disabled(progress.isRunning)
                    }

                    Picker("Maximum Dimension", selection: $maximumDimension) {
                        Text("Original").tag(0)
                        Text("1000 px").tag(1000)
                        Text("2000 px").tag(2000)
                        Text("4000 px").tag(4000)
                        Text("6000 px").tag(6000)
                    }
                    .disabled(progress.isRunning)

                    Toggle("Strip Metadata", isOn: $stripMetadata)
                        .disabled(progress.isRunning)
                }

                Section("Destination") {
                    HStack {
                        Text(destination?.path ?? "Choose a folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(destination == nil ? .secondary : .primary)
                        Spacer()
                        Button("Choose…") {
                            chooseDestination()
                        }
                        .disabled(progress.isRunning)
                    }
                }
            }
            .formStyle(.grouped)

            if progress.isRunning || didFinish || errorMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if progress.isRunning {
                        ProgressView(value: progress.fraction) {
                            Text(progress.message)
                                .font(.caption)
                        } currentValueLabel: {
                            Text("\(Int(progress.fraction * 100))%")
                                .font(.caption.monospacedDigit())
                        }
                        .progressViewStyle(.linear)
                    } else if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    } else if didFinish {
                        Label("\(exportedCount) \(exportedCount == 1 ? "image" : "images") exported", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                        if let destination {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([destination])
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Spacer()
                Button(didFinish ? "Done" : "Cancel") {
                    if progress.isRunning {
                        exportTask?.cancel()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)

                Button(progress.isRunning ? "Exporting…" : "Export") {
                    startExport()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(destination == nil || items.isEmpty || progress.isRunning)
            }
            .padding(12)
        }
        .frame(width: 500, height: 540)
        .onDisappear {
            exportTask?.cancel()
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Export Images To"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            destination = panel.url
        }
    }

    private func startExport() {
        guard let destination else { return }
        errorMessage = nil
        didFinish = false
        progress.isRunning = true
        progress.fraction = 0
        progress.message = "Preparing…"
        let options = ExportOptions(
            format: format,
            quality: quality,
            maximumDimension: maximumDimension == 0 ? nil : maximumDimension,
            stripMetadata: stripMetadata,
            destination: destination
        )
        let items = self.items
        let service = model.exportService
        let state = progress
        exportTask = Task {
            let access = destination.startAccessingSecurityScopedResource()
            defer { if access { destination.stopAccessingSecurityScopedResource() } }
            do {
                let results = try await service.export(items: items, options: options) { fraction, message in
                    state.fraction = fraction
                    state.message = message
                }
                await MainActor.run {
                    exportedCount = results.count
                    state.isRunning = false
                    didFinish = true
                }
            } catch is CancellationError {
                await MainActor.run {
                    state.isRunning = false
                    errorMessage = "Export cancelled."
                }
            } catch {
                await MainActor.run {
                    state.isRunning = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
