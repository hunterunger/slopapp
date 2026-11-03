import SlopappCore
import SlopKit
import SwiftUI

struct MainWindow: View {
    @Bindable var store: Store
    @Bindable var navigation: Navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, navigation: navigation)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            VStack(spacing: 0) {
                NavigationStack(path: $navigation.path) {
                    Group {
                        if !navigation.search.trimmingCharacters(in: .whitespaces).isEmpty {
                            SearchResultsView(store: store, navigation: navigation)
                        } else {
                            switch navigation.section ?? .discover {
                            case .discover: DiscoverView(store: store, navigation: navigation)
                            case .installed: InstalledView(store: store, navigation: navigation)
                            case .updates: UpdatesView(store: store, navigation: navigation)
                            case .alsoGreat: AlsoGreatView()
                            }
                        }
                    }
                    .navigationDestination(for: String.self) { slug in
                        AppDetailView(slug: slug, store: store, navigation: navigation)
                    }
                }
                // Below the stack (not an inset) so it shows on pushed detail pages too.
                StatusBanner(store: store)
            }
        }
        .searchable(text: $navigation.search, prompt: "Search apps")
        .onSubmit(of: .search) {
            // Return in the search field opens the highlighted (or first) result.
            let results = store.items.filter { $0.matches(navigation.search) }
            if let slug = navigation.selection ?? results.first?.id { navigation.showDetail(slug) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                    }
                }
                .help("Check for Updates (⌘R)")
                .disabled(store.isChecking)
            }
        }
        .sheet(item: $store.uninstallRequest) { item in
            UninstallSheet(item: item, store: store)
        }
        .confirmationDialog(
            store.quitRequest?.title ?? "",
            isPresented: Binding(get: { store.quitRequest != nil }, set: { if !$0 { store.cancelQuitRequest() } }),
            presenting: store.quitRequest
        ) { request in
            Button(request.items.count == 1 ? "Quit and Update" : "Quit and Update All") { store.confirmQuitAndUpdate() }
            Button("Cancel", role: .cancel) { store.cancelQuitRequest() }
        } message: { _ in
            Text("Slopapp reopens it when the update is done. Save any open work first.")
        }
        .onAppear {
            navigation.openWindow = { [openWindow] in openWindow(id: WindowID.main) }
            NSApp.setActivationPolicy(.regular)
        }
    }
}

struct Sidebar: View {
    let store: Store
    @Bindable var navigation: Navigation

    var body: some View {
        List(selection: $navigation.section) {
            ForEach(Navigation.Section.allCases) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(section == .updates ? store.updates.count : 0)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
    }
}

/// Offline / cached catalog notices and the Undo for the last uninstall, along the bottom.
struct StatusBanner: View {
    let store: Store

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
            Divider()
            HStack(spacing: Spacing.m) {
                Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(text).font(.callout).lineLimit(2)
                Spacer()
                buttons().controlSize(.small)
            }
            .padding(.horizontal, Spacing.l)
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

struct SearchResultsView: View {
    let store: Store
    @Bindable var navigation: Navigation

    var body: some View {
        let results = store.items.filter { $0.matches(navigation.search) }
        Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: navigation.search)
            } else {
                KeyboardGrid(sections: [results], navigation: navigation, autofocus: false) {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        PageHeader(title: "Results", subtitle: results.count == 1 ? "1 app" : "\(results.count) apps")
                        AppGrid(items: results, store: store, navigation: navigation)
                    }
                }
            }
        }
        .navigationTitle("Search")
    }
}
