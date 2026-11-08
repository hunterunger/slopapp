import SlopappCore
import SlopKit
import SwiftUI

struct MainWindow: View {
    @Bindable var store: Store
    @Bindable var navigation: Navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Laid out like the original's store window: a full-height sidebar with Back/Forward
        // beside the window buttons, and the pages in an inset rounded panel with search and
        // the update status along its top. No toolbar band.
        HStack(spacing: 0) {
            Sidebar(store: store, navigation: navigation)
                .frame(width: WindowChrome.sidebarWidth)
            ContentPanel(fill: Color(nsColor: Herbarium.paper)) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: WindowChrome.panelHeaderHeight)
                    PageStack(store: store, navigation: navigation)
                    // Below the pages, so it shows on app pages too.
                    StatusBanner(store: store)
                }
                // On top of the pages, not above them: macOS stretches a page's scroll view
                // up under the (empty) toolbar, and anything underneath a scroll view never
                // gets its clicks.
                .overlay(alignment: .top) { ContentHeader(store: store, navigation: navigation) }
            }
            .padding([.top, .trailing, .bottom], WindowChrome.panelInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { NordicShell() }
        .ignoresSafeArea()
        .storeWindowChrome()
        .navigationTitle(navigation.windowTitle { store.item($0)?.app.name })
        .alert(
            store.uninstallRequest.map { "Move \($0.app.name) to the Trash?" } ?? "",
            isPresented: Binding(get: { store.uninstallRequest != nil }, set: { if !$0 { store.uninstallRequest = nil } }),
            presenting: store.uninstallRequest
        ) { item in
            Button("Move to Trash") { Task { await store.uninstall(item, removeData: false) } }
                .keyboardShortcut(.defaultAction)
            Button("Move to Trash with Its Data") { Task { await store.uninstall(item, removeData: true) } }
            Button("Cancel", role: .cancel) { store.uninstallRequest = nil }
        } message: { item in
            let running = item.primary.map { RunningApps.isRunning(at: $0.url) } ?? false
            Text((running ? "\(item.app.name) is open. It will quit first. " : "")
                 + "Move only the app and keep its settings, or move its settings and data too. You can put everything back from the Trash.")
        }
        .confirmationDialog(
            store.quitRequest?.title ?? "",
            isPresented: Binding(get: { store.quitRequest != nil }, set: { if !$0 { store.cancelQuitRequest() } }),
            presenting: store.quitRequest
        ) { request in
            Button(request.items.count == 1 ? "Quit and Update" : "Quit and Update All") { store.confirmQuitAndUpdate() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { store.cancelQuitRequest() }
        } message: { request in
            Text(request.message)
        }
        .onAppear {
            navigation.openWindow = { [openWindow] in openWindow(id: WindowID.main) }
            NSApp.setActivationPolicy(.regular)
        }
    }
}

/// The page for the sidebar selection, or search results while there's a query.
struct SectionContent: View {
    let store: Store
    let navigation: Navigation

    var body: some View {
        if !navigation.search.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchResultsView(store: store, navigation: navigation)
        } else {
            switch navigation.section {
            case .discover: DiscoverView(store: store, navigation: navigation)
            case .installed: InstalledView(store: store, navigation: navigation)
            case .updates: UpdatesView(store: store, navigation: navigation)
            case .favorites: FavoritesView(store: store, navigation: navigation)
            case .allApps: CatalogPage(category: nil, store: store, navigation: navigation)
            case .category(let name): CatalogPage(category: name, store: store, navigation: navigation)
            }
        }
    }
}

/// Offline / cached catalog notices and the Undo for the last uninstall, along the bottom.
struct StatusBanner: View {
    let store: Store
    private static let dismissSlack: CGFloat = 5

    var body: some View {
        VStack(spacing: 0) {
            if let trashed = store.lastTrashed {
                bar(systemImage: "trash", text: trashed.removedData
                    ? "\(trashed.name) and its settings and data were moved to the Trash."
                    : "\(trashed.name) was moved to the Trash. Its settings were kept.") {
                    Button("Undo") { store.undoUninstall() }
                    Button {
                        store.dismissTrashed()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.regular)
                    // The cross (not its 22 pt hit area) ends on the page's trailing edge.
                    .padding(.trailing, -Self.dismissSlack)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
                }
            }
            if let error = store.feedError, store.feed != nil {
                bar(systemImage: "wifi.exclamationmark", text: "\(error) Showing the catalog from \(store.lastCheck.map { relativeDate($0).lowercasedFirst } ?? "earlier").") {
                    Button("Try Again") { Task { await store.refresh() } }
                        .disabled(store.isChecking)
                }
            }
        }
    }

    private func bar<Buttons: View>(systemImage: String, text: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Spacing.m) {
                Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(text).font(.callout).lineLimit(2)
                Spacer()
                buttons().controlSize(.small)
            }
            // On the page's content edges, like everything else in the panel.
            .padding(.horizontal, PageLayout.margin)
            .padding(.vertical, Spacing.s)
        }
        .background(.bar)
    }
}

/// The catalog didn't load and there's nothing cached: one message, one action.
struct CatalogUnavailable: View {
    let store: Store

    var body: some View {
        if store.isChecking || (store.feedError == nil && store.feed == nil) {
            ProgressView("Loading the catalog…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Can't Load the Catalog", systemImage: "wifi.exclamationmark")
            } description: {
                Text(store.feedError ?? "")
            } actions: {
                Button("Try Again") { Task { await store.refresh() } }
            }
        }
    }
}

