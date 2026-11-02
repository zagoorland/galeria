import CoreServices
import Foundation

/// Watches a folder recursively with FSEvents and debounces bursts of writes.
///
/// FSEvents delivers its callback on a background dispatch queue, so the
/// callback only schedules a hop back to the main actor.
final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "zagoor.galeria.folder-watcher", qos: .utility)
    private var eventHandler: (@MainActor @Sendable () -> Void)?
    private var debounceWorkItem: DispatchWorkItem?

    deinit {
        stop()
    }

    func start(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        stop()
        eventHandler = onChange

        let info = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagWatchRoot |
            kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.scheduleNotification()
            },
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.35,
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        eventHandler = nil
    }

    private func scheduleNotification() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let handler = self.eventHandler else { return }
            Task { @MainActor in handler() }
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.25, execute: item)
    }
}
