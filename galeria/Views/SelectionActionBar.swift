import SwiftUI

struct SelectionActionBar: View {
    @Environment(GalleryModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Text(selectionTitle)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.leading, 4)
                .accessibilityLabel("\(model.selection.count) selected, \(ByteCountFormatter.string(fromByteCount: model.selectedTotalSize, countStyle: .file))")

            Divider().frame(height: 18)

            Button(role: .destructive) {
                Task { await model.trashSelection() }
            } label: {
                Label("Trash", systemImage: "trash")
            }
            .help("Move to Trash (Delete)")
            .accessibilityLabel("Move selected images to Trash")

            Menu {
                Button("Choose Folder…") { model.chooseMoveDestination() }
                if !model.quickMoveDestinations.isEmpty {
                    Divider()
                    ForEach(Array(model.quickMoveDestinations.enumerated()), id: \.element.id) { index, record in
                        Button("Move to \(record.name)") {
                            Task { await model.transferSelection(to: record, mode: .move) }
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))),
                                          modifiers: [.command, .option])
                    }
                }
            } label: {
                Label("Move", systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Move Selected Images to a Folder")

            Menu {
                Button("Choose Folder…") { model.chooseCopyDestination() }
                if !model.quickMoveDestinations.isEmpty {
                    Divider()
                    ForEach(model.quickMoveDestinations) { record in
                        Button("Copy to \(record.name)") {
                            Task { await model.transferSelection(to: record, mode: .copy) }
                        }
                    }
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Copy Selected Images to a Folder")

            actionButton("Share", symbol: "square.and.arrow.up", help: "Share…") {
                model.shareSelection()
            }
            actionButton("Reveal", symbol: "finder", help: "Reveal in Finder") {
                model.revealSelection()
            }

            if model.canCompareSelection {
                actionButton("Compare", symbol: "rectangle.split.2x1", help: "Compare Selected Images") {
                    model.openCompare()
                }
            }

            Menu {
                Button("Rotate Left") { Task { await model.rotateSelection(.left) } }
                Button("Rotate Right") { Task { await model.rotateSelection(.right) } }
            } label: {
                Label("Rotate", systemImage: "rotate.left")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Rotate Selected Images")

            Menu {
                ForEach(0...5, id: \.self) { rating in
                    Button(rating == 0 ? "No Rating" : "\(rating) \(rating == 1 ? "Star" : "Stars")") {
                        Task { await model.setRating(rating) }
                    }
                }
            } label: {
                Label("Rate", systemImage: "star")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Rate Selected Images")

            Menu {
                Button("None") { Task { await model.setLabel(nil) } }
                ForEach(FinderColorLabel.allCases) { label in
                    Button(label.displayName) { Task { await model.setLabel(label) } }
                }
            } label: {
                Label("Label", systemImage: "tag")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Apply a Finder Color Label")

            Spacer(minLength: 4)

            actionButton("Clear Selection", symbol: "xmark.circle", help: "Clear Selection") {
                model.clearSelection()
            }
        }
        .controlSize(.small)
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.separator.opacity(0.7)).frame(height: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var selectionTitle: String {
        let count = model.selection.count
        let size = ByteCountFormatter.string(fromByteCount: model.selectedTotalSize, countStyle: .file)
        return "\(count) selected · \(size)"
    }

    private func actionButton(_ label: String, symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
        }
        .help(help)
        .accessibilityLabel(label)
    }
}
