import SwiftUI

struct KeyboardShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard Shortcuts")
                        .font(.largeTitle.weight(.bold))
                    Text("Galeria is designed to be used without leaving the keyboard.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                shortcutSection("Files & Browsing", shortcuts: [
                    ("Open a folder", "⌘O"),
                    ("Open enclosing folder", "⌘↑"),
                    ("Search images", "⌘F"),
                    ("Show filters", "⇧⌘L"),
                    ("Select all images", "⌘A"),
                    ("Clear selection", "⇧⌘A"),
                    ("Toggle selection mode", "⇧⌘S"),
                    ("Original aspect ratio", "—")
                ])

                shortcutSection("Selection & Actions", shortcuts: [
                    ("Select one · range · toggle", "Click · ⇧Click · ⌘Click"),
                    ("Rectangle select", "Drag empty space"),
                    ("Quick Look / close preview", "Space"),
                    ("Open preview", "Return"),
                    ("Close preview", "Esc"),
                    ("Move to Trash", "Delete, ⌘⌫"),
                    ("Undo / Redo", "⌘Z / ⇧⌘Z"),
                    ("Rate 0–5 stars", "0 – 5"),
                    ("Pick / Reject", "P / X"),
                    ("Color label", "6 – 9"),
                    ("Rotate left / right", "⌘L / ⌘R"),
                    ("Reveal in Finder", "⇧⌘R"),
                    ("Export selected", "⇧⌘E")
                ])

                shortcutSection("Preview", shortcuts: [
                    ("Previous / next image", "← → or ↑ ↓"),
                    ("Trackpad: previous / next image", "Swipe right / left"),
                    ("Trackpad: close preview", "Swipe down"),
                    ("Zoom in / out", "+ / −"),
                    ("Fit image", "0"),
                    ("Toggle fit / 100%", "Double-click"),
                    ("Pan", "Scroll while zoomed"),
                    ("Show / hide filmstrip", "F"),
                    ("Photo info", "⌘I"),
                    ("Live Text on / off", "L"),
                    ("Compare selected", "⌥⌘C"),
                    ("Start slideshow", "⌥⌘P"),
                    ("Slideshow play / pause", "Space"),
                    ("Exit slideshow / cull", "Esc")
                ])

                shortcutSection("Organize", shortcuts: [
                    ("Cull folder", "⇧⌘K"),
                    ("Find duplicates", "⌥⌘D"),
                    ("Photo map", "⌥⌘M"),
                    ("Batch rename", "—"),
                    ("Quick-move destinations", "⌥⌘1 – ⌥⌘9")
                ])
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 620)
        .accessibilityIdentifier("shortcuts.window")
    }

    private func shortcutSection(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    HStack {
                        Text(shortcut.0)
                            .font(.callout)
                        Spacer()
                        Text(shortcut.1)
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(index.isMultiple(of: 2) ? Color(nsColor: .controlBackgroundColor).opacity(0.55) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
            }
        }
    }
}
