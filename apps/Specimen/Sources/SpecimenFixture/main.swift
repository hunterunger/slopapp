import CoreGraphics
import CoreText
import Foundation
import SpecimenCore

// specimen-fixture: the OFL test font for walkthroughs and blind tests.
//
//   specimen-fixture install [dir]          copy Silkscreen Regular + Bold to dir (default /tmp/specimen-test)
//   specimen-fixture library [dir] [count]  make a project-style library of renamed copies in dir/Library
//                                           (and dir/Library/Big with `count` extra fonts, default 0)
//   specimen-fixture documents [dir]        write sample documents (PDF, SVG, HTML, CSS, EPS, RTF) to dir/Documents
//   specimen-fixture clean [dir]            turn fonts back on, unregister every font file under dir, delete dir
//   specimen-fixture status [dir]           show whether each face under dir is registered and on
//
// Specimen itself registers the top-level fonts (session scope) when launched with
// SPECIMEN_TEST_FONTS=dir, and in test mode registers library fonts at session scope only.
// It cleans up on quit; `clean` is the safety net after a crash. Nothing else is touched.

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"
let directory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "/tmp/specimen-test", isDirectory: true)
let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fixtures")
let regular = fixtures.appendingPathComponent("Silkscreen-Regular.ttf")
let bold = fixtures.appendingPathComponent("Silkscreen-Bold.ttf")

func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }

/// Every font file under `folder`, recursively.
func allFontFiles(_ folder: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
    return enumerator.compactMap { $0 as? URL }.filter { LibraryPaths.isFontFile($0.path) }
}

func makeFamily(_ name: String, in folder: URL, bold withBold: Bool = true) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FixtureFonts.renamed(Data(contentsOf: regular), family: name, style: "Regular")
        .write(to: folder.appendingPathComponent("\(name.filter { !$0.isWhitespace })-Regular.ttf"))
    if withBold {
        try FixtureFonts.renamed(Data(contentsOf: bold), family: name, style: "Bold")
            .write(to: folder.appendingPathComponent("\(name.filter { !$0.isWhitespace })-Bold.ttf"))
    }
}

switch command {
case "install":
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for source in [regular, bold] {
        let target = directory.appendingPathComponent(source.lastPathComponent)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
    }
    print("Copied the test font (Silkscreen, SIL OFL) to \(directory.path).")
    print("Launch Specimen with SPECIMEN_TEST_FONTS=\(directory.path) to use it.")
case "library":
    // Renamed copies of the OFL fixture, organised by project.
    let library = directory.appendingPathComponent("Library")
    try makeFamily("Acme Sans", in: library.appendingPathComponent("Clients/Acme/Fonts"))
    try makeFamily("Acme Serif", in: library.appendingPathComponent("Clients/Acme/Fonts"), bold: false)
    try makeFamily("Beacon Mono", in: library.appendingPathComponent("Clients/Beacon"))
    try makeFamily("Archive Grotesk", in: library.appendingPathComponent("Archive 2019"))
    // The same font in two projects (v1 and v2): only one can be on.
    try makeFamily("Shared Display", in: library.appendingPathComponent("Clients/Acme/Fonts"), bold: false)
    try makeFamily("Shared Display", in: library.appendingPathComponent("Archive 2019"), bold: false)
    let count = arguments.count > 2 ? Int(arguments[2]) ?? 0 : 0
    if count > 0 {
        let big = library.appendingPathComponent("Big")
        let data = try Data(contentsOf: regular)
        for index in 1...count {
            let folder = big.appendingPathComponent("Project \(index % 40)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FixtureFonts.renamed(data, family: "Bulk \(index)").write(to: folder.appendingPathComponent("Bulk\(index)-Regular.ttf"))
        }
    }
    print("Made a test library in \(library.path) (\(allFontFiles(library).count) font files).")
case "documents":
    let folder = directory.appendingPathComponent("Documents")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    // A PDF set in two library fonts (loaded from their files; nothing is registered).
    let acme = directory.appendingPathComponent("Library/Clients/Acme/Fonts/AcmeSans-Bold.ttf")
    let pdf = folder.appendingPathComponent("Acme Poster.pdf")
    var box = CGRect(x: 0, y: 0, width: 400, height: 300)
    if let context = CGContext(pdf as CFURL, mediaBox: &box, nil) {
        context.beginPDFPage(nil)
        var y: CGFloat = 220
        for (path, name) in [(acme.path, "AcmeSans-Bold"), (acme.deletingLastPathComponent().appendingPathComponent("AcmeSerif-Regular.ttf").path, "AcmeSerif-Regular")] {
            if let font = FontLoader.makeFont(postScriptName: name, path: path, isEnabled: false, size: 28) {
                context.textPosition = CGPoint(x: 20, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Acme \(name)", attributes: [.init(kCTFontAttributeName as String): font])), context)
                y -= 60
            }
        }
        let helvetica = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        context.textPosition = CGPoint(x: 20, y: 60)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Set in Helvetica", attributes: [.init(kCTFontAttributeName as String): helvetica])), context)
        context.endPDFPage()
        context.closePDF()
    }
    try """
    <svg xmlns="http://www.w3.org/2000/svg" width="200" height="80"><style>.title { font-family: "Beacon Mono", monospace; }</style>
    <text class="title" x="10" y="30">Beacon</text><text font-family="Missing Grotesk, sans-serif" x="10" y="60">Missing</text></svg>
    """.write(to: folder.appendingPathComponent("Beacon Logo.svg"), atomically: true, encoding: .utf8)
    try "body { font-family: 'Archive Grotesk', Helvetica, sans-serif; } h1 { font: bold 2rem/1.1 \"Shared Display\", serif; }\n"
        .write(to: folder.appendingPathComponent("site.css"), atomically: true, encoding: .utf8)
    try """
    <html><head><link rel="stylesheet" href="site.css"><style>@font-face { font-family: "Web Only"; src: url(web.woff2); }</style></head>
    <body><p style="font-family: 'Web Only', Georgia">Hello</p></body></html>
    """.write(to: folder.appendingPathComponent("Microsite.html"), atomically: true, encoding: .utf8)
    try "%!PS-Adobe-3.0 EPSF-3.0\n%%DocumentNeededResources: font AcmeSans-Regular\n%%+ font Helvetica-Bold\n%%EndComments\n"
        .write(to: folder.appendingPathComponent("Badge.eps"), atomically: true, encoding: .utf8)
    try #"{\rtf1\ansi{\fonttbl\f0\fnil AcmeSerif-Regular;\f1\fswiss Helvetica;}\f0 Letter}"#
        .write(to: folder.appendingPathComponent("Letter.rtf"), atomically: true, encoding: .utf8)
    print("Wrote sample documents to \(folder.path).")
case "clean":
    let top = TestFonts.fontFiles(in: directory)
    var errors = TestFonts.cleanUp(top)
    // Library fonts Specimen registered in test mode (session scope), anywhere below.
    let nested = allFontFiles(directory).filter { CTFontManagerGetScopeForURL($0 as CFURL) != .none }
    errors += TestFonts.cleanUp(nested)
    spin()
    errors.forEach { print("note: \($0)") }
    if directory.path.hasPrefix("/tmp/") || directory.path.hasPrefix("/private/tmp/") {
        try? FileManager.default.removeItem(at: directory)
    }
    print("Cleaned up \(top.count + nested.count) test font file(s) in \(directory.path).")
case "status":
    let enabled = Set((CTFontManagerCopyAvailablePostScriptNames() as? [String]) ?? [])
    var registered = 0
    for url in allFontFiles(directory) {
        let names = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? [])
            .compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
        let scope = CTFontManagerGetScopeForURL(url as CFURL)
        if scope != .none { registered += 1 }
        let scopeName = scope == .none ? "not registered" : scope == .session ? "registered (session)" : scope == .persistent ? "REGISTERED PERSISTENTLY" : "registered"
        for name in names where scope != .none || arguments.contains("--all") {
            print("\(name): \(scopeName), \(enabled.contains(name) ? "on" : "off")  \(url.path)")
        }
    }
    print("\(registered) file(s) registered under \(directory.path). (--all lists unregistered ones too.)")
default:
    print("usage: specimen-fixture install|library|documents|clean|status [dir]   (default dir /tmp/specimen-test)")
}
