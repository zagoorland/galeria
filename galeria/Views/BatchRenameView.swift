import SwiftUI

struct BatchRenameView: View {
    @Environment(GalleryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pattern = "{name}"
    @State private var counterStart = 1
    @State private var counterPadding = 2
    @State private var isRenaming = false

    let items: [ImageItem]
    private let tokens = ["{name}", "{counter}", "{date}", "{camera}"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch Rename")
                        .font(.headline)
                    Text("\(items.count) \(items.count == 1 ? "image" : "images") · extensions are preserved")
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
                .help("Close")
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pattern")
                            .font(.callout.weight(.medium))
                        TextField("Rename Pattern", text: $pattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        HStack(spacing: 6) {
                            ForEach(tokens, id: \.self) { token in
                                Button(token) {
                                    if !pattern.isEmpty && !pattern.hasSuffix(" ") { pattern += " " }
                                    pattern += token
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    HStack(spacing: 20) {
                        Stepper("Start at \(counterStart)", value: $counterStart, in: 0...99999)
                        Stepper("Padding \(counterPadding)", value: $counterPadding, in: 1...10)
                    }
                    .font(.callout)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Preview")
                                .font(.callout.weight(.medium))
                            Spacer()
                            if !plan.collisions.isEmpty {
                                Label("Collision", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            } else if plan.canApply {
                                Text("\(plan.effectiveChanges.count) names will change")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(plan.changes.prefix(8))) { change in
                                HStack(spacing: 8) {
                                    Text(change.originalURL.lastPathComponent)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(change.renamedURL.lastPathComponent)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(change.isNoop ? .secondary : .primary)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(.caption, design: .monospaced))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                if change.id != plan.changes.prefix(8).last?.id {
                                    Divider()
                                }
                            }
                            if plan.changes.count > 8 {
                                Text("+\(plan.changes.count - 8) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                            }
                        }
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        ForEach(plan.collisions, id: \.self) { collision in
                            Text(collision)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(16)
            }

            Divider()
            HStack {
                Text("Reverts with ⌘Z")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isRenaming ? "Renaming…" : "Rename") {
                    Task {
                        isRenaming = true
                        if await model.performBatchRename(plan) {
                            dismiss()
                        }
                        isRenaming = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!plan.canApply || isRenaming)
            }
            .padding(12)
        }
        .frame(width: 560, height: 540)
    }

    private var plan: RenamePlan {
        BatchRenameEngine(existingPaths: model.existingFilePaths())
            .plan(items: items, pattern: pattern, counterStart: counterStart, counterPadding: counterPadding)
    }
}
