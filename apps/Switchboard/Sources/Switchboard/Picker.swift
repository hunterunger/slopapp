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
    var size: PickerSize = .medium
    /// Room for the list on the current screen; the list scrolls past this.
    var availableListHeight: Double = 10_000
    /// Bumped on every show, so the list scrolls the preselected row into view.
    var generation = 0
    /// Where the pointer was when the picker appeared. Hover only selects once it moves, so a
    /// panel that opens under a resting pointer keeps the rule's preselection.
    @ObservationIgnored var mouseAtShow: CGPoint = .zero

    var host: String { link.map { LinkText.host(of: $0.url) } ?? "" }
    var detail: String { link.map { LinkText.detail(of: $0.url, maxLength: 44) } ?? "" }
    var isFile: Bool { link?.url.isFileURL == true }
    var layout: PickerLayout {
        PickerLayout(rowCount: targets.count, size: size, availableHeight: availableListHeight)
    }

    /// Panel width per row size: room for "Google Chrome Canary" and its key.
    var width: CGFloat {
        switch size {
        case .small: 270
        case .medium: 300
        case .large: 340
        }
    }
}

/// The browser chooser: a non-activating panel near the pointer with one row per browser.
/// 1–9 open, ↑/↓/Tab + Return, click; ⌘ makes it a rule, ⇧ opens in the background, ⌘C copies,
/// Esc or clicking away cancels. Each row also has a menu (right-click or "…").
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
    /// Header + footer + padding, measured after each show (an estimate until then).
    private var chromeHeight: Double = 120

    /// Gap kept between the panel and the screen's edges (matches `PanelPlacement`'s margin).
    private static let screenMargin: Double = 16

    var isShowing: Bool { panel?.isVisible == true }

    /// The panel, for store screenshot scenes.
    var window: NSWindow? { panel }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel { [state, icons] in
            PickerView(
                state: state,
                icons: icons,
                onPick: { [weak self] index, flags in self?.pick(index, flags: flags) },
                onCopy: { [weak self] in self?.copyLink() }
            )
        }
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onDismiss = { [weak self] in self?.didDismiss() }
        panel.setAccessibilityLabel("Choose a browser")
        return panel
    }

    /// Builds the panel and draws it once off-screen, so the first real link shows instantly.
    func prewarm(targets: [Target], size: PickerSize) {
        icons.preload(targets)
        // A link that launched the app may already be showing (or have shown) the picker:
        // then it's warm, and touching it would drop that link.
        guard panel == nil else { return }
        let panel = makePanel()
        self.panel = panel
        state.link = IncomingLink(url: URL(string: "https://example.com")!)
        state.targets = targets
        state.size = size
        // Learn the header/footer height now, so even a long list sizes right on the first show.
        if let fitting = panel.contentView?.fittingSize.height, fitting > state.layout.listHeight {
            chromeHeight = fitting - state.layout.listHeight
        }
        // Then draw it the way it will appear (a long list scrolls), so that view exists too.
        state.availableListHeight = Self.visibleFrameUnderPointer().height - 2 * Self.screenMargin - chromeHeight
        panel.setFrame(NSRect(x: -20_000, y: -20_000, width: 320, height: 300), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.orderOut(nil)
        panel.alphaValue = 1
        state.link = nil
    }

    /// - Parameter preselect: the browser to highlight first (what the rules would pick).
    func show(
        _ link: IncomingLink, targets: [Target], size: PickerSize, receivedAt: TimeInterval,
        waitingCount: Int, preselect: UUID? = nil
    ) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        self.receivedAt = receivedAt
        resolved = false
        copied = false
        state.link = link
        state.targets = targets
        state.size = size
        state.selection = preselect.flatMap { id in targets.firstIndex { $0.id == id } } ?? 0
        state.waitingCount = waitingCount
        state.heldModifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        state.mouseAtShow = NSEvent.mouseLocation
        state.generation &+= 1
        icons.preload(targets)
        place(panel)
        panel.displayIfNeeded()
        startWatchingModifiers()
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: "Open \(state.host) in. \(targets.count) choices.",
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
        Diagnostics.record("picker shown targets=\(targets.count) event_to_visible_ms=\(Diagnostics.milliseconds(since: receivedAt))")
    }

    /// Sizes the list for the pointer's screen and shows the panel near the pointer, fully on
    /// screen. With many browsers on a short screen the list scrolls instead of spilling off.
    private func place(_ panel: FloatingPanel) {
        let visible = Self.visibleFrameUnderPointer()
        let room = visible.height - 2 * Self.screenMargin
        state.availableListHeight = room - chromeHeight
        panel.show(at: .nearMouse)
        // Learn the real header/footer height; if the estimate was off and the panel doesn't
        // fit, size the list again (rare: only the first show with a very long list).
        let measured = panel.frame.height - state.layout.listHeight
        if measured > 0, abs(measured - chromeHeight) > 0.5 {
            chromeHeight = measured
            if panel.frame.height > room {
                state.availableListHeight = room - chromeHeight
                panel.show(at: .nearMouse)
            }
        }
    }

    private static func visibleFrameUnderPointer() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    func setWaitingCount(_ count: Int) {
        state.waitingCount = count
        if let panel, panel.isVisible { place(panel) } // resize for the extra line
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
        HUD.show(link.url.isFileURL ? "Location copied" : "Link copied", systemImage: "doc.on.doc")
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
        case 126: // ↑
            moveSelection(by: -1)
            return true
        case 125: // ↓
            moveSelection(by: 1)
            return true
        case 48: // Tab, ⇧Tab
            moveSelection(by: flags.contains(.shift) ? -1 : 1)
            return true
        case 115, 116: // Home, Page Up
            state.selection = 0
            return true
        case 119, 121: // End, Page Down
            state.selection = max(state.targets.count - 1, 0)
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        state.selection = PickerSelection.moved(from: state.selection, by: delta, count: state.targets.count)
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

/// Picker geometry. Everything hangs off two columns: the icon column (header symbol, row
/// icons, footer text share its leading edge) and the trailing key column (key caps, the copy
/// button, the "…" menu share its centre line).
enum PickerMetrics {
    /// Around the list, inside the panel. Rows' highlight is concentric with the panel.
    static let listInset = Spacing.s
    /// Row content inset from the row's edges (same as the gap above and below the icon).
    static let rowInset = CGFloat(PickerSize.rowInset)
    /// Leading and trailing edge of all content, from the panel's edge.
    static let contentInset = listInset + rowInset
    /// Width of the trailing column.
    static let keySlot: CGFloat = 20
    /// Gap between columns inside a row (icon → name, menu → key).
    static let columnGap = Spacing.s
}

struct PickerView: View {
    @Bindable var state: PickerState
    let icons: IconCache
    let onPick: (Int, NSEvent.ModifierFlags) -> Void
    let onCopy: () -> Void
    @Environment(\.floatingPanelCornerRadius) private var panelRadius

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            list
                .padding(PickerMetrics.listInset)
            Hairline()
            footer
        }
        .frame(width: state.width)
        .fixedSize()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: PickerMetrics.columnGap) {
            // Centred in the icon column, so the host lines up with the browser names.
            Image(systemName: state.isFile ? "doc" : "link")
                .font(state.size.nameFont)
                .foregroundStyle(.secondary)
                .frame(width: state.size.iconSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                // Cut long hosts from the front so the part that matters (example.com) stays;
                // file names in the middle, keeping their start and extension.
                Text(state.host)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(state.isFile ? .middle : .head)
                if !state.detail.isEmpty {
                    Text(state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Link to \(state.host)\(state.detail.isEmpty ? "" : ", \(state.detail)")")
            Button(action: onCopy) {
                Label(state.isFile ? "Copy Location" : "Copy Link", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .frame(width: PickerMetrics.keySlot, height: PickerMetrics.keySlot)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(state.isFile ? "Copy location (⌘C)" : "Copy link (⌘C)")
        }
        .padding(.horizontal, PickerMetrics.contentInset)
        .padding(.vertical, Spacing.m)
    }

    @ViewBuilder private var list: some View {
        let layout = state.layout
        if layout.scrolls {
            ScrollViewReader { proxy in
                ScrollView(.vertical) { rows }
                    .scrollIndicators(.automatic)
                    .frame(height: layout.listHeight)
                    .onChange(of: state.selection) { _, new in proxy.scrollTo(new) }
                    .onChange(of: state.generation) { _, _ in proxy.scrollTo(state.selection) }
                    .onAppear { proxy.scrollTo(state.selection) }
            }
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: PickerLayout.rowSpacing) {
            ForEach(Array(state.targets.enumerated()), id: \.element.id) { index, target in
                TargetRow(
                    target: target,
                    icon: icons.icon(for: target),
                    key: PickerSelection.keyLabel(for: index),
                    size: state.size,
                    isSelected: index == state.selection,
                    highlightRadius: Radius.nested(in: panelRadius, padding: PickerMetrics.listInset),
                    alwaysHost: state.isFile ? nil : state.host,
                    onPick: { flags in onPick(index, flags) }
                )
                .id(index)
                .onContinuousHover { phase in
                    // Ignore the hover a resting pointer reports when the panel appears.
                    guard case .active = phase, NSEvent.mouseLocation != state.mouseAtShow else { return }
                    if state.selection != index { state.selection = index }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hint)
                .lineLimit(1)
            if state.waitingCount > 0 {
                Text(state.waitingCount == 1 ? "1 more link waiting" : "\(state.waitingCount) more links waiting")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PickerMetrics.contentInset)
        .padding(.vertical, Spacing.s)
    }

    private var hint: String {
        if state.heldModifiers.contains(.command), !state.isFile { return "Always open \(state.host) in the browser you pick" }
        if state.heldModifiers.contains(.shift) { return "Open in the background" }
        return state.isFile ? "⇧ Background · ⌘C Copy location" : "⌘ Always use · ⇧ Background · ⌘C Copy link"
    }
}

extension PickerSize {
    /// The browser name's text style in a picker row (the header's link symbol matches it).
    var nameFont: Font { self == .large ? .title3 : .body }
}

/// One browser: icon, name, profile/options line, its number key. Highlighted like a menu
/// item when selected (system selection colours, so it follows the accent colour).
private struct TargetRow: View {
    let target: Target
    let icon: NSImage
    let key: String?
    let size: PickerSize
    let isSelected: Bool
    /// Concentric with the panel: its radius minus the list's inset.
    let highlightRadius: CGFloat
    /// The host "Always open … here" would create a rule for; nil for files.
    let alwaysHost: String?
    let onPick: (NSEvent.ModifierFlags) -> Void

    /// The panel is only on screen while it's key, but follow the window state anyway so a
    /// highlight never stays blue in a background window (Golden Gate greys them).
    @Environment(\.appearsActive) private var appearsActive

    private var selectedText: Color {
        appearsActive ? Color(nsColor: .selectedMenuItemTextColor) : .primary
    }
    private var highlightFill: Color {
        Color(nsColor: appearsActive ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor)
    }
    private var highlight: RoundedRectangle { RoundedRectangle(cornerRadius: highlightRadius, style: .continuous) }

    var body: some View {
        Button {
            onPick(NSApp.currentEvent?.modifierFlags ?? [])
        } label: {
            HStack(spacing: PickerMetrics.columnGap) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.iconSize, height: size.iconSize)
                VStack(alignment: .leading, spacing: 1) {
                    // App names cut at the end ("Safari Technology Pre…"), never mid-word.
                    Text(target.appName)
                        .font(size.nameFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !target.pickerSubtitle.isEmpty {
                        Text(target.pickerSubtitle)
                            .font(.caption)
                            .foregroundStyle(isSelected ? AnyShapeStyle(selectedText.opacity(0.85)) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room for the "…" menu (an overlay, on the highlighted row only). Kept on every
                // row so a long name doesn't re-truncate when its row is highlighted.
                Color.clear.frame(width: PickerMetrics.keySlot, height: PickerMetrics.keySlot)
                keyCap
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(selectedText) : AnyShapeStyle(.primary))
            .padding(.horizontal, PickerMetrics.rowInset)
            .frame(height: size.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected { highlight.fill(highlightFill) }
            }
            .contentShape(highlight)
        }
        .buttonStyle(.plain)
        .contextMenu { actions }
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Open in Background") { onPick(.shift) }
        .accessibilityAction(named: alwaysHost.map { "Always Open \($0) Here" } ?? "Open") {
            onPick(alwaysHost == nil ? [] : .command)
        }
        // After the row's accessibility modifiers, so the menu keeps its own name.
        .overlay(alignment: .trailing) {
            if isSelected {
                moreMenu.padding(.trailing, PickerMetrics.rowInset + PickerMetrics.keySlot + PickerMetrics.columnGap)
            }
        }
        // A group per row, so VoiceOver reaches the row first and then its menu.
        .accessibilityElement(children: .contain)
    }

    /// The number key, in a fixed slot so rows past nine (no key) keep the same columns.
    private var keyCap: some View {
        ZStack {
            if let key {
                Text(key)
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(selectedText) : AnyShapeStyle(.secondary))
                    .frame(width: PickerMetrics.keySlot, height: PickerMetrics.keySlot)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(selectedText.opacity(0.6)) : AnyShapeStyle(.tertiary), lineWidth: 1)
                    }
            }
        }
        .frame(width: PickerMetrics.keySlot, height: PickerMetrics.keySlot)
        .accessibilityHidden(true)
    }

    /// The row's actions as a "…" menu, on the highlighted row only (right-click works on any).
    private var moreMenu: some View {
        Menu {
            actions
        } label: {
            Label("More for \(target.displayName)", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .foregroundStyle(selectedText)
                .frame(width: PickerMetrics.keySlot, height: PickerMetrics.keySlot)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        // A borderless menu draws its label in the tint, not the foreground style: on the
        // highlight it must be the selected-text colour in light and dark alike.
        .tint(selectedText)
        .menuIndicator(.hidden)
        .frame(width: PickerMetrics.keySlot, height: PickerMetrics.keySlot)
        .foregroundStyle(selectedText)
        .help("More options")
        .accessibilityLabel("More for \(target.displayName)")
        .accessibilitySortPriority(-1)
    }

    @ViewBuilder private var actions: some View {
        Button("Open") { onPick([]) }
        Button("Open in Background") { onPick(.shift) }
        if let alwaysHost {
            Divider()
            Button("Always Open \(alwaysHost) Here") { onPick(.command) }
        }
    }

    private var accessibilityName: String {
        let name = target.displayName + (target.opensInBackground ? ", in the background" : "")
        return key.map { "\($0), \(name)" } ?? name
    }
}
