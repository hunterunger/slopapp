import CoreText
import Foundation
import SpecimenCore

// specimen-fixture: the OFL test font for walkthroughs and blind tests.
//
//   specimen-fixture install [dir]   copy Silkscreen Regular + Bold to dir (default /tmp/specimen-test)
//   specimen-fixture clean [dir]     turn them back on, unregister them, delete dir
//   specimen-fixture status [dir]    show whether each face is registered and on
//
// Specimen itself registers them (session scope) when launched with SPECIMEN_TEST_FONTS=dir,
// and cleans up on quit. `clean` is the safety net after a crash. Nothing else is touched.

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"
let directory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "/tmp/specimen-test", isDirectory: true)
let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fixtures")

func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }

switch command {
case "install":
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for name in ["Silkscreen-Regular.ttf", "Silkscreen-Bold.ttf"] {
        let target = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: target)
    }
    print("Copied the test font (Silkscreen, SIL OFL) to \(directory.path).")
    print("Launch Specimen with SPECIMEN_TEST_FONTS=\(directory.path) to use it.")
case "clean":
    let urls = TestFonts.fontFiles(in: directory)
    let errors = TestFonts.cleanUp(urls)
    spin()
    errors.forEach { print("note: \($0)") }
    if directory.path.hasPrefix("/tmp/") || directory.path.hasPrefix("/private/tmp/") {
        try? FileManager.default.removeItem(at: directory)
    }
    print("Cleaned up \(urls.count) test font file(s) in \(directory.path).")
case "status":
    let enabled = Set((CTFontManagerCopyAvailablePostScriptNames() as? [String]) ?? [])
    for url in TestFonts.fontFiles(in: directory) {
        let names = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? [])
            .compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
        let scope = CTFontManagerGetScopeForURL(url as CFURL)
        for name in names {
            print("\(name): \(scope == .none ? "not registered" : "registered"), \(enabled.contains(name) ? "on" : "off")")
        }
    }
default:
    print("usage: specimen-fixture install|clean|status [dir]   (default dir /tmp/specimen-test)")
}
