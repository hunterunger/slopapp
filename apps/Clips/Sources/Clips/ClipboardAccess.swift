import SlopKit

/// Whether macOS lets Clips read what other apps copy ("Paste from Other Apps", macOS 15.4+):
/// `.allowed`, `.asks` (an alert on each read until allowed), `.denied`. Lives in SlopKit
/// (`PasteboardPrivacy`), shared with Shorthand.
typealias ClipboardAccess = PasteboardPrivacy
