import Foundation

/// Whether this process has Full Disk Access. Same probe as SlopKit's `Permission`, here so
/// the command line tool can use it: the user's TCC database is only readable with access.
public enum FullDiskAccessProbe {
    public static func isGranted() -> Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        try? handle.close()
        return true
    }
}
