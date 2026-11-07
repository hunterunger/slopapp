import SlopappCore
import SlopKit
import SwiftUI

// The library window's frame: the sidebar (Back/Forward on the window buttons' row, then the
// pages), the header row at the top of the content panel (search on the left, update status
// on the right), and the page area that shows a section or an app page over it.

extension EnvironmentValues {
    /// False while an app page covers the section underneath (it stays alive so its scroll
    /// position survives Back).
    @Entry var isActivePage = true
}

/// True while the page on screen is scrolled away from its top (the header shows a hairline).
struct PageScrolledKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// Reports through `PageScrolledKey` whether this scroll view is scrolled (macOS 15+;
    /// on 14 the header just never shows its hairline).
    func reportsPageScroll() -> some View { modifier(PageScrollReporter()) }
}

private struct PageScrollReporter: ViewModifier {
    @State private var scrolled = false
    @Environment(\.isActivePage) private var isActivePage

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0.5 } action: { scrolled = $1 }
                .preference(key: PageScrolledKey.self, value: scrolled && isActivePage)
        } else {
            content
        }
    }
}

/// The sidebar section's page, with the open app page (if any) on top of it.
struct PageStack: View {
    let store: Store
    let navigation: Navigation
    @State private var scrolled = false

    var body: some View {
        let detail = navigation.path.last
        ZStack {
            SectionContent(store: store, navigation: navigation)
                .opacity(detail == nil ? 1 : 0)
                .allowsHitTesting(detail == nil)
                .disabled(detail != nil)
                .accessibilityHidden(detail != nil)
                .environment(\.isActivePage, detail == nil)
            if let detail {
                AppDetailView(slug: detail, store: store, navigation: navigation)
                    .id(detail)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // macOS 26 lets scroll content run up under the (empty) toolbar, over the search
        // row; pages stop at the header.
        .clipped()
        .onPreferenceChange(PageScrolledKey.self) { scrolled = $0 }
        .overlay(alignment: .top) {
            Hairline().opacity(scrolled ? 1 : 0).animation(.easeOut(duration: 0.15), value: scrolled)
        }
    }
}

// MARK: - Sidebar

/// Back/Forward beside the window buttons, then Discover, Installed, Favorites; All Apps with
/// its categories (text only, lined up with the labels above); Updates last, with a count.
struct Sidebar: View {
    let store: Store
    @Bindable var navigation: Navigation
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.xs) {
                Spacer(minLength: 0)
                HistoryButton(symbol: "chevron.left", label: "Back", help: "Back (⌘[)",
                              enabled: navigation.history.canGoBack) { navigation.goBack() }
                HistoryButton(symbol: "chevron.right", label: "Forward", help: "Forward (⌘])",
                              enabled: navigation.history.canGoForward) { navigation.goForward() }
            }
            // Forward's chevron ends on the rows' trailing content edge (where the count ends).
            .padding(.trailing, Sidebar.inset)
            .frame(height: WindowChrome.buttonRowHeight)
            .background(WindowDragArea())

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SidebarItem.top) { item in
                        row(item).padding(.bottom, Spacing.m)
                    }
                    row(.allApps)
                    ForEach(store.categories, id: \.self) { name in
                        row(.category(name))
                    }
                    row(.updates)
                }
                .padding(.horizontal, Sidebar.inset)
                // The first row's top is level with the top of the page beside it.
                .padding(.top, WindowChrome.pageTop - WindowChrome.buttonRowHeight)
                .padding(.bottom, Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.downArrow) { move(1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sidebar")
        }
    }

    /// Rows sit this far from the sidebar's edges; their icons are centred under the close button.
    static let inset: CGFloat = Spacing.s

    private func row(_ item: SidebarItem) -> some View {
        SidebarRow(item: item,
                   badge: item == .updates ? store.updates.count : 0,
                   isSelected: navigation.section == item && navigation.search.trimmingCharacters(in: .whitespaces).isEmpty,
                   isFocused: focused) {
            navigation.show(item)
        }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard let next = SidebarItem.moved(from: navigation.section, by: step, categories: store.categories) else { return .ignored }
        navigation.show(next)
        return .handled
    }
}

private struct SidebarRow: View {
    let item: SidebarItem
    let badge: Int
    let isSelected: Bool
    let isFocused: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var activeState

    private var isActive: Bool { activeState != .inactive }

    /// Pine on the washed sidebar (lifted sage in dark mode), aimed at 4.5:1 on the wash so it
    /// keeps well over the 3:1 symbols need on the selected slot too.
    static let symbolInk = Color(nsColor: .readable(Herbarium.action, on: Herbarium.shellWash, target: 4.5))

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                // Pages get the launcher's pine; categories their own Nordic colour, as a dot in
                // the icon's space so their names line up with the labels above.
                Group {
                    if case .category(let name) = item {
                        CategoryDot(tone: .category(name))
                    } else if let symbol = item.symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(isActive ? AnyShapeStyle(SidebarRow.symbolInk) : AnyShapeStyle(.secondary))
                    }
                }
                .frame(width: 20)
                .accessibilityHidden(true)
                Text(item.title)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
                if badge > 0 { CountBadge(count: badge) }
            }
            .padding(.horizontal, Spacing.s)
            .frame(height: 28)
            .background { selection }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(badge > 0 ? "\(item.title), \(badge)" : item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var selection: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        if isSelected && isActive {
            // A pine-tinted slot; a little more colour while the sidebar has keyboard focus, so
            // arrow-key users can see where they are.
            let dark = colorScheme == .dark
            shape.fill(Color(nsColor: Herbarium.action).opacity(isFocused ? (dark ? 0.30 : 0.22) : (dark ? 0.20 : 0.13)))
        } else if isSelected {
            // Behind other windows: grey, like every selection.
            shape.fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
        } else {
            shape.fill(hovering ? AnyShapeStyle(Color.primary.opacity(0.05)) : AnyShapeStyle(.clear))
        }
    }
}

/// The Updates count: pine with paper text in the key window (7:1 or better), grey behind.
struct CountBadge: View {
    let count: Int
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.onActionCapsule(active: activeState != .inactive))
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 1)
            .background { ActionCapsule() }
    }
}

/// A borderless chevron, the size of the window buttons beside it.
private struct HistoryButton: View {
    let symbol: String
    let label: String
    let help: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                // Disabled stays visible (tertiary), like Finder's; quaternary all but vanished.
                .foregroundStyle(enabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(label)
    }
}

// MARK: - Content header

/// The top row of the content panel: a borderless search field on the left; the update
/// status (opens Updates) and Check for Updates on the right.
struct ContentHeader: View {
    let store: Store
    @Bindable var navigation: Navigation
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            SearchField(text: $navigation.search, focused: $searchFocused) {
                // Return opens the highlighted (or first) result.
                let results = store.items.filter { $0.matches(navigation.search) }
                if let slug = navigation.selection ?? results.first?.id { navigation.showDetail(slug) }
            }
            .frame(maxWidth: 300, alignment: .leading)
            Spacer(minLength: Spacing.m)
            UpdateStatusButton(store: store, navigation: navigation)
            Hairline(axis: .vertical).frame(height: 18)
            CheckForUpdatesButton(store: store)
        }
        // Search starts and the refresh arrow ends on the page's content edges.
        .padding(.horizontal, PageLayout.margin)
        .frame(height: WindowChrome.panelHeaderHeight)
        .background(WindowDragArea())
        .onChange(of: navigation.searchFocusRequest) { searchFocused = true }
    }
}

/// Magnifier and a plain text field, no bezel. Esc clears it.
private struct SearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $text, prompt: Text("Search"))
                .textFieldStyle(.plain)
                .font(.title3)
                .focused(focused)
                .onSubmit(onSubmit)
                .onExitCommand { text = "" }
                .accessibilityLabel("Search apps")
            if !text.isEmpty {
                Button {
                    text = ""
                    focused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear")
                .accessibilityLabel("Clear Search")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}

/// "✓ Up to Date" in pine / "2 Updates" on a pine capsule; opens Updates.
private struct UpdateStatusButton: View {
    let store: Store
    let navigation: Navigation
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let status = HeaderStatus(updates: store.updates.count, isChecking: store.isChecking,
                                  hasError: store.feedError != nil, hasCatalog: store.feed != nil)
        Button {
            navigation.show(.updates)
        } label: {
            HStack(spacing: Spacing.xs) {
                if status.kind == .checking {
                    ProgressView().controlSize(.small)
                } else if let symbol = status.symbol {
                    Image(systemName: symbol).fontWeight(.semibold)
                }
                Text(status.title)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(style(status))
            // Waiting updates are a pine capsule; everything else is text.
            .padding(.horizontal, status.kind == .updates ? Spacing.s : 0)
            .frame(height: status.kind == .updates ? 24 : nil)
            .background {
                if status.kind == .updates { ActionCapsule() }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help(status))
        .accessibilityLabel("\(status.title). Show Updates")
    }

    private var isActive: Bool { activeState != .inactive }

    private func style(_ status: HeaderStatus) -> AnyShapeStyle {
        switch status.kind {
        case .updates: .onActionCapsule(active: isActive)
        case .upToDate: isActive ? AnyShapeStyle(Color(nsColor: .readable(Herbarium.action, on: Herbarium.paper))) : AnyShapeStyle(.secondary)
        default: AnyShapeStyle(.secondary)
        }
    }

    private func help(_ status: HeaderStatus) -> String {
        let checked = store.lastCheck.map { "Last checked \(relativeDate($0).lowercasedFirst)." } ?? "Not checked yet."
        switch status.kind {
        case .updates: return "Show the apps with updates. \(checked)"
        case .offline: return "\(store.feedError ?? "Couldn't check for updates.") \(checked)"
        default: return checked
        }
    }
}

private struct CheckForUpdatesButton: View {
    let store: Store
    private static let slack: CGFloat = 6

    var body: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.title3)
                .foregroundStyle(store.isChecking ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Lay out by the glyph (about 14 pt of the 26 pt hit area), so it lines up with the
        // page's trailing edge and sits as far from the divider as the status text does.
        .padding(.horizontal, -Self.slack)
        .disabled(store.isChecking)
        .help("Check for Updates (⌘R)")
        .accessibilityLabel("Check for Updates")
    }
}
