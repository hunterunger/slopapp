import Darwin
import Foundation
import TidyCore

/// Space map fixtures: realistic things to find in the walkthrough fixture's home folder,
/// stand-in disks, and a big synthetic tree for the scan benchmark. Everything stays inside
/// `/tmp/tidy-test` (or the temp folder), like `Fixture`.
public enum MapFixture {
    /// Adds map content to a walkthrough fixture (real data, about 250 MB) and builds two
    /// stand-in disks under `root/disks`. Returns the `TIDY_VOLUMES` value to launch with:
    /// the fixture root stands in for the startup disk.
    @discardableResult
    public static func addMapExtras(to fixture: Fixture) throws -> String {
        guard Fixture.isSafeRoot(fixture.root) else { throw Fixture.FixtureError.unsafeRoot(fixture.root.path) }
        let home = fixture.home
        let mb = 1_000_000
        try write(home, "Movies/Exports/Final cut v3.mov", 60 * mb)
        try write(home, "Movies/Exports/Rough cut.mov", 38 * mb)
        try write(home, "Movies/Exports/Old/Teaser 2024.mov", 22 * mb)
        for b in 0..<3 {
            for f in 0..<12 {
                try write(home, "Library/Application Support/MobileSync/Backup/Fixture-iPhone-\(b + 1)/\(String(format: "%02x", f))/blob-\(f)", (1 + f % 3) * mb)
            }
        }
        // A web project: thousands of tiny files (the "smaller items" case).
        for package in 0..<40 {
            for file in 0..<50 {
                try write(home, "Developer/web-app/node_modules/pkg-\(package)/lib/file-\(file).js", 4_000)
            }
        }
        try write(home, "Developer/web-app/bundle.js", 3 * mb)
        try sparse(home, "Virtual Machines/Fixture Linux.vmdk", logical: 2_000_000_000, written: 18 * mb)
        // Clones and a hard link: count once, marked.
        try write(home, "Downloads/Installers/Fixture Studio.dmg", 15 * mb)
        let original = home.appendingPathComponent("Downloads/Installers/Fixture Studio.dmg").path
        for copy in ["Downloads/Installers/Fixture Studio copy.dmg", "Desktop/Fixture Studio.dmg"] {
            let target = home.appendingPathComponent(copy)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = clonefile(original, target.path, 0)
        }
        try write(home, "Music/Sessions/Take 4.wav", 12 * mb)
        _ = link(home.appendingPathComponent("Music/Sessions/Take 4.wav").path,
                 home.appendingPathComponent("Music/Take 4 (linked).wav").path)
        for i in 0..<3_000 { try write(home, "Downloads/Big Folder of Small Things/note-\(i).txt", 3_000) }
        // Synced folders: shown, never moved.
        try write(home, "Library/Mobile Documents/com~apple~CloudDocs/Book draft.pages", 5 * mb)
        try write(home, "Library/CloudStorage/FixtureDrive-fixture@example.com/My Drive/Slides.key", 3 * mb)
        // A library package.
        for i in 0..<8 { try write(home, "Pictures/Fixture Library.photoslibrary/originals/IMG_\(1000 + i).heic", 2 * mb) }
        try write(home, "Library/Mail/V10/Inbox.mbox/Messages/1.emlx", 2 * mb)

        let disks = fixture.root.appendingPathComponent("disks")
        let stick = disks.appendingPathComponent("Fixture Stick")
        try write(stick, "Footage/clip-1.mov", 30 * mb)
        try write(stick, "Footage/clip-2.mov", 20 * mb)
        for i in 0..<40 { try write(stick, "Photos/photo-\(i).jpg", 500_000) }
        try write(stick, ".Spotlight-V100/store.db", mb)
        let archive = disks.appendingPathComponent("Archive")
        try write(archive, "Old Projects/2019.zip", 9 * mb)
        try write(archive, "Old Projects/2020.zip", 6 * mb)

        let root = fixture.root.standardizedFileURL.path
        return [
            "\(root)|Fixture HD|startup|2400000000|700000000|160000000|420000000",
            "\(stick.path)|Fixture Stick|external|64000000000|48000000000",
            "\(archive.path)|Archive|readonly|16000000000|12000000000",
        ].joined(separator: ";")
    }

    /// A synthetic tree for the scan benchmark: `files` files in three levels of folders
    /// (about 100 per leaf folder; 95 % empty, the rest 1–8 KB, so it's light on disk), plus
    /// clones, hard links, sparse files, a package, an unreadable folder, a 40-level chain and
    /// a 255-byte name.
    public static func createTree(at root: URL, files: Int) throws {
        guard Fixture.isSafeRoot(root) else { throw Fixture.FixtureError.unsafeRoot(root.path) }
        try Fixture.remove(root)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let leaves = max(1, files / 100)
        let top = 20
        let middle = max(1, Int((Double(leaves) / Double(top) / 10).rounded(.up)))
        var made = 0
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return seed }
        let buffer = [UInt8](repeating: 0x5A, count: 8_192)
        outer: for a in 0..<top {
            for b in 0..<middle {
                for c in 0..<10 {
                    let folder = root.path + "/area-\(a)/group-\(b)/leaf-\(c)"
                    try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
                    for f in 0..<100 {
                        if made >= files { break outer }
                        let fd = open(folder + "/item-\(f).dat", O_CREAT | O_WRONLY | O_TRUNC, 0o644)
                        guard fd >= 0 else { continue }
                        if next() % 20 == 0 {
                            let size = 1 + Int(next() % 8_192)
                            _ = buffer.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, size) }
                        }
                        close(fd)
                        made += 1
                    }
                }
            }
        }
        let extras = root.appendingPathComponent("extras")
        try write(extras, "clone-source.bin", 40_000)
        for i in 0..<100 {
            _ = clonefile(extras.appendingPathComponent("clone-source.bin").path, extras.appendingPathComponent("clone-\(i).bin").path, 0)
        }
        try write(extras, "link-source.bin", 40_000)
        for i in 0..<100 {
            _ = link(extras.appendingPathComponent("link-source.bin").path, extras.appendingPathComponent("link-\(i).bin").path)
        }
        try sparse(extras, "disk.img", logical: 4_000_000_000, written: 1_000_000)
        for i in 0..<20 { try write(extras, "Fixture.app/Contents/Resources/r\(i).bin", 20_000) }
        try write(extras, "locked/unreadable.bin", 10_000)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: extras.appendingPathComponent("locked").path)
        var deep = extras.appendingPathComponent("deep")
        for level in 0..<40 { deep.appendPathComponent("level-\(level)") }
        try write(deep, "bottom.bin", 1_000)
        try write(extras, String(repeating: "n", count: 251) + ".bin", 1_000)
        for i in 0..<5 { try write(extras, "big-\(i).bin", 2_000_000) }
    }

    private static func write(_ base: URL, _ relative: String, _ bytes: Int) throws {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: UInt8(truncatingIfNeeded: relative.utf8.count | 1), count: bytes).write(to: url)
    }

    private static func sparse(_ base: URL, _ relative: String, logical: Int64, written: Int) throws {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 3, count: written))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(logical))
        try handle.close()
    }
}
