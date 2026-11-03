import AppKit
import ApplicationServices

/// A snapshot of one accessibility element, fetched in a single batched IPC call.
struct Node {
    let element: AXUIElement
    let role: String
    let subrole: String?
    let title: String?
    let desc: String?
    let identifier: String?
    let help: String?
    let placeholder: String?
    let value: Any?
    let enabled: Bool?
    let focused: Bool?
    let frame: CGRect?
    let children: [AXUIElement]
    let markChar: String?
    let cmdChar: String?
    let cmdModifiers: Int?

    private static let attributes: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
        kAXIdentifierAttribute, kAXHelpAttribute, kAXPlaceholderValueAttribute, kAXValueAttribute,
        kAXEnabledAttribute, kAXFocusedAttribute, kAXPositionAttribute, kAXSizeAttribute,
        kAXChildrenAttribute, kAXMenuItemMarkCharAttribute, kAXMenuItemCmdCharAttribute,
        kAXMenuItemCmdModifiersAttribute,
    ]

    init(_ element: AXUIElement) {
        self.element = element
        var raw: CFArray?
        let names = Node.attributes as CFArray
        var values: [Any?] = Array(repeating: nil, count: Node.attributes.count)
        if AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(), &raw) == .success,
           let array = raw as? [Any] {
            for (i, v) in array.enumerated() where i < values.count {
                // Missing attributes come back as AXValue-wrapped errors.
                if let axv = asAXValue(v), AXValueGetType(axv) == .axError { continue }
                values[i] = v
            }
        }
        func str(_ i: Int) -> String? {
            guard let s = values[i] as? String, !s.isEmpty else { return nil }
            return s
        }
        role = str(0) ?? "AXUnknown"
        subrole = str(1)
        title = str(2)
        desc = str(3)
        identifier = str(4)
        help = str(5)
        placeholder = str(6)
        value = values[7]
        enabled = values[8] as? Bool
        focused = values[9] as? Bool
        var point = CGPoint.zero, size = CGSize.zero
        let hasPoint = asAXValue(values[10]).map { AXValueGetValue($0, .cgPoint, &point) } ?? false
        let hasSize = asAXValue(values[11]).map { AXValueGetValue($0, .cgSize, &size) } ?? false
        frame = hasPoint && hasSize ? CGRect(origin: point, size: size) : nil
        children = (values[12] as? [AXUIElement]) ?? []
        markChar = str(13)
        cmdChar = str(14)
        cmdModifiers = values[15] as? Int
    }

    /// The human-facing name of the element: what a person would read on screen.
    var label: String? {
        if let title { return title }
        if let desc { return desc }
        if role == kAXStaticTextRole, let s = value as? String, !s.isEmpty { return s }
        if let titled = titleElementText { return titled }
        if let placeholder { return placeholder }
        return help
    }

    /// Text of the element named by AXTitleUIElement: how SwiftUI Form rows label their
    /// switches and pop-ups. VoiceOver reads it, so it counts as a label.
    private var titleElementText: String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let titleElement = ref as! AXUIElement
        for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            var text: CFTypeRef?
            if AXUIElementCopyAttributeValue(titleElement, attribute as CFString, &text) == .success,
               let string = text as? String, !string.isEmpty {
                return string
            }
        }
        return nil
    }

    var shortRole: String {
        var r = role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
        r = r.prefix(1).lowercased() + r.dropFirst()
        if let subrole, ["AXWindow", "AXButton", "AXTextField"].contains(role) {
            let s = subrole.hasPrefix("AX") ? String(subrole.dropFirst(2)) : subrole
            r += ":" + s.prefix(1).lowercased() + s.dropFirst()
        }
        return r
    }

    var actions: [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    var isPressable: Bool { actions.contains(kAXPressAction) }

    /// Unlabeled layout containers are hidden from tree output (their children are shown).
    var isNoise: Bool {
        let containers: Set<String> = ["AXGroup", "AXScrollArea", "AXSplitGroup", "AXLayoutArea", "AXUnknown", "AXLayoutItem"]
        return containers.contains(role) && title == nil && desc == nil && identifier == nil
    }

    /// One compact line: role "label" = value [flags] ⌘X @x,y wxh
    /// On screen right now. Closed menus keep their items in the tree but have no frame.
    var isOnScreen: Bool { (frame?.width ?? 0) > 0 && (frame?.height ?? 0) > 0 }

    var isSeparator: Bool { role == kAXMenuItemRole && label == nil && enabled == false }

    /// SwiftUI/AppKit internal identifiers ("menuAction:", "_NS:123") mean nothing to a reader.
    var meaningfulIdentifier: String? {
        guard let identifier, !identifier.hasSuffix(":"), !identifier.hasPrefix("_NS:") else { return nil }
        return identifier
    }

    func line(showFrame: Bool = true) -> String {
        if isSeparator { return "separator" }
        var parts: [String] = [shortRole]
        if let label { parts.append(quote(label)) }
        if let id = meaningfulIdentifier, id != label { parts.append("#" + id) }
        switch role {
        case kAXCheckBoxRole, kAXRadioButtonRole, "AXSwitch", "AXToggle":
            if let n = value as? Int { parts.append(n == 0 ? "[off]" : "[on]") }
        case kAXStaticTextRole:
            if let s = value as? String, !s.isEmpty, s != label { parts.append("= " + quote(s)) }
        default:
            if let s = value as? String {
                if s != label { parts.append("= " + quote(s)) }
            } else if let n = value as? NSNumber {
                parts.append("= \(n)")
            }
        }
        if markChar != nil { parts.append("[✓]") }
        if let cmdChar { parts.append(shortcut(cmdChar, cmdModifiers ?? 0)) }
        if role == kAXMenuRole && !isOnScreen { parts.append("[closed]") }
        if enabled == false { parts.append("[disabled]") }
        if focused == true { parts.append("[focused]") }
        if showFrame, let f = frame, f.width > 0, f.height > 0 {
            parts.append("@\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
        }
        return parts.joined(separator: " ")
    }

    /// All the text an element can be found by.
    var searchableText: [String] {
        var all = [title, desc, identifier, help, placeholder].compactMap { $0 }
        if let s = value as? String, !s.isEmpty { all.append(s) }
        return all
    }
}

func asAXValue(_ any: Any?) -> AXValue? {
    guard let any else { return nil }
    let cf = any as CFTypeRef
    guard CFGetTypeID(cf) == AXValueGetTypeID() else { return nil }
    return (cf as! AXValue)
}

func quote(_ s: String, limit: Int = 80) -> String {
    var t = s.replacingOccurrences(of: "\n", with: "⏎")
    if t.count > limit { t = String(t.prefix(limit)) + "…" }
    return "\"" + t + "\""
}

/// Menu shortcut text from AXMenuItemCmdChar/Modifiers. Modifier bits: 1 shift, 2 option,
/// 4 control, 8 = no command key.
func shortcut(_ char: String, _ mods: Int) -> String {
    var s = ""
    if mods & 4 != 0 { s += "⌃" }
    if mods & 2 != 0 { s += "⌥" }
    if mods & 1 != 0 { s += "⇧" }
    if mods & 8 == 0 { s += "⌘" }
    return s + char.uppercased()
}

extension AXUIElement {
    func attribute(_ name: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    func element(_ name: String) -> AXUIElement? {
        guard let v = attribute(name) else { return nil }
        let cf = v as CFTypeRef
        guard CFGetTypeID(cf) == AXUIElementGetTypeID() else { return nil }
        return (cf as! AXUIElement)
    }

    func elements(_ name: String) -> [AXUIElement] {
        (attribute(name) as? [AXUIElement]) ?? []
    }

    @discardableResult
    func perform(_ action: String) -> AXError {
        AXUIElementPerformAction(self, action as CFString)
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, name as CFString, value)
    }

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(self, &p)
        return p
    }
}

extension AXError {
    var name: String {
        switch self {
        case .success: "success"
        case .actionUnsupported: "action unsupported"
        case .attributeUnsupported: "attribute unsupported"
        case .cannotComplete: "cannot complete (app busy or not responding)"
        case .illegalArgument: "illegal argument"
        case .invalidUIElement: "element no longer exists"
        case .apiDisabled: "accessibility permission missing"
        case .notImplemented: "not implemented by the app"
        default: "AXError \(rawValue)"
        }
    }
}
