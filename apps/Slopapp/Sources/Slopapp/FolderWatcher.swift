import Darwin
import Foundation

/// Calls back (debounced) when apps are added to or removed from the watched folders, e.g.
/// an app dragged to the Trash in Finder. Kernel vnode events: no polling.
@MainActor
final class FolderWatcher {
    private var sources: [String: any DispatchSourceFileSystemObject] = [:]
    private var pending: DispatchWorkItem?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    /// Starts watching any of these folders that exist and aren't watched yet.
    func watch(_ folders: [URL]) {
        for folder in folders {
            let path = folder.standardizedFileURL.path
            guard sources[path] == nil else { continue }
            let fd = Darwin.open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
            source.setEventHandler { [weak self, weak source] in
                let events = source?.data ?? []
                MainActor.assumeIsolated { self?.changed(path, events: events) }
            }
            source.setCancelHandler { Darwin.close(fd) }
            sources[path] = source
            source.resume()
        }
    }

    private func changed(_ path: String, events: DispatchSource.FileSystemEvent) {
        if events.contains(.delete) || events.contains(.rename) {
            // The folder itself went away or moved: stop watching it (it's re-added if it returns).
            sources.removeValue(forKey: path)?.cancel()
        }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.onChange() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
