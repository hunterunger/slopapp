import AppKit
import ClipsCore

/// Trims whitespace from both ends of RTF and RTFD, keeping the formatting in between.
/// Reading and writing RTF needs no main thread, so this runs with the rest of capture.
enum RichTextTrim {
    static let trimmer: RichTextTrimmer = { rep in trim(rep) }

    static func trim(_ rep: Representation) -> Representation? {
        let isRTFD = rep.type == PasteboardType.rtfd
        let read = isRTFD ? NSAttributedString(rtfd: rep.data, documentAttributes: nil)
            : NSAttributedString(rtf: rep.data, documentAttributes: nil)
        guard let read else { return nil }
        let string = read.string as NSString
        let keep = CharacterSet.whitespacesAndNewlines.inverted
        let first = string.rangeOfCharacter(from: keep)
        let last = string.rangeOfCharacter(from: keep, options: .backwards)
        guard first.location != NSNotFound else { return nil }
        let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let trimmed = read.attributedSubstring(from: range)
        let whole = NSRange(location: 0, length: trimmed.length)
        let data = isRTFD ? trimmed.rtfd(from: whole, documentAttributes: [:])
            : trimmed.rtf(from: whole, documentAttributes: [:])
        return data.map { Representation(type: rep.type, data: $0) }
    }
}
