import CArchive
import Darwin
import Foundation
@testable import CrateCore

/// Test folders live under /tmp/crate-test/unit (the only place tests may write).
enum TestFolder {
    static func make(_ label: String = #function) -> URL {
        let clean = label.filter { $0.isLetter || $0.isNumber }
        let url = URL(fileURLWithPath: "/tmp/crate-test/unit", isDirectory: true)
            .appendingPathComponent("\(clean.prefix(40))-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ text: String, to url: URL) {
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(text.utf8).write(to: url)
    }

    /// Relative paths of everything under `folder`, sorted ("a/", "a/b.txt").
    static func tree(_ folder: URL) -> [String] {
        let base = Naming.realPath(folder)
        var result: [String] = []
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        while let url = enumerator?.nextObject() as? URL {
            var relative = String(url.path.dropFirst(base.path.count + 1))
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true, values?.isSymbolicLink != true { relative += "/" }
            result.append(relative)
        }
        return result.sorted()
    }

    static func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    }
}

/// Writes archives with arbitrary (also hostile) entries, straight through libarchive.
enum RawArchive {
    enum Format { case zip, tar, tarGz, sevenZip }

    enum Body {
        case file(Data)
        case zeros(Int64)
        case folder
        case symlink(String)
        case hardlink(String)
    }

    struct Entry {
        var path: String
        var body: Body
        var perm: mode_t = 0o644
        init(_ path: String, _ body: Body, perm: mode_t = 0o644) {
            self.path = path
            self.body = body
            self.perm = perm
        }
        static func text(_ path: String, _ text: String) -> Entry { Entry(path, .file(Data(text.utf8))) }
    }

    static func write(_ url: URL, format: Format = .zip, entries: [Entry], password: String? = nil, zipCrypto: Bool = false) {
        let a = archive_write_new()!
        defer { archive_write_free(a) }
        switch format {
        case .zip:
            archive_write_set_format_zip(a)
            if let password {
                archive_write_set_options(a, zipCrypto ? "zip:encryption=zipcrypt" : "zip:encryption=aes256")
                archive_write_set_passphrase(a, password)
            }
        case .tar: archive_write_set_format_pax_restricted(a)
        case .tarGz:
            archive_write_set_format_pax_restricted(a)
            archive_write_add_filter_gzip(a)
        case .sevenZip: archive_write_set_format_7zip(a)
        }
        precondition(archive_write_open_filename(a, url.path) == ARCHIVE_OK)
        let e = archive_entry_new()!
        defer { archive_entry_free(e) }
        for entry in entries {
            archive_entry_clear(e)
            archive_entry_set_pathname_utf8(e, entry.path)
            archive_entry_set_perm(e, entry.perm)
            archive_entry_set_mtime(e, 1_700_000_000, 0)
            switch entry.body {
            case .file(let data):
                archive_entry_set_filetype(e, UInt32(AE_IFREG))
                archive_entry_set_size(e, Int64(data.count))
                archive_write_header(a, e)
                _ = data.withUnsafeBytes { archive_write_data(a, $0.baseAddress, data.count) }
            case .zeros(let count):
                archive_entry_set_filetype(e, UInt32(AE_IFREG))
                archive_entry_set_size(e, count)
                archive_write_header(a, e)
                let chunk = [UInt8](repeating: 0, count: 1 << 20)
                var left = count
                while left > 0 {
                    let n = Int(min(left, Int64(chunk.count)))
                    _ = chunk.withUnsafeBytes { archive_write_data(a, $0.baseAddress, n) }
                    left -= Int64(n)
                }
            case .folder:
                archive_entry_set_filetype(e, UInt32(AE_IFDIR))
                archive_write_header(a, e)
            case .symlink(let target):
                archive_entry_set_filetype(e, UInt32(AE_IFLNK))
                archive_entry_set_symlink_utf8(e, target)
                archive_write_header(a, e)
            case .hardlink(let target):
                archive_entry_set_filetype(e, UInt32(AE_IFREG))
                archive_entry_set_hardlink_utf8(e, target)
                archive_entry_set_size(e, 0)
                archive_write_header(a, e)
            }
            archive_write_finish_entry(a)
        }
        archive_write_close(a)
    }
}

/// A file system whose free space and Trash can be controlled.
final class FakeFileSystem: FileSystem, @unchecked Sendable {
    var free: Int64?
    var trashed: [URL] = []
    var quarantines: [String: Data] = [:]
    let real = SystemFileSystem()

    init(free: Int64? = nil) { self.free = free }

    func availableCapacity(at url: URL) -> Int64? { free ?? real.availableCapacity(at: url) }
    func quarantine(of url: URL) -> Data? { quarantines[url.path] ?? real.quarantine(of: url) }
    func setQuarantine(_ value: Data, on url: URL) { real.setQuarantine(value, on: url) }
    func trash(_ url: URL) throws -> URL { trashed.append(url); return url }
    func isWritableFolder(_ url: URL) -> Bool { real.isWritableFolder(url) }
}

extension ArchiveListing {
    var paths: [String] { entries.map(\.path).sorted() }
}

import CommonCrypto

enum CommonCryptoShim {
    static func sha256(_ data: inout [UInt8], _ digest: inout [UInt8]) {
        CC_SHA256(&data, CC_LONG(data.count), &digest)
    }
}
