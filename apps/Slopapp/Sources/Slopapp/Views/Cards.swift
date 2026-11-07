import SlopappCore
import SlopKit
import SwiftUI

// The building blocks of every grid page: the app card (icon left; task-first pitch, name,
// and the state button stacked on the right), a fixed-column grid, the filter chips, the
// page header, and the scroll view that adds arrow-key selection.

enum PageLayout {
    /// Left/right margin of a page's content.
    static let margin: CGFloat = 36
    /// Narrowest a card gets before the grid drops a column.
    static let cardWidth: Double = 250
    static let columnSpacing: Double = 28
    static let rowSpacing: CGFloat = Spacing.xxl
    /// Between the big blocks of a page (Discover's banner and category rows, the app page's
    /// notes and its "More in" column).
    static let sectionGap: CGFloat = 32
}

/// The hover / selection shape behind a card or a list row with an app icon: it reaches
/// `padding` past the content on every side (so the icon art and text stay on the page's
/// alignment lines) and its corners are concentric with the icon tile's.
struct CardHighlight: ViewModifier {
    var isSelected: Bool
    var isHovered: Bool
    /// The visible icon tile's side (`AppIconView.artSide`).
    var artSide: CGFloat
    var padding: CGFloat = Spacing.s
    /// Give the padding back to the layout, so the content (not the highlight) lines up.
    /// `AppGrid` keeps it instead (and spaces its cells to match), so scrolling a selected
    /// card into view brings its whole highlight.
    var outdents = true

    static let gridPadding: CGFloat = Spacing.s

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.iconTile(side: artSide) + padding, style: .continuous)
        content
            .padding(padding)
            .background {
                shape.fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16))
                           : isHovered ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear))
            }
            .contentShape(shape)
            .padding(outdents ? -padding : 0)
    }
}

/// One app: icon, its pitch (what it does) as the headline, its name under it, then the
/// Install / Open / Update button and an optional line of details.
struct AppCard<Accessory: View>: View {
    let item: CatalogItem
    let store: Store
    let navigation: Navigation
    /// A short line next to the button ("Version 1.0.0", "1.0.0 → 1.1.0 · 2 MB").
    var caption: String?
    @ViewBuilder var accessory: Accessory
    @State private var hovering = false

    static var iconSize: CGFloat { 72 }

    var body: some View {
        let isSelected = navigation.selection == item.id
        HStack(alignment: .top, spacing: Spacing.m) {
            // The tile's art (not its transparent margin) sits on the page's leading edge.
            AppIconView(item: item, icons: store.icons, size: Self.iconSize, alignsArt: true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Button {
                    open()
                } label: {
                    // Every card keeps room for a two-line pitch, so the buttons in a row line up.
                    ZStack(alignment: .topLeading) {
                        textBlock(tagline: "X\nX", name: "X").hidden().accessibilityHidden(true)
                        textBlock(tagline: item.app.tagline.isEmpty ? item.app.name : item.app.tagline.trimmingTrailingPeriod,
                                  name: item.app.name)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.app.name). \(item.app.tagline)")
                .accessibilityHint("Shows details")
                HStack(spacing: Spacing.s) {
                    ActionButton(item: item, store: store, size: .card)
                    // Progress is wider than the button: rather than slide sideways, the
                    // extras step aside until it's done.
                    if store.operations[item.id] == nil { accessory }
                }
                // A confirmation that comes and goes: below the button, outside the layout, so
                // the grid doesn't move when it appears or fades.
                .overlay(alignment: .bottomLeading) {
                    NoticeLine(message: store.notices[item.id])
                        .fixedSize()
                        .alignmentGuide(.bottom) { _ in -Spacing.s }
                        .animation(.easeOut(duration: 0.2), value: store.notices[item.id])
                }
                ErrorLine(message: store.errors[item.id]?.message)
            }
        }
        .modifier(CardHighlight(isSelected: isSelected, isHovered: hovering, artSide: AppIconView.artSide(Self.iconSize),
                                padding: CardHighlight.gridPadding, outdents: false))
        .onTapGesture { open() }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu { AppContextMenu(item: item, store: store, navigation: navigation) }
    }

    /// Pitch (up to two lines), name, and the optional caption.
    private func textBlock(tagline: String, name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tagline)
                .font(.title3)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func open() {
        navigation.selection = item.id
        navigation.showDetail(item.id)
    }
}

extension AppCard where Accessory == EmptyView {
    init(item: CatalogItem, store: Store, navigation: Navigation, caption: String? = nil) {
        self.init(item: item, store: store, navigation: navigation, caption: caption) { EmptyView() }
    }
}

extension String {
    /// Taglines are sentences ("Keep your Mac awake."); as card headlines they read better bare.
    var trimmingTrailingPeriod: String { hasSuffix(".") && !hasSuffix("..") ? String(dropLast()) : self }
}

/// Cards in a fixed number of columns (the same number arrow keys move through).
struct AppGrid<Card: View>: View {
    let items: [CatalogItem]
    let columns: Int
    @ViewBuilder var card: (CatalogItem) -> Card

    var body: some View {
        // Each cell includes its card's highlight (CardHighlight.gridPadding on every side):
        // the spacing shrinks and the grid reaches out by the same amount, so the cards
        // themselves keep the page's edges and the column and row gaps.
        let pad = CardHighlight.gridPadding
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: PageLayout.columnSpacing - 2 * pad, alignment: .top),
                           count: max(1, columns)),
            alignment: .leading,
            spacing: PageLayout.rowSpacing - 2 * pad
        ) {
            ForEach(items) { item in
                card(item)
            }
        }
        .padding(-pad)
    }
}

extension AppGrid where Card == AppCard<EmptyView> {
    init(items: [CatalogItem], columns: Int, store: Store, navigation: Navigation, caption: ((CatalogItem) -> String?)? = nil) {
        self.init(items: items, columns: columns) { item in
            AppCard(item: item, store: store, navigation: navigation, caption: caption?(item))
        }
    }
}

/// Right-click menu shared by cards.
struct AppContextMenu: View {
    let item: CatalogItem
    let store: Store
    let navigation: Navigation

    var body: some View {
        Button("Show Details") { navigation.showDetail(item.id) }
        if item.primary != nil {
            Button("Open") { store.open(item) }
            Button("Reveal in Finder") { store.reveal(item) }
        }
        if item.state == .updateAvailable {
            Button("Update") { store.installOrUpdate(item) }
        }
        if item.state == .notInstalled {
            Button("Install") { store.installOrUpdate(item) }
        }
        if item.state == .installed, item.app.isInstallable, item.primary?.location.canModify == true {
            Button("Reinstall") { store.reinstall(item) }
        }
        if item.isOnlyElsewhere, item.app.isInstallable {
            Button("Install a Copy in Applications") { store.installOrUpdate(item) }
        }
        Divider()
        Button(store.isFavorite(item) ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(item) }
        if item.primary?.location.canModify == true {
            Divider()
            Button("Move to Trash…") { store.requestUninstall(item) }
        }
    }
}

/// Capsule filter chips ("All", "Available", "Coming Soon") under a page title.
struct FilterChips: View {
    @Binding var selection: CatalogFilter

    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(CatalogFilter.allCases) { filter in
                let isOn = selection == filter
                Button(filter.title) {
                    selection = filter
                }
                .buttonStyle(ChipStyle(isOn: isOn))
                .accessibilityLabel(filter.title)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }
}

/// One filter chip: a capsule, accent-filled when on; darker while hovered and pressed.
struct ChipStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, isOn: isOn)
    }

    private struct ChipBody: View {
        let configuration: ButtonStyleConfiguration
        let isOn: Bool
        @State private var hovering = false
        @Environment(\.controlActiveState) private var activeState

        var body: some View {
            configuration.label
                .font(.callout)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .foregroundStyle(isOn && activeState != .inactive
                                 ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor)) : AnyShapeStyle(.primary))
                .background(fill, in: Capsule())
                .overlay {
                    // Pressed: the same darkening on either fill.
                    if configuration.isPressed { Capsule().fill(.primary.opacity(0.12)) }
                }
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }

        private var fill: AnyShapeStyle {
            if isOn {
                // Like a selected segment: accent in the key window, grey behind it.
                return activeState == .inactive ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor)
            }
            return hovering ? AnyShapeStyle(.tertiary.opacity(0.7)) : AnyShapeStyle(.quaternary)
        }
    }
}

/// Big title, one line under it, optional controls on the right of the title (on its centre
/// line); a hairline below.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    /// A category page: its colour hangs in front of the title.
    var isCategory = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .center, spacing: Spacing.m) {
                if isCategory {
                    CategoryTitle(name: title)
                } else {
                    Text(title).font(.largeTitle)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
                trailing
            }
            if let subtitle {
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A scrolling page of card sections you can move through with the arrow keys; Return
/// shows the selected app's details, ⌘⌫ moves it to the Trash. It works out how many
/// columns fit and hands that to the content, so the grid and the arrow keys agree.
struct KeyboardGrid<Content: View>: View {
    /// The cards on screen, per section, for a column count.
    let sections: (Int) -> [[CatalogItem]]
    @Bindable var navigation: Navigation
    var store: Store?
    /// Take keyboard focus when shown. Off for search results, so typing stays in the field.
    var autofocus = true
    @ViewBuilder var content: (Int) -> Content
    @State private var columns = 3
    @FocusState private var focused: Bool
    @Environment(\.isActivePage) private var isActivePage

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content(columns)
                    .padding(.horizontal, PageLayout.margin)
                    .padding(.top, Spacing.xxl)
                    .padding(.bottom, PageLayout.margin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: Int.self) { geometry in
                        GridNavigation.columns(width: geometry.size.width - 2 * PageLayout.margin,
                                               minimum: PageLayout.cardWidth, spacing: PageLayout.columnSpacing)
                    } action: { columns = min(4, $0) }
            }
            .reportsPageScroll()
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { move(.up, proxy) }
            .onKeyPress(.downArrow) { move(.down, proxy) }
            .onKeyPress(.leftArrow) { move(.left, proxy) }
            .onKeyPress(.rightArrow) { move(.right, proxy) }
            .onKeyPress(.return) {
                guard let slug = navigation.selection else { return .ignored }
                navigation.showDetail(slug)
                return .handled
            }
            .onDeleteCommand {
                if let slug = navigation.selection, let store, let item = store.item(slug) { store.requestUninstall(item) }
            }
            // Arrow keys work as soon as the page shows (⌘1–⌘5 still switch pages; Tab
            // goes back to the sidebar and search field).
            .onAppear { if autofocus { focused = true } }
            // Back from an app page: the page underneath takes the keys again.
            .onChange(of: isActivePage) { if isActivePage && autofocus { focused = true } }
            .onKeyPress(.escape) {
                guard navigation.selection != nil else { return .ignored }
                navigation.selection = nil
                return .handled
            }
        }
    }

    private func move(_ direction: GridNavigation.Direction, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let sections = sections(columns)
        let grid = GridNavigation(sections: sections.map(\.count), columns: columns)
        let items = sections.flatMap { $0 }
        let index = navigation.selection.flatMap { slug in items.firstIndex { $0.id == slug } }
        guard let next = grid.move(from: index, direction), next < items.count else { return .ignored }
        navigation.selection = items[next].id
        withAnimation(nil) { proxy.scrollTo(items[next].id) }
        return .handled
    }
}
