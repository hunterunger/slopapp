import AppKit
import Observation
import SlopKit
import SwiftUI
import SwitchboardCore

/// What the picker is showing. Updated in place so the panel never has to be rebuilt.
@MainActor
@Observable
final class PickerState {
    var link: IncomingLink?
    var targets: [Target] = []
    var selection = 0
    var waitingCount = 0
    /// Modifier keys held right now, so the hint line can say what a pick will do.
    var heldModifiers: NSEvent.ModifierFlags = []

    var host: String { link.map { LinkText.host(of: $0.url) } ?? "" }
    var detail: String { link.map { LinkText.detail(of: $0.url, maxLength: 40) } ?? "" }
}

/// The browser chooser: a non-activating panel at the cursor. 1–9 open, arrows + Return,
/// click; ⌘ makes it a rule, ⇧ opens in the background, ⌘C copies, Esc or clicking away cancels.
@MainActor
final class PickerController {
    /// (link, target, background, always, receivedAt)
    var onChoose: ((IncomingLink, Target, Bool, Bool, TimeInterval) -> Void)?
    /// (link, copied)
    var onDismiss: ((IncomingLink, Bool) -> Void)?

    let state = PickerState()
    let icons = IconCache()
    private var panel: FloatingPanel?
    private var receivedAt: TimeInterval = 0
    private var resolved = false
    private var copied = false
    private var flagsMonitor: Any?

    var isShowing: Bool { panel?.isVisible == true }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(cornerRadius: 18) { [state, icons] in
            PickerView(state: state, icons: icons) { [weak self] index, flags in
                self?.pick(index, flags: flags)
            }
        }
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onDismiss = { [weak self] in self?.didDismiss() }
        panel.setAccessibilityLabel("Choose a browser")
        return panel
    }

    /// Builds the panel and draws it once off-screen, so the first real link shows instantly.
    func prewarm(targets: [Target]) {
        icons.preload(targets)
        // A link that launched the app may already be showing (or have shown) the picker:
        // then it's warm, and touching it would drop that link.
        guard panel == nil else { return }
        let panel = makePanel()
        self.panel = panel
        state.link = IncomingLink(url: URL(string: "https://example.com")!)
        state.targets = targets
        panel.setFrame(NSRect(x: -20_000, y: -20_000, width: 320, height: 160), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.orderOut(nil)
        panel.alphaValue = 1
        state.link = nil
    }

    /// - Parameter preselect: the browser to highlight first (what the rules would pick).
    func show(_ link: IncomingLink, targets: [Target], receivedAt: TimeInterval, waitingCount: Int, preselect: UUID? = nil) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        self.receivedAt = receivedAt
        resolved = false
        copied = false
        state.link = link
        state.targets = targets
        state.selection = preselect.flatMap { id in targets.firstIndex { $0.id == id } } ?? 0
        state.waitingCount = waitingCount
        state.heldModifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        icons.preload(targets)
        panel.show(at: .nearMouse)
        panel.displayIfNeeded()
        startWatchingModifiers()
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: "Open \(state.host) in. \(targets.count) choices.",
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
        Diagnostics.record("picker shown targets=\(targets.count) event_to_visible_ms=\(Diagnostics.milliseconds(since: receivedAt))")
    }

    func setWaitingCount(_ count: Int) {
        state.waitingCount = count
        if let panel, panel.isVisible { panel.show(at: .nearMouse) } // resize for the extra line
    }

    // MARK: - Picking

    private func pick(_ index: Int, flags: NSEvent.ModifierFlags) {
        guard !resolved, let link = state.link, state.targets.indices.contains(index) else { return }
        resolved = true
        let target = state.targets[index]
        let at = receivedAt
        panel?.dismiss()
        onChoose?(link, target, flags.contains(.shift), flags.contains(.command), at)
    }

    private func copyLink() {
        guard !resolved, let link = state.link else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
        copied = true
        panel?.dismiss()
        HUD.show("Link copied", systemImage: "doc.on.doc")
    }

    private func didDismiss() {
        stopWatchingModifiers()
        guard let link = state.link else { return }
        let wasResolved = resolved
        resolved = true
        state.link = nil
        if !wasResolved { onDismiss?(link, copied) }
    }

    // MARK: - Keyboard

    /// Key codes for 1–9 on the number row and the keypad (layout-independent positions).
    private static let digitKeys: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
    ]

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let number = Self.digitKeys[event.keyCode], flags.intersection([.control, .option]).isEmpty {
            pick(number - 1, flags: flags)
            return true
        }
        switch event.keyCode {
        case 8 where flags.contains(.command): // ⌘C
            copyLink()
            return true
        case 36, 76, 49: // Return, Enter, Space
            pick(state.selection, flags: flags)
            return true
        case 123, 126: // ← ↑
            moveSelection(by: -1)
            return true
        case 124, 125, 48: // → ↓ Tab
            moveSelection(by: flags.contains(.shift) && event.keyCode == 48 ? -1 : 1)
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        let count = state.targets.count
        guard count > 0 else { return }
        state.selection = (state.selection + delta + count) % count
    }

    private func startWatchingModifiers() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.state.heldModifiers = event.modifierFlags.intersection([.command, .shift])
            return event
        }
    }

    private func stopWatchingModifiers() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
    }
}

/// App icons, loaded once per app.
@MainActor
final class IconCache {
    private var icons: [String: NSImage] = [:]

    func icon(for target: Target) -> NSImage {
        if let cached = icons[target.bundleID] { return cached }
        let path = Opener.appURL(for: target)?.path ?? target.appPath
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 64, height: 64)
        icons[target.bundleID] = image
        return image
    }

    func preload(_ targets: [Target]) {
        for target in targets { _ = icon(for: target) }
    }
}

// MARK: - View

struct PickerView: View {
    @Bindable var state: PickerState
    let icons: IconCache
    let onPick: (Int, NSEvent.ModifierFlags) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: Int { min(max(state.targets.count, 1), 6) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(100), spacing: Spacing.xs), count: columns),
                alignment: .leading,
                spacing: Spacing.xs
            ) {
                ForEach(Array(state.targets.enumerated()), id: \.element.id) { index, target in
                    TargetCell(
                        target: target,
                        icon: icons.icon(for: target),
                        number: index < 9 ? index + 1 : nil,
                        isSelected: index == state.selection
                    ) {
                        onPick(index, NSApp.currentEvent?.modifierFlags ?? [])
                    }
                    .onHover { inside in
                        if inside { state.selection = index }
                    }
                }
            }
            footer
        }
        .padding(Spacing.l)
        .fixedSize()
        .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: state.selection)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: state.link?.url.isFileURL == true ? "doc" : "link")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                // Cut long hosts from the front so the part that matters (example.com) stays.
                Text(state.host)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.head)
                if !state.detail.isEmpty {
                    Text(state.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(width: max(CGFloat(columns) * 104, 320), alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Link to \(state.host)\(state.detail.isEmpty ? "" : ", \(state.detail)")")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if state.waitingCount > 0 {
                Text(state.waitingCount == 1 ? "1 more link waiting" : "\(state.waitingCount) more links waiting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hint: String {
        let isFile = state.link?.url.isFileURL == true
        if state.heldModifiers.contains(.command), !isFile { return "Always open \(state.host) in the browser you pick" }
        if state.heldModifiers.contains(.shift) { return "Open in the background" }
        return isFile ? "⇧ Background · ⌘C Copy location" : "⌘ Always use · ⇧ Background · ⌘C Copy link"
    }
}

private struct TargetCell: View {
    let target: Target
    let icon: NSImage
    let number: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .overlay(alignment: .bottomTrailing) { badge }
                Text(target.shortName)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.middle)
                Text(number.map(String.init) ?? " ")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 96)
            .padding(.vertical, Spacing.s)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var badge: some View {
        if target.privateWindow {
            Image(systemName: "eyeglasses")
                .font(.caption2.weight(.bold))
                .padding(3)
                .background(.regularMaterial, in: Circle())
                .offset(x: 4, y: 4)
        } else if let profile = target.profile {
            Text(String(profile.name.prefix(1)).uppercased())
                .font(.caption2.weight(.bold))
                .frame(width: 18, height: 18)
                .background(.regularMaterial, in: Circle())
                .offset(x: 4, y: 4)
        }
    }

    private var accessibilityName: String {
        let name = target.displayName
        return number.map { "\($0), \(name)" } ?? name
    }
}
