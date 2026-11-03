import AppKit
import ApplicationServices

/// Where in an app an element lives. Refs record their scope plus the child-index path.
enum Scope: String, Codable, CaseIterable {
    case windows   // the app's windows (AXWindows), front to back
    case extras    // the app's status item(s) in the menu bar (MenuBarExtra), incl. open menus
    case menu      // the app's main menu bar (File, Edit, ...)

    func roots(of app: AXUIElement) -> [AXUIElement] {
        switch self {
        case .windows: app.elements(kAXWindowsAttribute)
        case .extras: app.element(kAXExtrasMenuBarAttribute).map { [$0] } ?? []
        case .menu: app.element(kAXMenuBarAttribute).map { [$0] } ?? []
        }
    }
}

struct Ref: Codable {
    let scope: Scope
    let path: [Int]       // path[0] indexes Scope.roots; the rest index AXChildren
    let roles: [String]   // role at each step, to detect a changed UI
    let label: String?
}

struct RefFile: Codable {
    let pid: Int32
    var refs: [String: Ref]
}

enum RefStore {
    static let dir = URL(fileURLWithPath: "/tmp/slopdrive")

    static func url(_ pid: pid_t) -> URL { dir.appendingPathComponent("refs-\(pid).json") }

    static func save(_ file: RefFile) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: url(file.pid)) }
    }

    static func load(_ pid: pid_t) -> RefFile? {
        guard let data = try? Data(contentsOf: url(pid)) else { return nil }
        return try? JSONDecoder().decode(RefFile.self, from: data)
    }
}

/// Depth-first walk with a node budget. `visit` returns false to skip an element's children.
struct Walker {
    var maxDepth = 40
    var maxNodes = 1500
    private(set) var visited = 0
    private(set) var truncated = false

    mutating func walk(
        _ element: AXUIElement, path: [Int], roles: [String], depth: Int,
        _ visit: (Node, [Int], [String], Int) -> Bool
    ) {
        guard visited < maxNodes else { truncated = true; return }
        visited += 1
        let node = Node(element)
        let roles = roles + [node.role]
        guard visit(node, path, roles, depth), depth < maxDepth else { return }
        for (i, child) in node.children.enumerated() {
            walk(child, path: path + [i], roles: roles, depth: depth + 1, visit)
        }
    }
}

struct TreePrinter {
    var maxDepth: Int
    var showFrames = true

    struct Root {
        let scope: Scope
        let path: [Int]
        let roles: [String]   // roles above this element (empty for scope roots)
        let element: AXUIElement
    }

    static func roots(of app: AXUIElement, scopes: [Scope], windows: [Int]? = nil) -> [Root] {
        scopes.flatMap { scope in
            scope.roots(of: app).enumerated().compactMap { i, el in
                if scope == .windows, let windows, !windows.contains(i) { return nil }
                return Root(scope: scope, path: [i], roles: [], element: el)
            }
        }
    }

    /// Prints each root's tree and stores refs (e1, e2, ...) for the printed nodes.
    /// Returns how many nodes were printed.
    @discardableResult
    func print(pid: pid_t, roots: [Root], extend: Bool = false) -> Int {
        // A subtree (`tree <app> <ref>`) adds refs after the existing ones instead of renumbering.
        var refs: [String: Ref] = extend ? (RefStore.load(pid)?.refs ?? [:]) : [:]
        var counter = refs.keys.compactMap { Int($0.dropFirst()) }.max() ?? 0
        var walker = Walker(maxDepth: maxDepth)
        let controls: Set<String> = [kAXCheckBoxRole, kAXPopUpButtonRole, kAXSliderRole, kAXTextFieldRole,
                                     kAXRadioButtonRole, kAXButtonRole, kAXComboBoxRole, kAXTextAreaRole, "AXSwitch"]
        for root in roots {
            // Unlabeled layout containers are skipped and don't add indentation.
            var indentAt: [Int: Int] = [:]   // path length -> indentation
            var lastText: [[Int]: String] = [:]   // parent path -> latest static text seen under it
            let base = root.path.count
            walker.walk(root.element, path: root.path, roles: root.roles, depth: 0) { node, path, roles, depth in
                let parentIndent = indentAt[path.count - 1] ?? -1
                if node.isNoise && depth > 0 {
                    indentAt[path.count] = parentIndent
                    return true
                }
                let indent = path.count == base ? 0 : parentIndent + 1
                indentAt[path.count] = indent
                counter += 1
                let ref = "e\(counter)"
                refs[ref] = Ref(scope: root.scope, path: path, roles: roles, label: node.label)
                var line = node.line(showFrame: showFrames)
                let parent = Array(path.dropLast())
                if node.role == kAXStaticTextRole, let text = node.label {
                    lastText[parent] = text
                } else if node.label == nil, controls.contains(node.role), node.subrole == nil || node.role != kAXButtonRole {
                    // No accessible name: VoiceOver can't read it either. Hint at the visible label.
                    line += lastText[parent].map { " [unlabeled, near \(quote($0, limit: 40))]" } ?? " [unlabeled]"
                }
                Swift.print(String(repeating: "  ", count: indent) + ref + " " + line)
                return true
            }
        }
        if walker.truncated {
            Swift.print("… stopped after \(walker.visited) elements. Narrow it: --window N, --depth N, or `tree <app> <ref>`.")
        }
        RefStore.save(RefFile(pid: pid, refs: refs))
        return counter
    }
}

enum Finder {
    /// Resolves a stored ref, re-finding the element by role and label if the UI shifted.
    static func resolve(_ name: String, app: AXUIElement, pid: pid_t) throws -> AXUIElement {
        guard let file = RefStore.load(pid), file.pid == pid else {
            throw DriveError("no refs saved for this app (pid \(pid)). Run `tree` first.")
        }
        guard let ref = file.refs[name] else {
            throw DriveError("unknown ref \(name). Refs come from the latest `tree` of this app; run it again.")
        }
        let roots = ref.scope.roots(of: app)
        if let first = ref.path.first, first < roots.count {
            var el = roots[first]
            var ok = Node(el).role == ref.roles.first
            for (step, index) in ref.path.dropFirst().enumerated() where ok {
                let kids = el.elements(kAXChildrenAttribute)
                guard index < kids.count else { ok = false; break }
                el = kids[index]
                ok = Node(el).role == ref.roles[step + 1]
            }
            if ok, Node(el).label == ref.label { return el }
        }
        // The UI changed since `tree`: look for the same role + label in the same scope.
        let role = ref.roles.last ?? ""
        var matches: [AXUIElement] = []
        var walker = Walker()
        for (i, root) in roots.enumerated() {
            walker.walk(root, path: [i], roles: [], depth: 0) { node, _, _, _ in
                if node.role == role && node.label == ref.label { matches.append(node.element) }
                return true
            }
        }
        if matches.count == 1 { return matches[0] }
        throw DriveError("ref \(name) (\(role) \(ref.label.map { quote($0) } ?? "")) is stale; the UI changed. Run `tree` again.")
    }

    struct Match {
        let node: Node
        let score: Int
        let order: Int
    }

    /// Finds an element by visible text. Searches windows, then status-item menus, then the
    /// main menu. Exact matches beat partial ones; pressable elements beat static text.
    static func find(_ query: String, app: AXUIElement, role: String?, preferPressable: Bool,
                     scopes: [Scope] = [.windows, .extras, .menu], onScreenOnly: Bool = false) -> (Node, [Node])? {
        let q = query.lowercased()
        for scope in scopes {
            var matches: [Match] = []
            var walker = Walker()
            for (i, root) in scope.roots(of: app).enumerated() {
                walker.walk(root, path: [i], roles: [], depth: 0) { node, _, _, _ in
                    if onScreenOnly && node.role == kAXMenuRole && !node.isOnScreen { return false }
                    if let role {
                        let r = role.lowercased()
                        let names = [node.role, node.shortRole, node.subrole ?? ""]
                            .map { $0.lowercased() } + [node.subrole.map { String($0.dropFirst(2)).lowercased() } ?? ""]
                        if !names.contains(r) && !names.contains("ax" + r) && !node.shortRole.lowercased().hasPrefix(r) { return true }
                    }
                    let texts = node.searchableText.map { $0.lowercased() }
                    var score = 0
                    if node.label?.lowercased() == q { score = 3 }
                    else if texts.contains(q) { score = 2 }
                    else if texts.contains(where: { $0.contains(q) }) { score = 1 }
                    if score > 0 { matches.append(Match(node: node, score: score, order: matches.count)) }
                    return true
                }
            }
            guard !matches.isEmpty else { continue }
            let sorted = matches.sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if preferPressable {
                    let pa = a.node.isPressable, pb = b.node.isPressable
                    if pa != pb { return pa }
                }
                return a.order < b.order
            }
            return (sorted[0].node, sorted.dropFirst().map(\.node))
        }
        return nil
    }

    /// Accepts a ref (e12) or a text query.
    static func element(_ target: String, app: AXUIElement, pid: pid_t, role: String?, forAction: Bool) throws -> AXUIElement {
        if target.range(of: #"^e\d+$"#, options: .regularExpression) != nil {
            return try resolve(target, app: app, pid: pid)
        }
        guard let (node, others) = find(target, app: app, role: role, preferPressable: forAction) else {
            throw DriveError("nothing matching \(quote(target))\(role.map { " with role \($0)" } ?? "") in windows, status-item menus or the main menu. Try `tree`.")
        }
        if !others.isEmpty {
            let list = others.prefix(4).map { $0.shortRole + " " + ($0.label.map { quote($0, limit: 30) } ?? "") }
            FileHandle.standardError.write(Data("note: \(others.count) other match(es), using the first: \(node.shortRole) \(node.label.map { quote($0) } ?? ""). Others: \(list.joined(separator: ", ")). Use a ref to be exact.\n".utf8))
        }
        return node.element
    }
}

struct DriveError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
