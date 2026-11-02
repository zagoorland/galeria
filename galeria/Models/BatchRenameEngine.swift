import Foundation

struct RenameChange: Hashable, Sendable, Identifiable {
    let originalURL: URL
    let renamedURL: URL
    var id: URL { originalURL }
    var isNoop: Bool { originalURL.standardizedFileURL == renamedURL.standardizedFileURL }
}

struct RenamePlan: Sendable {
    let changes: [RenameChange]
    let collisions: [String]

    var canApply: Bool { collisions.isEmpty && changes.contains { !$0.isNoop } }
    var effectiveChanges: [RenameChange] { changes.filter { !$0.isNoop } }
}

/// Pure batch-rename pattern engine. The pattern describes the base filename;
/// each image's original extension is preserved.
struct BatchRenameEngine: Sendable {
    let existingPaths: Set<String>

    init(existingPaths: Set<String> = []) {
        self.existingPaths = Set(existingPaths.map { $0.lowercased() })
    }

    func plan(items: [ImageItem], pattern: String, counterStart: Int, counterPadding: Int) -> RenamePlan {
        let padding = min(max(counterPadding, 1), 10)
        let start = max(counterStart, 0)
        let existingOriginalPaths = Set(items.map { $0.url.standardizedFileURL.path.lowercased() })
        var occupied: [String: URL] = [:]
        var changes: [RenameChange] = []
        var collisions: [String] = []

        for (index, item) in items.enumerated() {
            let base = Self.render(pattern: pattern, item: item,
                                    counter: start + index, padding: padding)
            let cleaned = Self.sanitizedBase(base)
            if cleaned.isEmpty {
                collisions.append("The pattern produces an empty name for \(item.name).")
                continue
            }
            let originalExtension = item.url.pathExtension
            let fileName = originalExtension.isEmpty ? cleaned : "\(cleaned).\(originalExtension)"
            let destination = item.url.deletingLastPathComponent().appendingPathComponent(fileName)
            let key = destination.standardizedFileURL.path.lowercased()

            if let previous = occupied[key] {
                collisions.append("“\(previous.lastPathComponent)” and “\(destination.lastPathComponent)” would use the same name.")
            }
            occupied[key] = destination

            if existingPaths.contains(key) && !existingOriginalPaths.contains(key) {
                collisions.append("A file named “\(destination.lastPathComponent)” already exists.")
            }
            changes.append(RenameChange(originalURL: item.url, renamedURL: destination))
        }

        return RenamePlan(changes: changes, collisions: Array(Set(collisions)).sorted())
    }

    nonisolated static func render(pattern: String, item: ImageItem, counter: Int, padding: Int) -> String {
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let counterValue = String(format: "%0\(padding)d", counter)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let camera = item.cameraModel ?? item.cameraMake ?? "Unknown Camera"
        var result = pattern
        let tokens: [(String, String)] = [
            ("{name}", baseName),
            ("{counter}", counterValue),
            ("{date}", formatter.string(from: item.captureDate)),
            ("{camera}", camera)
        ]
        for (token, value) in tokens {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }

    nonisolated static func sanitizedBase(_ value: String) -> String {
        var cleaned = value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        return String(cleaned.prefix(200))
    }
}
