import AppKit
import Foundation
import Testing
@testable import IconsmithCore

/// Opt-in: renders every template with the fixture pictures and the real system folder into
/// one PNG, for looking at the templates by eye.
/// `ICONSMITH_CONTACT_SHEET=/tmp/iconsmith-test/sheet.png swift test --filter contactSheet`
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["ICONSMITH_CONTACT_SHEET"] != nil))
func contactSheet() throws {
    let out = try #require(ProcessInfo.processInfo.environment["ICONSMITH_CONTACT_SHEET"])
    #expect(out.hasPrefix("/tmp/iconsmith-test/"))
    let art = FolderArt.system()
    let pictures = URL(fileURLWithPath: "/tmp/iconsmith-test/pictures")
    var sources = try ["logo.png", "landscape.jpg", "mark.svg"].map { try SourceLoader.load(pictures.appending(path: $0)) }
    sources.append(IconSource.blank()!)
    var styles: [IconStyle] = IconShape.allCases.map { IconStyle(shape: $0, fill: true) }
    styles.append(IconStyle(shape: .folder, background: .color, color: RGBA(0.95, 0.3, 0.3)))
    styles.append(IconStyle(shape: .folderSymbol, background: .color, color: RGBA(0.3, 0.75, 0.4)))
    styles.append(IconStyle(shape: .folderCover, background: .color, color: RGBA(0.15, 0.15, 0.17)))
    var text = IconStyle(shape: .folder)
    text.text = IconText(string: "LOL 😆")
    styles.append(text)
    var badge = IconStyle(shape: .macOSApp)
    badge.text = IconText(string: "β", position: .badge)
    styles.append(badge)
    let cell = 160
    let context = Bitmap.context(width: cell * styles.count, height: cell * sources.count)!
    context.setFillColor(CGColor(gray: 0.93, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: cell * styles.count, height: cell * sources.count))
    for (row, source) in sources.enumerated() {
        let renderer = IconRenderer(source: source, folder: art)
        for (column, style) in styles.enumerated() {
            var s = style
            s.fill = !source.edges.isTransparent
            let image = try #require(renderer.render(s, pixels: cell))
            context.draw(image, in: CGRect(x: column * cell, y: (sources.count - 1 - row) * cell, width: cell, height: cell))
        }
    }
    try Bitmap.pngData(context.makeImage()!)!.write(to: URL(fileURLWithPath: out))
}
