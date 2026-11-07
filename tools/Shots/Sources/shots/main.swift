// shots: helper for scripts/shots.sh (docs/screenshots.md). Not meant to be run by hand,
// but every command is safe to try:
//
//   shots plan <showcase.json>                     validate; one line per shot: id, scene, size
//   shots env <showcase.json> <data dir>           the scenes' extra environment, KEY=VALUE lines
//   shots ids <ready.json>                         "id kind" per window to capture (exit 2 + message on a scene error)
//   shots gate                                     exit 1 unless the display is awake, unlocked and Retina
//   shots backdrop [--showcase F] [--category C] --appearance A [--ready F]
//                                                  full-screen backdrop window of our own on the
//                                                  primary screen, behind the app; runs until killed
//   shots compose --showcase F --shot ID --ready R --captures DIR [--category C] --appearance A
//                 [--menubar true|false] --out PNG
//   shots manifest --slug S --app-version V --showcase F --dir D   write D/manifest.json
//   shots capture --ready R --backdrop ID --dir D  each window composited over our backdrop (see Capture.swift)
//
// The backdrop is the app's icon tile colour (apps/<Name>/Icon.py beside --showcase); --category
// is the fallback for apps without an icon spec. --brand <brand.json> overrides the palette file
// (default: brand/brand.json from the repo root).
import AppKit
import ShotsCore

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func required(_ name: String) throws -> String {
    guard let value = option(name) else { throw Failure("missing \(name)") }
    return value
}

func positional(_ index: Int) throws -> String {
    let values = arguments.dropFirst().filter { !$0.hasPrefix("--") }
    guard index < values.count else { throw Failure("missing argument \(index + 1)") }
    return Array(values)[index]
}

var repoRoot: URL {
    if let root = ProcessInfo.processInfo.environment["SLOPAPP_ROOT"] { return URL(fileURLWithPath: root) }
    // tools/Shots/.build/<config>/shots → repo root
    return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
}

/// The backdrop for one appearance: the app's icon tile colour (from apps/<Name>/Icon.py, next to
/// its showcase.json) as a wash over birch or night. Without --showcase (or an icon spec), the
/// category's Nordic colour.
@MainActor func palette() throws -> BackdropPalette {
    let brand = option("--brand").map { URL(fileURLWithPath: $0) } ?? repoRoot.appendingPathComponent("brand/brand.json")
    let nordic = try Nordic.load(brand: brand)
    let appDirectory = option("--showcase").map { URL(fileURLWithPath: $0).standardizedFileURL.deletingLastPathComponent() }
    let tile = try appDirectory.flatMap { Nordic.appTile(appDirectory: $0, repoRoot: repoRoot) }
        ?? nordic.colour(forCategory: option("--category") ?? "")
    let appearance = try required("--appearance")
    guard ["light", "dark"].contains(appearance) else { throw Failure("--appearance must be light or dark") }
    return BackdropPalette(tile: tile, nordic: nordic, dark: appearance == "dark")
}

@MainActor func run() throws {
    guard let command = arguments.first else { throw Failure("usage: see the top of tools/Shots/Sources/shots/main.swift") }
    switch command {
    case "plan":
        let file = try ShowcaseFile.load(URL(fileURLWithPath: try positional(0)))
        for shot in file.shots {
            print([shot.id, shot.sceneName, shot.size ?? "-"].joined(separator: "\t"))
        }

    case "env":
        let file = try ShowcaseFile.load(URL(fileURLWithPath: try positional(0)))
        for (key, value) in file.environment(data: try positional(1)).sorted(by: { $0.key < $1.key }) {
            guard key.range(of: "^[A-Z_][A-Z0-9_]*$", options: .regularExpression) != nil else {
                throw Failure("showcase.json env key \"\(key)\" isn't an environment variable name")
            }
            print("\(key)=\(value)")
        }

    case "ids":
        let ready = try ReadyFile.load(URL(fileURLWithPath: try positional(0)))
        if let error = ready.error {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(2)
        }
        // "<id> <kind> [image]": status items come as an image the app drew (macOS draws the
        // real ones itself, outside the app's windows).
        for window in ready.windows { print("\(window.id) \(window.kind.rawValue) \(window.image ?? "")") }

    case "gate":
        var problems: [String] = []
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        if (session["CGSSessionScreenIsLocked"] as? Bool) == true { problems.append("the screen is locked") }
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { problems.append("the display is asleep") }
        if let screen = NSScreen.screens.first, screen.backingScaleFactor < 2 {
            problems.append("the primary display isn't Retina (scale \(screen.backingScaleFactor)); shots need 2x captures")
        }
        if problems.isEmpty {
            print("ok")
        } else {
            print(problems.joined(separator: "; "))
            exit(1)
        }

    case "backdrop":
        try Backdrop.run(palette: try palette(), ready: option("--ready").map { URL(fileURLWithPath: $0) })

    case "compose":
        let file = try ShowcaseFile.load(URL(fileURLWithPath: try required("--showcase")))
        let id = try required("--shot")
        guard let shot = file.shots.first(where: { $0.id == id }) else { throw Failure("no shot \(id) in showcase.json") }
        let ready = try ReadyFile.load(URL(fileURLWithPath: try required("--ready")))
        let captures = URL(fileURLWithPath: try required("--captures"))
        var images: [UInt32: CGImage] = [:]
        for window in ready.windows {
            let url = captures.appendingPathComponent("\(window.id).png")
            guard let image = Render.loadImage(url) else {
                if window.kind == .statusItem { continue } // the strip still works without the icon
                throw Failure("missing capture \(url.path)")
            }
            images[window.id] = image
        }
        let composition = Composition.layout(ready: ready, shot: shot, menuBar: option("--menubar") == "true")
        guard let image = Render.compose(composition, captures: images, palette: try palette()) else {
            throw Failure("couldn't compose \(id)")
        }
        try Render.writePNG(image, to: URL(fileURLWithPath: try required("--out")))
        print(String(format: "composed %@ (zoom %.2f)", id, composition.zoom))

    case "manifest":
        let file = try ShowcaseFile.load(URL(fileURLWithPath: try required("--showcase")))
        let dir = URL(fileURLWithPath: try required("--dir"))
        let entries = file.shots.map { ShotManifest.Entry(id: $0.id, width: 2880, height: 1800) }
        for entry in entries {
            for name in [entry.light, entry.dark, entry.light1x, entry.dark1x]
            where !FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
                throw Failure("missing \(name) in \(dir.path)")
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let manifest = ShotManifest(slug: try required("--slug"), appVersion: try required("--app-version"),
                                    showcaseVersion: file.version, date: formatter.string(from: Date()), shots: entries)
        try manifest.encoded().write(to: dir.appendingPathComponent("manifest.json"))
        print("manifest: \(entries.count) shots")

    default:
        throw Failure("unknown command \(command)")
    }
}

do {
    if arguments.first == "capture" {
        try await Capture.run(ready: try ReadyFile.load(URL(fileURLWithPath: try required("--ready"))),
                              backdrop: UInt32(try required("--backdrop")) ?? 0,
                              directory: URL(fileURLWithPath: try required("--dir")))
    } else {
        try run()
    }
} catch {
    FileHandle.standardError.write(Data("shots: \(error)\n".utf8))
    exit(1)
}
