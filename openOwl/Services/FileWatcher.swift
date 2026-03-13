import Foundation
import CoreServices

final class FileWatcher {
    private let directoryURL: URL
    private let debounceInterval: TimeInterval
    private let ignoredDirectoryNames: Set<String>
    private let onChange: () -> Void

    private let queue = DispatchQueue(label: "com.openowl.filewatcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var isRunning = false
    private var debounceTimer: DispatchSourceTimer?

    init?(
        directoryURL: URL,
        debounceInterval: TimeInterval = 0.3,
        ignoredDirectoryNames: Set<String> = [".git", "node_modules"],
        onChange: @escaping () -> Void
    ) {
        self.directoryURL = directoryURL
        self.debounceInterval = debounceInterval
        self.ignoredDirectoryNames = ignoredDirectoryNames
        self.onChange = onChange

        guard createStream() else {
            return nil
        }
    }

    deinit {
        stop()
    }

    func start() {
        guard let stream else { return }
        guard !isRunning else { return }
        isRunning = FSEventStreamStart(stream)
    }

    func stop() {
        debounceTimer?.cancel()
        debounceTimer = nil

        if let stream {
            if isRunning {
                FSEventStreamStop(stream)
                isRunning = false
            }
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func createStream() -> Bool {
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPathsPointer, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handleEvents(
                eventPathsPointer: eventPathsPointer,
                numEvents: Int(numEvents)
            )
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [directoryURL.path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceInterval,
            flags
        ) else {
            return false
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        self.stream = stream
        return true
    }

    private func handleEvents(eventPathsPointer: UnsafeMutableRawPointer, numEvents: Int) {
        let paths = unsafeBitCast(eventPathsPointer, to: NSArray.self)
        guard paths.count > 0, numEvents > 0 else { return }

        for index in 0..<min(numEvents, paths.count) {
            guard let path = paths[index] as? String else { continue }
            if !isIgnored(path: path) {
                scheduleDebouncedCallback()
                return
            }
        }
    }

    private func isIgnored(path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardized.pathComponents
        return components.contains { ignoredDirectoryNames.contains($0) }
    }

    private func scheduleDebouncedCallback() {
        debounceTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + debounceInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.onChange()
            }
        }

        debounceTimer = timer
        timer.resume()
    }
}
