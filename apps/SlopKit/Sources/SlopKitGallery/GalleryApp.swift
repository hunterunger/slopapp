import AppKit
import SlopKit
import SwiftUI

// Every SlopKit component, one page each, for design review and screenshots.
//
//   swift run --package-path apps/SlopKit SlopKitGallery
//
// For the current macOS look, build it stamped with the real SDK, as scripts/bundle.sh does:
//   swift run --package-path apps/SlopKit SlopKitGallery \
//     -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker $(xcrun --sdk macosx --show-sdk-version)
//
// Environment (for screenshots):
//   GALLERY_PAGE=corners|colour|dropzone|queue|panels|capture|permissions|settings|about|type
//   GALLERY_DEMO=panel|hud|settings|about|dropin|dropin-empty|selfsizing   opens that demo at launch
//   SLOP_APPEARANCE=light|dark                                  forces the appearance
//   GALLERY_SNAPSHOT_DIR=/tmp/x   renders every page offscreen to PNGs, light and dark, and quits
// Demo files are written to /tmp/slopkit-gallery (never anywhere else).

extension KeyboardShortcuts.Name {
    static let galleryPanel = Self("galleryPanel")
}

let galleryInfo = AppInfo(name: "SlopKit Gallery", version: "dev", build: "0",
                          tagline: "Every Slopapp component in one place.")

@main
struct GalleryApp: App {
    @NSApplicationDelegateAdaptor(SlopAppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true

    init() {
        // `swift run` binaries start as background processes; make it a normal app.
        NSApplication.shared.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { GallerySnapshots.runIfAsked() }
        }
    }

    var body: some Scene {
        Window("SlopKit Gallery", id: "gallery") {
            GalleryView()
        }
        .defaultSize(width: 860, height: 640)
        .commands { MainWindowCommands(title: "SlopKit Gallery", id: "gallery") }

        // A drop-in utility window (design system §2b) exactly as an app builds it.
        Window("Drop-in Window", id: "dropin") {
            DropInDemo()
        }
        .defaultSize(width: Metrics.utilityWindowSize.width, height: Metrics.utilityWindowSize.height)

        MenuBarExtra("Gallery", systemImage: "square.grid.2x2", isInserted: $showMenuBarIcon) {
            Text("Status line goes here")
            Button("Main Action") {}
            MenuFooter(info: galleryInfo)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SlopSettings(info: galleryInfo, isMenuBarApp: true) {
                Toggle("An app-specific option", isOn: .constant(true))
            } shortcuts: {
                ShortcutRow("Show the picker", subtitle: "Works from any app. Not set by default.", name: .galleryPanel)
            }
        }
    }
}

enum GalleryPage: String, CaseIterable, Identifiable {
    case corners, colour, dropzone, queue, panels, capture, permissions, settings, about, type
    var id: Self { self }

    var title: String {
        switch self {
        case .corners: "Corners and Spacing"
        case .colour: "Colour"
        case .dropzone: "DropZone"
        case .queue: "FileQueue"
        case .panels: "Panels and HUD"
        case .capture: "Capture Layers"
        case .permissions: "Permissions"
        case .settings: "Settings"
        case .about: "About"
        case .type: "Type"
        }
    }

    var symbol: String {
        switch self {
        case .corners: "square.on.square"
        case .colour: "paintpalette"
        case .dropzone: "arrow.down.doc"
        case .queue: "list.bullet.rectangle"
        case .panels: "rectangle.on.rectangle"
        case .capture: "plus.viewfinder"
        case .permissions: "lock.shield"
        case .settings: "gearshape"
        case .about: "info.circle"
        case .type: "textformat"
        }
    }
}

struct GalleryView: View {
    @State private var page: GalleryPage? = GalleryPage(rawValue: ProcessInfo.processInfo.environment["GALLERY_PAGE"] ?? "") ?? .corners
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    private let demo = ProcessInfo.processInfo.environment["GALLERY_DEMO"]

    var body: some View {
        NavigationSplitView {
            List(GalleryPage.allCases, selection: $page) { page in
                Label(page.title, systemImage: page.symbol)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ScrollView {
                PageView(page: page ?? .corners)
            }
            .navigationTitle((page ?? .corners).title)
        }
        .frame(minWidth: 720, minHeight: 520)
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            switch demo {
            case "panel": PickerDemo.show(at: .center) { _ in }
            case "hud": HUD.show("Copied", systemImage: "doc.on.doc", duration: .seconds(30))
            case "settings": openSettings()
            case "about": AboutWindow.show(info: galleryInfo)
            case "dropin", "dropin-empty": openWindow(id: "dropin")
            case "selfsizing": SelfSizingDemo.show()
            default: break
            }
        }
    }
}

/// A titled group on a page.
struct Demo<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.headline)
                if let note {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
    }
}

// MARK: Pages

struct CornersPage: View {
    private let tokens: [(String, CGFloat)] = [
        ("xs", Radius.xs), ("s", Radius.s), ("m", Radius.m), ("l", Radius.l), ("xl", Radius.xl), ("xxl", Radius.xxl),
    ]

    var body: some View {
        Demo(title: "Radius", note: "Corner tokens. Never write a radius as a number.") {
            HStack(spacing: Spacing.m) {
                ForEach(tokens, id: \.0) { name, radius in
                    VStack(spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 64, height: 64)
                        Text("\(name) \(Int(radius))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Demo(title: "Nested corners",
             note: "A shape inset p inside a container of radius R has radius R − p: Radius.nested(in: R, padding: p).") {
            HStack(alignment: .top, spacing: Spacing.l) {
                nested(outer: Radius.xl, padding: Spacing.s)
                nested(outer: Radius.xl, padding: Spacing.xs)
                nested(outer: Radius.xxl, padding: Spacing.m)
            }
        }
        Demo(title: "Spacing", note: "4 pt grid: xs 4, s 8, m 12, l 16, xl 20, xxl 24. Window margins 20.") {
            HStack(alignment: .bottom, spacing: Spacing.m) {
                ForEach([("xs", Spacing.xs), ("s", Spacing.s), ("m", Spacing.m), ("l", Spacing.l), ("xl", Spacing.xl), ("xxl", Spacing.xxl)], id: \.0) { name, value in
                    VStack(spacing: Spacing.xs) {
                        Rectangle().fill(Color.accentColor).frame(width: value, height: value)
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Demo(title: "Icon tile", note: "App-icon-like squares: Radius.iconTile(side:).") {
            HStack(alignment: .bottom, spacing: Spacing.m) {
                ForEach([32.0, 48, 64], id: \.self) { side in
                    RoundedRectangle(cornerRadius: Radius.iconTile(side: side), style: .continuous)
                        .fill(.quaternary)
                        .frame(width: side, height: side)
                }
            }
        }
    }

    private func nested(outer: CGFloat, padding: CGFloat) -> some View {
        VStack(spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: Radius.nested(in: outer, padding: padding), style: .continuous)
                .fill(Color.accentColor.opacity(0.25))
                .frame(width: 96, height: 64)
                .padding(padding)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: outer, style: .continuous))
            Text("R \(Int(outer)), p \(Int(padding)) → \(Int(Radius.nested(in: outer, padding: padding)))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct ColourPage: View {
    var body: some View {
        Demo(title: "Readable text colours",
             note: "Hue kept, darkened (light mode) or lightened (dark mode) only as much as 4.5:1 needs.") {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("−74% saved").foregroundStyle(.textGreen)
                Text("Couldn't read photo.heic.").foregroundStyle(.textOrange)
                Text("Disk is full.").foregroundStyle(.textRed)
                Text("= 42.5 kg").foregroundStyle(.textAccent)
                Text("Highlighter yellow as text").foregroundStyle(.readable(.systemYellow))
                Text("Yellow as a symbol (3:1)").foregroundStyle(.readable(.systemYellow, target: ReadableColor.symbolTarget))
            }
            .font(.body.weight(.medium))
        }
        Demo(title: "Active and inactive windows",
             note: "Selections and accent marks go grey when the window isn't key, like Finder and Mail.") {
            HStack(alignment: .top, spacing: Spacing.l) {
                WindowStateSample(label: "This window")
                WindowStateSample(label: "Active").environment(\.controlActiveState, .key)
                WindowStateSample(label: "Inactive").environment(\.controlActiveState, .inactive)
            }
        }
    }
}

/// windowAccent, selectionTint, selectionFill and selectionRing for one window state.
struct WindowStateSample: View {
    let label: String
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Spacing.s) {
                Image(systemName: "star.fill").foregroundStyle(Color.windowAccent(activeState))
                Text("Selected row")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(Color.selectionTint(activeState), in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(Color.selectionRing(activeState), lineWidth: 2))
            Text("Aa")
                .font(.title3)
                .foregroundStyle(activeState.isActiveWindow ? Color(nsColor: .alternateSelectedControlTextColor) : .primary)
                .frame(width: 44, height: 44)
                .background(Color.selectionFill(activeState), in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        }
        .frame(width: 150, alignment: .leading)
    }
}

struct DropZonePage: View {
    @State private var dropped: [URL] = []

    var body: some View {
        Demo(title: "DropZone", note: "The empty state of a drop-in window. Click, Space or Return opens a chooser.") {
            DropZone("Drop images here", systemImage: "photo.on.rectangle.angled", types: [.image]) {
                dropped = $0
            }
            .frame(height: 220)
            Text(dropped.isEmpty ? "Nothing dropped yet." : dropped.map(\.lastPathComponent).joined(separator: ", "))
                .font(.callout).foregroundStyle(.secondary)
        }
        Demo(title: "Inside a card", note: ".dropZoneCornerRadius(Radius.nested(in: Radius.xl, padding: Spacing.s))") {
            DropZone("Drop a file here", allowsMultiple: false) { dropped = $0 }
                .dropZoneCornerRadius(Radius.nested(in: Radius.xl, padding: Spacing.s))
                .frame(height: 160)
                .padding(Spacing.s)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }
}

struct QueuePage: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Demo(title: "Drop-in window",
             note: "FileQueueView fills the window: a drop zone when empty, then a row per file with a drop strip under it.") {
            HStack(spacing: Spacing.s) {
                Button("Open Empty Window") {
                    DemoQueue.shared.clear()
                    openWindow(id: "dropin")
                }
                Button("Open With Demo Files") {
                    DemoQueue.shared.fill()
                    openWindow(id: "dropin")
                }
            }
        }
        Demo(title: "Row states", note: "Waiting, working, finished (smaller, unchanged), failed and canceled, plus a long name.") {
            Text("Open the window with demo files to see them.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct DropInDemo: View {
    @State private var model = DemoQueue.shared

    var body: some View {
        FileQueueView(queue: model.queue, selection: $model.selection, dropTitle: "Drop any files here")
            .fileQueueFollowsNewFiles()
            .frame(minWidth: 420, minHeight: 300)
            .task {
                if ProcessInfo.processInfo.environment["GALLERY_DEMO"] == "dropin", model.queue.items.isEmpty {
                    model.fill()
                }
            }
    }
}

struct PanelsPage: View {
    @State private var picked: String?

    var body: some View {
        Demo(title: "FloatingPanel", note: "Non-activating. Arrows move, 1–9 pick, Return confirms, Esc or a click outside closes.") {
            HStack(spacing: Spacing.s) {
                Button("Near Mouse") { PickerDemo.show(at: .nearMouse) { picked = $0 } }
                Button("Centered") { PickerDemo.show(at: .center) { picked = $0 } }
                Button("Corner") { PickerDemo.show(at: .corner(.bottomTrailing)) { picked = $0 } }
            }
            Text(picked.map { "Picked \($0)." } ?? "Nothing picked yet.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Demo(title: "HUD", note: "A small confirmation that fades by itself. Never an alert.") {
            HStack(spacing: Spacing.s) {
                Button("Show HUD") { HUD.show("Copied", systemImage: "doc.on.doc") }
                Button("Long Message") { HUD.show("Saved 14 files to Downloads", systemImage: "checkmark.circle") }
            }
        }
    }
}

struct CapturePage: View {
    var body: some View {
        Demo(title: "BadgeLayer and LoupeLayer",
             note: "Core Animation pieces of RegionOverlay: the size readout and the magnifier, over a test pattern.") {
            CaptureLayersDemo()
                .frame(width: 360, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
    }
}

struct PermissionsPage: View {
    var body: some View {
        Demo(title: "Status") {
            HStack(spacing: Spacing.l) {
                ForEach(Permission.allCases) { permission in
                    Label {
                        Text(permission.title)
                    } icon: {
                        // Colour on the symbol only: green text fails contrast in light mode.
                        Image(systemName: permission.isGranted ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(permission.isGranted ? .green : .secondary)
                    }
                    .font(.callout)
                }
            }
        }
        Demo(title: "PermissionPrompt", note: "What PermissionGate shows until the permission is granted.") {
            PermissionPrompt(permission: .accessibility,
                             reason: "Tiles moves and resizes windows for you. It can't read what's in them.")
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
    }
}

struct SettingsPage: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Demo(title: "SlopSettings", note: "General, Shortcuts, Advanced (if any) and About tabs at 480 pt.") {
            Button("Open Settings…") { openSettings() }
        }
        Demo(title: "Rows") {
            Form {
                ShortcutRow("Show the picker", subtitle: "Works from any app. Not set by default.", name: .galleryPanel)
                LaunchAtLoginToggle()
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: Metrics.settingsWidth, height: 150)
        }
    }
}

struct AboutPage: View {
    var body: some View {
        Demo(title: "AboutView", note: "Also in the About tab of Settings, and in its own window from a menu bar menu.") {
            Button("Show About Window") { AboutWindow.show(info: galleryInfo) }
            AboutView(info: galleryInfo)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
    }
}

struct TypePage: View {
    var body: some View {
        Demo(title: "Text styles") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Title 2").font(.title2.bold())
                Text("Headline").font(.headline)
                Text("Body text in sentence case. Buttons are verbs.")
                Text("Callout, secondary").font(.callout).foregroundStyle(.secondary)
                Text("Caption, secondary").font(.caption).foregroundStyle(.secondary)
                Text("4.2 MB → 1.1 MB  −74%").font(.body.monospacedDigit())
            }
        }
    }
}

// MARK: FloatingPanel demo

/// A Switchboard-style chooser: number keys pick, arrows move, Return confirms, Esc closes.
@MainActor
enum PickerDemo {
    static let options = ["Safari", "Firefox", "Chrome", "Arc"]
    private static var panel: FloatingPanel?

    static func show(at placement: PanelPlacement, onPick: @escaping (String) -> Void) {
        let model = PickerModel(options: options)
        let panel = FloatingPanel { PickerList(model: model) }
        func pick(_ index: Int) {
            guard options.indices.contains(index) else { return }
            onPick(options[index])
            panel.dismiss()
        }
        model.onPick = pick
        panel.keyHandler = { event in
            if let digit = event.digit { pick(digit - 1); return true }
            switch event.keyCode {
            case 125: model.move(1); return true      // down
            case 126: model.move(-1); return true     // up
            case 36, 76: pick(model.selection); return true // return, enter
            default: return false
            }
        }
        self.panel = panel
        panel.show(at: placement)
    }
}

@MainActor
@Observable
final class PickerModel {
    let options: [String]
    var selection = 0
    var onPick: (Int) -> Void = { _ in }

    init(options: [String]) { self.options = options }

    func move(_ delta: Int) {
        selection = (selection + delta + options.count) % options.count
    }
}

/// The reference for panel content: padding `Spacing.s` all round, and selection pills
/// concentric with the panel (`Radius.nested(in: panelRadius, padding: Spacing.s)`).
struct PickerList: View {
    let model: PickerModel
    @Environment(\.floatingPanelCornerRadius) private var panelRadius

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Open link with")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
            ForEach(Array(model.options.enumerated()), id: \.offset) { index, name in
                Button { model.onPick(index) } label: {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "globe")
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 20)
                        Text(name)
                        Spacer(minLength: Spacing.xl)
                        Text("\(index + 1)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.nested(in: panelRadius, padding: Spacing.s), style: .continuous)
                            .fill(index == model.selection ? Color.accentColor.opacity(0.2) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.s)
        .frame(width: 240)
    }
}

// MARK: Capture layers demo

struct CaptureLayersDemo: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let root = view.layer, let image = Self.testPattern(scale: scale) else { return view }
        root.contents = image
        root.contentsGravity = .resize

        let badge = BadgeLayer()
        badge.setScale(scale)
        badge.text = "1280 × 720"
        badge.frame = CGRect(origin: CGPoint(x: Spacing.l, y: Spacing.l), size: badge.preferredFrameSize())
        root.addSublayer(badge)

        let loupe = LoupeLayer()
        loupe.setScale(scale)
        loupe.show(image: image, centerPixel: CGPoint(x: 260 * scale, y: 80 * scale), pointLabel: "260, 80")
        let size = loupe.preferredFrameSize()
        loupe.frame = CGRect(x: 360 - size.width - Spacing.l, y: 220 - size.height - Spacing.l, width: size.width, height: size.height)
        root.addSublayer(loupe)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Stripes in system colours (no hex), so the magnifier has pixels to show.
    static func testPattern(scale: CGFloat) -> CGImage? {
        let width = Int(360 * scale), height = Int(220 * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors: [NSColor] = [.systemBlue, .systemTeal, .systemGreen, .systemYellow, .systemOrange, .systemPink, .systemPurple]
        let stripe = max(1, width / colors.count)
        for (index, color) in colors.enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: index * stripe, y: 0, width: stripe + 1, height: height))
        }
        context.setFillColor(NSColor.white.cgColor)
        for x in stride(from: 0, to: width, by: Int(12 * scale)) {
            context.fill(CGRect(x: x, y: 0, width: Int(scale), height: height))
        }
        return context.makeImage()
    }
}

// MARK: FileQueue demo

/// The drop-in window's queue, shared so the gallery page can fill or clear it.
@MainActor
@Observable
final class DemoQueue {
    static let shared = DemoQueue()
    let queue = FileQueue(processor: DemoProcessor(), acceptedTypes: [.item], maxConcurrent: 2)
    var selection = Set<FileQueueItem.ID>()

    /// Demo files: the processor decides each one's fate from its name.
    static let files: [(name: String, bytes: Int)] = [
        ("Beach at sunset.jpg", 2_400_000),
        ("Quarterly report, final version, with a name long enough to need truncating in the middle.pdf", 1_150_000),
        ("Already tiny.png", 18_000),
        ("Broken.heic", 640_000),
        ("Slow render.mov", 84_000_000),
        ("Second slow render.mov", 52_000_000),
        ("Waiting for a slot.mp4", 12_000_000),
        ("Canceled.mov", 9_000_000),
    ]

    func clear() {
        queue.remove(queue.items)
    }

    func fill() {
        clear()
        let folder = URL(fileURLWithPath: "/tmp/slopkit-gallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = Self.files.map { file -> URL in
            let url = folder.appendingPathComponent(file.name)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
                if let handle = try? FileHandle(forWritingTo: url) {
                    try? handle.truncate(atOffset: UInt64(file.bytes))
                    try? handle.close()
                }
            }
            return url
        }
        Task {
            let items = await queue.add(urls)
            if let canceled = items.first(where: { $0.name.hasPrefix("Canceled") }) { queue.cancel(canceled) }
        }
    }
}

/// A FileQueue processor that writes nothing. Names decide the outcome: "Broken" fails,
/// "tiny" is unchanged, "slow" works for a long time; everything else "shrinks" to a third.
struct DemoProcessor: FileProcessor {
    struct DemoError: LocalizedError {
        let name: String
        var errorDescription: String? { "Couldn't read \(name). It may be damaged. Try exporting it again." }
    }

    func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome {
        let name = job.input.lastPathComponent
        let steps = name.localizedCaseInsensitiveContains("slow") || name.hasPrefix("Waiting") ? 600 : 8
        for step in 1...steps {
            try await Task.sleep(for: .milliseconds(100))
            progress(Double(step) / Double(steps))
        }
        if name.hasPrefix("Broken") { throw DemoError(name: name) }
        if name.localizedCaseInsensitiveContains("tiny") { return .unchanged(reason: "Already as small as it gets") }
        let bytes = (try? job.input.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return .produced(output: job.input, bytes: bytes / 3)
    }
}

// MARK: Self-sizing window demo

/// A window that sizes itself to its content (`sizingOptions = .preferredContentSize`), as
/// `MenuBarExtra(.window)` panels are hosted, with every kind of hairline in it and content
/// that changes size every half second. A hairline whose layout size depends on the display
/// scale makes AppKit throw from its constraint pass here at launch.
@MainActor
enum SelfSizingDemo {
    private static var window: NSWindow?

    static func show() {
        guard window == nil else { window?.orderFrontRegardless(); return }
        let hosting = NSHostingController(rootView: SelfSizingPanel())
        hosting.sizingOptions = [.preferredContentSize]
        let panel = NSWindow(contentViewController: hosting)
        panel.title = "Self-Sizing Panel"
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.setFrameTopLeftPoint(NSPoint(x: 80, y: (NSScreen.main?.visibleFrame.maxY ?? 800) - 40))
        panel.orderFrontRegardless()
        window = panel
    }
}

struct SelfSizingPanel: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let rows = 1 + Int(context.date.timeIntervalSinceReferenceDate * 2) % 3
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(0..<rows, id: \.self) { row in
                    Text("Row \(row + 1)")
                    Hairline()
                }
                HStack {
                    Text("Left")
                    Hairline(axis: .vertical).frame(height: 16)
                    Text("Right")
                }
                Text("Bordered").padding(Spacing.s)
                    .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                Text("Concentric panel").padding(Spacing.s)
                    .windowConcentric(fill: .quaternary, inset: Spacing.m, hairline: Color(nsColor: .separatorColor))
            }
            .padding(Spacing.m)
            .frame(width: Metrics.menuBarWindowWidth)
        }
    }
}
