import Darwin
import Foundation

/// Mounted volumes a person would recognise, with free space as Finder counts it.
public final class SystemVolumes: VolumeSource {
    public init() {}

    public func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeIsInternalKey,
                                      .volumeIsLocalKey, .volumeIsBrowsableKey, .volumeIsReadOnlyKey,
                                      .volumeIsRootFileSystemKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                               options: [.skipHiddenVolumes]) else { return [] }
        let cached = Self.cachedStats()
        var result: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isRoot = values.volumeIsRootFileSystem ?? (url.path == "/")
            // The sealed system volume is read-only but stands for the startup disk; other
            // read-only volumes (installers, disk images) are left out.
            if !isRoot, values.volumeIsReadOnly == true { continue }
            if values.volumeIsBrowsable == false { continue }
            let name = values.volumeLocalizedName ?? url.lastPathComponent
            var available: UInt64?
            var total = values.volumeTotalCapacity.map { UInt64(max(0, $0)) }
            if values.volumeIsLocal ?? true {
                // Includes purgeable space, like Finder. Local volumes answer quickly.
                if let important = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    .volumeAvailableCapacityForImportantUsage {
                    available = UInt64(max(0, important))
                }
            }
            if available == nil, let stats = cached[url.path] {
                // Network volumes: the kernel's cached numbers, which never block on a server
                // that went away.
                available = stats.available
                total = total ?? stats.total
            }
            guard let available, let total, total > 0 else { continue }
            result.append(VolumeInfo(id: url.path, name: name, available: available, total: total,
                                     isInternal: values.volumeIsInternal ?? false, isBoot: isRoot))
        }
        return result.sorted { a, b in
            if a.isBoot != b.isBoot { return a.isBoot }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// `getfsstat(MNT_NOWAIT)`: mount point → (available, total), without waiting on any server.
    static func cachedStats() -> [String: (available: UInt64, total: UInt64)] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [:] }
        let buffer = UnsafeMutablePointer<statfs>.allocate(capacity: Int(count))
        defer { buffer.deallocate() }
        let filled = getfsstat(buffer, Int32(MemoryLayout<statfs>.stride * Int(count)), MNT_NOWAIT)
        guard filled > 0 else { return [:] }
        var result: [String: (UInt64, UInt64)] = [:]
        for index in 0..<Int(min(filled, count)) {
            var stat = buffer[index]
            let path = withUnsafeBytes(of: &stat.f_mntonname) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            let block = UInt64(stat.f_bsize)
            result[path] = (UInt64(stat.f_bavail) * block, UInt64(stat.f_blocks) * block)
        }
        return result
    }
}
