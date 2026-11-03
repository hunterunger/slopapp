import SlopappCore
import SlopKit
import SwiftUI

struct DiscoverView: View {
    let store: Store
    let navigation: Navigation

    var body: some View {
        Group {
            if store.feed == nil {
                CatalogUnavailable(store: store)
            } else {
                KeyboardGrid(sections: [store.available, store.comingSoon], navigation: navigation) {
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        PageHeader(title: "Discover", subtitle: "Free, open-source Mac apps. No account, no tracking.")
                        if !store.available.isEmpty {
                            section("Available Now", items: store.available)
                        }
                        if !store.comingSoon.isEmpty {
                            section("Coming Soon", items: store.comingSoon)
                        }
                    }
                }
            }
        }
        .navigationTitle("Discover")
    }

    private func section(_ title: String, items: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title).font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            AppGrid(items: items, store: store, navigation: navigation)
        }
    }
}

/// App Store-style rows in an adaptive grid: icon, name, tagline, state button.
struct AppGrid: View {
    static let minimumWidth: Double = 300
    let items: [CatalogItem]
    let store: Store
    let navigation: Navigation

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.minimumWidth), spacing: Spacing.xxl, alignment: .top)], alignment: .leading, spacing: Spacing.l) {
            ForEach(items) { item in
                AppCard(item: item, store: store, navigation: navigation)
            }
        }
    }
}

struct AppCard: View {
    let item: CatalogItem
    let store: Store
    let navigation: Navigation

    var body: some View {
        let isSelected = navigation.selection == item.id
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                Button {
                    navigation.selection = item.id
                    navigation.showDetail(item.id)
                } label: {
                    HStack(spacing: Spacing.m) {
                        AppIconView(item: item, icons: store.icons, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.app.name).font(.headline)
                            Text(item.app.tagline)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.app.name). \(item.app.tagline)")
                .accessibilityHint("Shows details")
                ActionButton(item: item, store: store)
            }
            ErrorLine(message: store.errors[item.id]?.message)
                .padding(.leading, 56 + Spacing.m)
            NoticeLine(message: store.notices[item.id])
                .padding(.leading, 56 + Spacing.m)
            Divider().padding(.leading, 56 + Spacing.m)
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .padding(-Spacing.s)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu { AppContextMenu(item: item, store: store, navigation: navigation) }
    }
}

/// Right-click menu shared by cards and rows.
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
        if item.primary?.location.canModify == true {
            Divider()
            Button("Move to Trash…") { store.requestUninstall(item) }
        }
    }
}

/// A scrolling page of card sections you can move through with the arrow keys; Return
/// shows the selected app's details. Tab reaches it from the sidebar and search field.
struct KeyboardGrid<Content: View>: View {
    let sections: [[CatalogItem]]
    @Bindable var navigation: Navigation
    /// Take keyboard focus when shown. Off for search results, so typing stays in the field.
    var autofocus = true
    @ViewBuilder var content: Content
    @State private var width: Double = 0
    @FocusState private var focused: Bool

    private var flat: [CatalogItem] { sections.flatMap { $0 } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(Spacing.xxl)
                    .onGeometryChange(for: Double.self) { $0.size.width - 2 * Spacing.xxl } action: { width = $0 }
            }
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
            // Arrow keys work as soon as the page shows (⌘1–⌘4 still switch pages; Tab
            // goes back to the sidebar and search field).
            .onAppear { if autofocus { focused = true } }
            .onKeyPress(.escape) {
                guard navigation.selection != nil else { return .ignored }
                navigation.selection = nil
                return .handled
            }
        }
    }

    private func move(_ direction: GridNavigation.Direction, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let grid = GridNavigation(
            sections: sections.map(\.count),
            columns: GridNavigation.columns(width: width, minimum: AppGrid.minimumWidth, spacing: Spacing.xxl)
        )
        let items = flat
        let index = navigation.selection.flatMap { slug in items.firstIndex { $0.id == slug } }
        guard let next = grid.move(from: index, direction), next < items.count else { return .ignored }
        navigation.selection = items[next].id
        proxy.scrollTo(items[next].id)
        return .handled
    }
}
