import Foundation

/// Leaves Squish's own earlier outputs out of a drop, so adding a folder again doesn't
/// make "photo-small-small.jpg". Only files Squish tagged count: a user's own
/// "holiday-small.jpg" is always compressed.
public enum OutputFilter {
    /// Files to compress, and how many were skipped as Squish's own outputs.
    public static func split(_ urls: [URL], files: any FileStore = SystemFileStore()) -> (keep: [URL], skipped: Int) {
        var keep: [URL] = []
        var skipped = 0
        for url in urls {
            if files.isMarkedAsOutput(url) { skipped += 1 } else { keep.append(url) }
        }
        return (keep, skipped)
    }
}
