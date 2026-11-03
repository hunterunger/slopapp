import AppKit
import ApplicationServices

let usage = """
slopdrive: drive a Mac app through Accessibility. <app> = name, bundle id, pid or .app path.

Apps
  apps [--paths]                         running GUI apps (--paths: add each bundle's path)
  launch <app> [--env K=V]... [--activate] [--fresh] [--timing] [--direct]
                                         start it (build/<Name>.app first, then /Applications)
                                         --direct: run the binary as a child of this terminal so it
                                         inherits the terminal's Accessibility / Screen Recording
                                         grants (test permission-gated features; log in /tmp/slopdrive)
  quit <app> [--force]                   quit it
  activate <app>                         bring it to the front (steals focus from the user)
  windows <app>                          numbered windows + other on-screen surfaces
  stats <app>                            CPU time and memory (footprint, RSS), wall-clock time

Reading
  tree <app> [<ref>] [--window N|title] [--menubar] [--menu] [--all] [--depth N] [--no-frames]
        default: all windows. --menubar: the app's status item and its open menu.
        --menu: main menu bar. Each line gets a ref (e1, e2...) for the commands below.
  inspect <app> <ref|text>               every attribute and action of one element
  wait <app> <text> [--timeout S] [--gone]   in windows and open status-item menus
  shot <app> [--window N|title] [-o path] PNG of the app's windows/open menus (not the rest of the screen)
  shot <app> --status-item               PNG of its menu bar icon (to check icon state)
  shot --screen [--rect x,y,w,h] [-o path]

Acting (no mouse movement, no global keys unless asked)
  click <app> <ref|text> [--role R]      AXPress, e.g. click Awake "1 Hour"
  menubar <app> [--item N]               open the app's menu bar item, print what opened
  close-menu <app>                       close an open menu
  menu <app> "File > Save"               pick a main-menu item
  set <app> <ref|text> <value>           set a field/slider/checkbox value
  focus <app> <ref|text>                 focus an element
  type <app> <text> [--activate]         type into the app (posted to its pid)
  key <app> <combo> [--activate] [--global]
        combo like cmd+shift+v, escape, down. --global posts system-wide: it goes to
        whatever is frontmost (needed for global hotkeys). Use sparingly.

Mouse (moves the real cursor; needs --allow-mouse and the target app)
  clickxy <app> <x> <y> --allow-mouse [--right] [--double] [--menubar] [--allow-over Owner]... [--check]
  drag <app> <x1> <y1> <x2> <y2> --allow-mouse [--allow-over Owner]... [--check]
        Refuses unless every point it clicks or passes over (start, end, and 19 samples along
        a drag) is on <app>'s own window: `activate` it first. The error names the window in
        the way. --allow-over Owner: also allow that app's windows (owner name as the error
        prints it, or bundle id), e.g. to drop onto Finder (Finder also allows the desktop).
        --menubar: the point is in the system menu bar (e.g. <app>'s status item).
        --check: only run the safety check, don't touch the mouse.
        Never acts over system permission/security prompts (UserNotificationCenter,
        CoreServicesUIAgent, SecurityAgent, universalAccessAuthWarn, System Settings, ...),
        even with --allow-over. Leave those for a human.

Refs: `tree` numbers what it prints and saves the refs per app in /tmp/slopdrive. They stay
valid until the next full `tree` of that app (`tree <app> <ref>` adds to them instead). If the UI moved, a ref is re-found by role + label;
if that fails you get "stale ref": run `tree` again.
"""

struct Args {
    var positional: [String] = []
    var values: [String: [String]] = [:]
    var flags: Set<String> = []

    static let valued: Set<String> = ["--env", "--window", "--depth", "--role", "--timeout", "-o", "--item", "--rect", "--allow-over"]

    init(_ argv: [String]) throws {
        var i = 0
        while i < argv.count {
            let a = argv[i]
            if Args.valued.contains(a) {
                guard i + 1 < argv.count else { throw DriveError("\(a) needs a value") }
                values[a, default: []].append(argv[i + 1]); i += 2; continue
            }
            if a.hasPrefix("--") { flags.insert(a) } else { positional.append(a) }
            i += 1
        }
    }

    func value(_ k: String) -> String? { values[k]?.last }
    func int(_ k: String) throws -> Int? {
        guard let v = value(k) else { return nil }
        guard let n = Int(v) else { throw DriveError("\(k) expects a number, got \(quote(v))") }
        return n
    }
    func has(_ f: String) -> Bool { flags.contains(f) }
    func arg(_ i: Int, _ name: String) throws -> String {
        guard i < positional.count else { throw DriveError("missing <\(name)>. Run `drive help`.") }
        return positional[i]
    }
}

@main
struct SlopDrive {
    static func main() async {
        let argv = Array(CommandLine.arguments.dropFirst())
        guard let command = argv.first, !["help", "-h", "--help"].contains(command) else {
            print(usage); return
        }
        do {
            let args = try Args(Array(argv.dropFirst()))
            try await run(command, args)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    static func needAX() throws {
        guard AXIsProcessTrusted() else {
            throw DriveError("this terminal has no Accessibility permission. Grant it in System Settings > Privacy & Security > Accessibility, then retry.")
        }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 3)
        // While the screen is locked, macOS reports every app as its own window and
        // hides real windows from Accessibility. Fail loudly instead of printing junk.
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        if (session["CGSSessionScreenIsLocked"] as? Bool) == true || CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            throw DriveError("the screen is locked or the display is asleep, so macOS hides windows from Accessibility. Unlock the Mac and retry. UI driving and blind tests need an unlocked, awake screen.")
        }
    }

    static func target(_ args: Args) throws -> (NSRunningApplication, AXUIElement) {
        let app = try Apps.running(try args.arg(0, "app"))
        return (app, AXUIElementCreateApplication(app.processIdentifier))
    }

    static func run(_ command: String, _ args: Args) async throws {
        switch command {
        case "apps":
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
                let active = app.isActive ? " [active]" : ""
                let path = args.has("--paths") ? "  \(app.bundleURL?.standardizedFileURL.path ?? "-")" : ""
                print("\(app.processIdentifier)  \(app.localizedName ?? "?")  \(app.bundleIdentifier ?? "-")  \(Apps.policyName(app.activationPolicy))\(active)\(path)")
            }

        case "launch":
            let url = try Apps.bundleURL(try args.arg(0, "app"))
            var env: [String: String] = [:]
            for pair in args.values["--env"] ?? [] {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { throw DriveError("--env expects K=V, got \(quote(pair))") }
                env[kv[0]] = kv[1]
            }
            let existing = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
            if !existing.isEmpty {
                if args.has("--fresh") {
                    for app in existing { _ = await Apps.quit(app, force: false) }
                } else {
                    let pid = existing[0].processIdentifier
                    print("already running: \(existing[0].localizedName ?? url.lastPathComponent) pid \(pid)\(env.isEmpty ? "" : " (--env ignored; use --fresh to relaunch)")")
                    return
                }
            }
            let launched = args.has("--direct")
                ? try await Apps.launchDirect(url, env: env)
                : try await Apps.launch(url, env: env, activate: args.has("--activate"))
            let pid = launched.app.processIdentifier
            // First on-screen surface: a window or the menu bar icon.
            var surface = "-", surfaceMs = -1
            let start = Date()
            // The menu bar icon is drawn by the system, so look for it through Accessibility.
            let ax = AXUIElementCreateApplication(pid)
            while Date().timeIntervalSince(start) < 5 {
                if ServerWindow.list(pid: pid).contains(where: { $0.layer == 0 }) {
                    surface = "window"
                } else if AXIsProcessTrusted(),
                          let bar = Scope.extras.roots(of: ax).first, !bar.elements(kAXChildrenAttribute).isEmpty {
                    surface = "status-item"
                }
                if surface != "-" {
                    surfaceMs = launched.launchMs + Int(Date().timeIntervalSince(start) * 1000)
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            if args.has("--timing") {
                print("pid=\(pid) launch_ms=\(launched.launchMs) first_surface=\(surface) first_surface_ms=\(surfaceMs)")
            } else {
                let shown = surfaceMs >= 0 ? ", first \(surface) after \(surfaceMs) ms" : ", nothing on screen yet"
                print("launched \(launched.app.localizedName ?? url.lastPathComponent) pid \(pid) in \(launched.launchMs) ms\(shown)")
            }

        case "quit":
            let (app, _) = try target(args)
            let name = app.localizedName ?? "app"
            let ok = await Apps.quit(app, force: args.has("--force"))
            print(ok ? "quit \(name)" : "\(name) is still running (try --force)")
            if !ok { exit(1) }

        case "activate":
            let (app, _) = try target(args)
            app.activate()
            print("activated \(app.localizedName ?? "app")")

        case "windows":
            try needAX()
            let (app, ax) = try target(args)
            let windows = Scope.windows.roots(of: ax).map(Node.init)
            let server = ServerWindow.list(pid: app.processIdentifier)
            if windows.isEmpty { print("no windows") }
            for (i, w) in windows.enumerated() {
                print("\(i + 1). \(w.line())")
            }
            let others = server.filter { $0.layer != 0 }
            if !others.isEmpty {
                print("other surfaces:")
                for s in others {
                    print("   \(s.kind) id \(s.id) @\(Int(s.bounds.minX)),\(Int(s.bounds.minY)) \(Int(s.bounds.width))x\(Int(s.bounds.height))")
                }
            }

        case "stats":
            let (app, _) = try target(args)
            guard let u = Usage.of(app.processIdentifier) else { throw DriveError("can't read usage for pid \(app.processIdentifier)") }
            // time_s (wall clock) lets callers turn cpu_ms deltas into a percentage.
            print(String(format: "pid=%d cpu_ms=%.1f footprint_mb=%.1f rss_mb=%.1f time_s=%.3f",
                         app.processIdentifier, Double(u.cpuNanoseconds) / 1e6,
                         Double(u.footprintBytes) / 1_048_576, Double(u.residentBytes) / 1_048_576,
                         Date().timeIntervalSince1970))

        case "tree":
            try needAX()
            let (app, ax) = try target(args)
            let pid = app.processIdentifier
            let printer = TreePrinter(maxDepth: try args.int("--depth") ?? 40, showFrames: !args.has("--no-frames"))
            var roots: [TreePrinter.Root]
            if args.positional.count > 1 {
                let refName = args.positional[1]
                let el = try Finder.resolve(refName, app: ax, pid: pid)
                guard let ref = RefStore.load(pid)?.refs[refName] else { throw DriveError("unknown ref \(refName)") }
                roots = [TreePrinter.Root(scope: ref.scope, path: ref.path, roles: Array(ref.roles.dropLast()), element: el)]
            } else if args.has("--all") {
                roots = TreePrinter.roots(of: ax, scopes: [.windows, .extras, .menu])
            } else if args.has("--menubar") {
                roots = TreePrinter.roots(of: ax, scopes: [.extras])
                if roots.isEmpty { throw DriveError("\(app.localizedName ?? "app") has no menu bar item") }
            } else if args.has("--menu") {
                roots = TreePrinter.roots(of: ax, scopes: [.menu])
            } else {
                let window = try args.value("--window").map { try windowIndex($0, ax: ax) }
                roots = TreePrinter.roots(of: ax, scopes: [.windows], windows: window.map { [$0] })
                if roots.isEmpty {
                    let hasExtras = !Scope.extras.roots(of: ax).isEmpty
                    print("no windows." + (hasExtras ? " It has a menu bar item: try `menubar \(args.positional[0])` or `tree \(args.positional[0]) --menubar`." : ""))
                    return
                }
            }
            printer.print(pid: pid, roots: roots, extend: args.positional.count > 1)

        case "inspect":
            try needAX()
            let (app, ax) = try target(args)
            let el = try Finder.element(try args.arg(1, "ref|text"), app: ax, pid: app.processIdentifier, role: args.value("--role"), forAction: false)
            let node = Node(el)
            print(node.line())
            var names: CFArray?
            AXUIElementCopyAttributeNames(el, &names)
            for name in (names as? [String] ?? []).sorted() where name != kAXChildrenAttribute {
                guard let v = el.attribute(name) else { continue }
                let cf = v as CFTypeRef
                let text: String
                if CFGetTypeID(cf) == AXUIElementGetTypeID() { text = "<element \(Node(cf as! AXUIElement).shortRole)>" }
                else if let arr = v as? [AXUIElement] { text = "<\(arr.count) elements>" }
                else { text = quote(String(describing: v), limit: 160) }
                var settable = DarwinBoolean(false)
                AXUIElementIsAttributeSettable(el, name as CFString, &settable)
                print("  \(name)\(settable.boolValue ? " (settable)" : "") = \(text)")
            }
            print("  actions: \(node.actions.joined(separator: ", "))")
            print("  children: \(node.children.count)")

        case "click":
            try needAX()
            let (app, ax) = try target(args)
            let el = try Finder.element(try args.arg(1, "ref|text"), app: ax, pid: app.processIdentifier, role: args.value("--role"), forAction: true)
            let node = Node(el)
            if node.enabled == false { throw DriveError("\(node.line(showFrame: false)) is disabled") }
            // Some apps only answer the press after their menu/tracking loop ends: don't block on it.
            AXUIElementSetMessagingTimeout(el, 1)
            var err = el.perform(kAXPressAction)
            if err == .actionUnsupported {
                // Rows, cells and text: select or focus instead.
                if el.set(kAXSelectedAttribute, kCFBooleanTrue) == .success { err = .success }
                else { err = el.set(kAXFocusedAttribute, kCFBooleanTrue) }
            }
            guard err == .success || err == .cannotComplete else { throw DriveError("couldn't press \(node.line(showFrame: false)): \(err.name)") }
            print("clicked \(node.shortRole) \(node.label.map { quote($0) } ?? "")")

        case "menubar":
            try needAX()
            let (app, ax) = try target(args)
            guard let bar = Scope.extras.roots(of: ax).first else { throw DriveError("\(app.localizedName ?? "app") has no menu bar item") }
            let items = bar.elements(kAXChildrenAttribute)
            let index = (try args.int("--item") ?? 1) - 1
            guard items.indices.contains(index) else { throw DriveError("it has \(items.count) menu bar item(s)") }
            let before = Set(ServerWindow.list(pid: app.processIdentifier).map(\.id))
            AXUIElementSetMessagingTimeout(items[index], 0.5)
            items[index].perform(kAXPressAction)
            // A menu-style item opens an AXMenu under the item; a window-style one opens a panel.
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(50))
                if items[index].elements(kAXChildrenAttribute).contains(where: { Node($0).isOnScreen }) { break }
                if !Set(ServerWindow.list(pid: app.processIdentifier).map(\.id)).subtracting(before).isEmpty { break }
            }
            let printer = TreePrinter(maxDepth: 40, showFrames: false)
            let menuOpen = items[index].elements(kAXChildrenAttribute).contains(where: { Node($0).isOnScreen })
            if menuOpen {
                printer.print(pid: app.processIdentifier, roots: TreePrinter.roots(of: ax, scopes: [.extras]))
            } else {
                let n = printer.print(pid: app.processIdentifier, roots: TreePrinter.roots(of: ax, scopes: [.windows]))
                if n == 0 { print("pressed the menu bar item, but no menu or window appeared") }
            }

        case "close-menu":
            try needAX()
            let (app, ax) = try target(args)
            var closed = 0
            for scope in [Scope.extras, .menu] {
                var walker = Walker(maxDepth: 3)
                for (i, root) in scope.roots(of: ax).enumerated() {
                    walker.walk(root, path: [i], roles: [], depth: 0) { node, _, _, _ in
                        if node.role == kAXMenuRole {
                            if node.isOnScreen {
                                AXUIElementSetMessagingTimeout(node.element, 0.5)
                                if node.element.perform(kAXCancelAction) == .success { closed += 1 }
                            }
                            return false
                        }
                        return true
                    }
                }
            }
            print(closed > 0 ? "closed \(closed) menu(s)" : "no open menu in \(app.localizedName ?? "app")")

        case "menu":
            try needAX()
            let (app, ax) = try target(args)
            let path = try args.arg(1, "\"Menu > Item\"").components(separatedBy: ">").map { $0.trimmingCharacters(in: .whitespaces) }
            guard var current = Scope.menu.roots(of: ax).first else { throw DriveError("no main menu (menu-bar-only apps have none)") }
            for (depth, title) in path.enumerated() {
                var kids = current.elements(kAXChildrenAttribute)
                // Menu bar item -> its AXMenu -> items.
                if depth > 0, kids.count == 1, Node(kids[0]).role == kAXMenuRole { kids = kids[0].elements(kAXChildrenAttribute) }
                guard let next = kids.first(where: { Node($0).title?.lowercased() == title.lowercased() })
                        ?? kids.first(where: { Node($0).title?.lowercased().hasPrefix(title.lowercased()) == true }) else {
                    let titles = kids.compactMap { Node($0).title }.prefix(30)
                    throw DriveError("no menu item \(quote(title)). Options: \(titles.joined(separator: ", "))")
                }
                current = next
            }
            AXUIElementSetMessagingTimeout(current, 1)
            let err = current.perform(kAXPressAction)
            guard err == .success || err == .cannotComplete else { throw DriveError("couldn't pick it: \(err.name)") }
            print("picked \(path.joined(separator: " > ")) in \(app.localizedName ?? "app")")

        case "set":
            try needAX()
            let (app, ax) = try target(args)
            let el = try Finder.element(try args.arg(1, "ref|text"), app: ax, pid: app.processIdentifier, role: args.value("--role"), forAction: false)
            let raw = try args.arg(2, "value")
            let node = Node(el)
            let value: CFTypeRef
            if node.value is NSNumber || [kAXCheckBoxRole, kAXSliderRole, kAXRadioButtonRole].contains(node.role) {
                let lowered = raw.lowercased()
                let n: Double = ["on", "true", "yes"].contains(lowered) ? 1 : ["off", "false", "no"].contains(lowered) ? 0 : (Double(raw) ?? .nan)
                guard !n.isNaN else { throw DriveError("\(node.shortRole) needs a number or on/off") }
                // Checkboxes usually refuse a direct value: press when it needs to change.
                if node.role == kAXCheckBoxRole, let current = node.value as? Int {
                    if (current != 0) != (n != 0) { el.perform(kAXPressAction) }
                    print("set \(node.shortRole) \(node.label.map { quote($0) } ?? "") to \(n != 0 ? "on" : "off")"); return
                }
                value = NSNumber(value: n)
            } else {
                value = raw as CFString
            }
            let err = el.set(kAXValueAttribute, value)
            guard err == .success else { throw DriveError("couldn't set the value: \(err.name)") }
            el.perform(kAXConfirmAction)   // commit, like pressing Return; ignored when unsupported
            print("set \(node.shortRole) \(node.label.map { quote($0) } ?? "") = \(quote(raw))")

        case "focus":
            try needAX()
            let (app, ax) = try target(args)
            let el = try Finder.element(try args.arg(1, "ref|text"), app: ax, pid: app.processIdentifier, role: args.value("--role"), forAction: false)
            let err = el.set(kAXFocusedAttribute, kCFBooleanTrue)
            guard err == .success else { throw DriveError("couldn't focus it: \(err.name)") }
            print("focused \(Node(el).shortRole) \(Node(el).label.map { quote($0) } ?? "")")

        case "type":
            let (app, _) = try target(args)
            if args.has("--activate") { app.activate(); try await Task.sleep(for: .milliseconds(250)) }
            Keys.type(try args.arg(1, "text"), pid: app.processIdentifier)
            print("typed \(args.positional[1].count) characters into \(app.localizedName ?? "app")")

        case "key":
            let (app, _) = try target(args)
            let (code, flags) = try Keys.parse(try args.arg(1, "combo"))
            if args.has("--activate") { app.activate(); try await Task.sleep(for: .milliseconds(250)) }
            let global = args.has("--global")
            Keys.press(code, flags: flags, pid: global ? nil : app.processIdentifier)
            print("pressed \(args.positional[1])\(global ? " system-wide" : " in \(app.localizedName ?? "app")")")

        case "wait":
            try needAX()
            let (app, ax) = try target(args)
            let text = try args.arg(1, "text")
            let timeout = Double(args.value("--timeout") ?? "10") ?? 10
            let gone = args.has("--gone")
            let start = Date()
            while Date().timeIntervalSince(start) < timeout {
                // Only what's on screen: windows and open status-item menus (the main menu is always there).
                let found = Finder.find(text, app: ax, role: nil, preferPressable: false, scopes: [.windows, .extras], onScreenOnly: true) != nil
                if found != gone {
                    print("\(gone ? "gone" : "found") \(quote(text)) after \(Int(Date().timeIntervalSince(start) * 1000)) ms"); return
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            throw DriveError("timed out after \(Int(timeout))s waiting for \(quote(text))\(gone ? " to disappear" : "") in \(app.localizedName ?? "app")")

        case "shot":
            try FileManager.default.createDirectory(at: RefStore.dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
            if args.has("--screen") {
                let out = args.value("-o") ?? "/tmp/slopdrive/screen-\(stamp).png"
                var cmd = ["-x", "-m"]
                if let rect = args.value("--rect") { cmd = ["-x", "-R", rect] }
                try capture(cmd + [out])
                print(out); return
            }
            let (app, ax) = try target(args)
            let name = (app.localizedName ?? "app").replacingOccurrences(of: " ", with: "")
            if args.has("--status-item") {
                // The system draws menu bar icons, so capture the icon's area of the screen.
                guard let item = Scope.extras.roots(of: ax).first?.elements(kAXChildrenAttribute).first,
                      let f = Node(item).frame else { throw DriveError("\(name) has no menu bar item") }
                let out = args.value("-o") ?? "/tmp/slopdrive/\(name)-status-item-\(stamp).png"
                try capture(["-x", "-R", "\(Int(f.minX) - 4),\(Int(f.minY)),\(Int(f.width) + 8),\(Int(f.height))", out])
                print("\(out)  (status item \(Int(f.width))x\(Int(f.height)))"); return
            }
            var surfaces = ServerWindow.list(pid: app.processIdentifier)
            if let spec = args.value("--window") {
                let i = try windowIndex(spec, ax: ax)
                guard let f = Node(Scope.windows.roots(of: ax)[i]).frame else { throw DriveError("window \(spec) has no frame") }
                surfaces = surfaces.filter { $0.layer == 0 && $0.bounds.integral == f.integral }
                if surfaces.isEmpty { throw DriveError("window \(spec) isn't on screen (minimized or hidden?)") }
            }
            if surfaces.isEmpty { throw DriveError("\(name) has nothing on screen. Open a window or `menubar \(args.positional[0])` first.") }
            for (i, s) in surfaces.enumerated() {
                var out = args.value("-o") ?? "/tmp/slopdrive/\(name)-\(stamp).png"
                if surfaces.count > 1 { out = out.replacingOccurrences(of: ".png", with: "-\(i + 1).png") }
                try capture(["-x", "-o", "-l\(s.id)", out])
                print("\(out)  (\(s.kind) \(Int(s.bounds.width))x\(Int(s.bounds.height))\(s.title.isEmpty ? "" : " " + quote(s.title)))")
            }

        case "clickxy", "drag":
            let isClick = command == "clickxy"
            let usageLine = isClick
                ? "usage: clickxy <app> <x> <y> --allow-mouse [--right] [--double] [--menubar] [--allow-over Owner]"
                : "usage: drag <app> <x1> <y1> <x2> <y2> --allow-mouse [--allow-over Owner]"
            guard args.has("--allow-mouse") || args.has("--check") else {
                throw DriveError("\(command) moves the user's real mouse. Prefer `click` with a ref. If you must, add --allow-mouse.")
            }
            let want = isClick ? 3 : 5
            guard args.positional.count == want else {
                throw DriveError(args.positional.count == want - 1 && Double(args.positional[0]) != nil
                    ? "\(command) now needs the target app first, so it can refuse to click anything else. \(usageLine)"
                    : usageLine)
            }
            let nums = args.positional.dropFirst().compactMap(Double.init)
            guard nums.count == want - 1 else { throw DriveError(usageLine) }
            try needAX()
            let (app, _) = try target(args)
            var policy = MouseGuard.Policy(target: app)
            policy.allowOver = Set((args.values["--allow-over"] ?? []).map { $0.lowercased() })
            policy.menuBar = args.has("--menubar")
            if policy.menuBar && !isClick { throw DriveError("--menubar is for clickxy only") }
            let start = CGPoint(x: nums[0], y: nums[1])
            let points = isClick ? [start] : Mouse.path(from: start, to: CGPoint(x: nums[2], y: nums[3]))
            let verb = isClick ? "click" : "drag"
            try MouseGuard.check(points, policy: policy, verb: verb)
            if args.has("--check") {
                print("ok: \(isClick ? "\(Int(nums[0])),\(Int(nums[1]))" : "all \(points.count) points of the path") \(isClick ? "is" : "are") on \(app.localizedName ?? "the app")\(policy.allowOver.isEmpty ? "" : " or allowed windows")")
                return
            }
            // Re-check (window server only, it's fast) right before each press and drag step.
            let recheck: (CGPoint) throws -> Void = { p in
                if let why = MouseGuard.refusal(at: p, policy: policy, accessibility: false) {
                    throw DriveError("stopped the \(verb): \(why)")
                }
            }
            let dragRecheck: (CGPoint) throws -> Void = { p in
                if let why = MouseGuard.promptRefusal(at: p, policy: policy) {
                    throw DriveError("stopped the drag: \(why)")
                }
            }
            if isClick {
                try Mouse.click(at: start, right: args.has("--right"), count: args.has("--double") ? 2 : 1, check: recheck)
                print("clicked at \(Int(nums[0])),\(Int(nums[1])) in \(app.localizedName ?? "app")")
            } else {
                try Mouse.drag(along: points, checkStart: recheck, checkStep: dragRecheck)
                print("dragged \(Int(nums[0])),\(Int(nums[1])) -> \(Int(nums[2])),\(Int(nums[3])) in \(app.localizedName ?? "app")")
            }

        default:
            throw DriveError("unknown command \(quote(command)). Run `drive help`.")
        }
    }

    /// --window takes a number (front-to-back order, as `windows` prints it; changes when focus
    /// moves) or part of a window title (stable).
    static func windowIndex(_ spec: String, ax: AXUIElement) throws -> Int {
        let windows = Scope.windows.roots(of: ax).map(Node.init)
        if let n = Int(spec) {
            guard windows.indices.contains(n - 1) else { throw DriveError("no window \(n); it has \(windows.count) (see `windows`)") }
            return n - 1
        }
        let q = spec.lowercased()
        if let i = windows.firstIndex(where: { ($0.title ?? "").lowercased() == q })
            ?? windows.firstIndex(where: { ($0.title ?? "").lowercased().contains(q) || ($0.identifier ?? "").lowercased().contains(q) }) {
            return i
        }
        throw DriveError("no window titled \(quote(spec)). Windows: \(windows.map { $0.title ?? "(untitled)" }.joined(separator: ", "))")
    }

    static func capture(_ arguments: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = arguments
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw DriveError("screencapture failed (status \(p.terminationStatus)); is Screen Recording permission granted?") }
    }
}
