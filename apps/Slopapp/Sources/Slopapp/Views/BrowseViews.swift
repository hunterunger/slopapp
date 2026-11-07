import SlopappCore
import SlopKit
import SwiftUI

/// All Apps, or one category: title and a line about it, the sort control on the right,
/// filter chips, then every matching app as cards.
struct CatalogPage: View {
    /// nil: All Apps.
    let category: String?
    let store: Store
    @Bindable var navigation: Navigation

    var body: some View {
        let title = category ?? "All Apps"
        Group {
            if store.feed == nil {
                CatalogUnavailable(store: store)
            } else {
                let apps = Browse.apps(store.items, category: category, filter: navigation.filter, sort: navigation.sort)
                KeyboardGrid(sections: { _ in [apps] }, navigation: navigation, store: store) { columns in
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        PageHeader(title: title,
                                   subtitle: category.map(Categories.blurb(for:)) ?? "Every app in the catalog. Free, open source, no account.",
                                   isCategory: category != nil) {
                            Picker("Sort By", selection: $navigation.sort) {
                                ForEach(CatalogSort.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .help("Sort apps")
                        }
                        FilterChips(selection: $navigation.filter)
                        Hairline()
                        if apps.isEmpty {
                            // A filter that leaves nothing: say so, and offer the way back.
                            ContentUnavailableView {
                                switch navigation.filter {
                                case .all: Label("No Apps Here Yet", systemImage: "square.grid.2x2")
                                case .available: Label("Nothing to Install Yet", systemImage: "square.grid.2x2")
                                case .comingSoon: Label("Nothing Planned Here", systemImage: "square.grid.2x2")
                                }
                            } description: {
                                switch navigation.filter {
                                case .all: Text("Apps in \(title) will show up here.")
                                case .available: Text("No app in \(title) is ready to download yet.")
                                case .comingSoon: Text("Every app planned for \(title) is out already.")
                                }
                            } actions: {
                                if navigation.filter != .all {
                                    Button("Show All") { navigation.filter = .all }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 240)
                        } else {
                            AppGrid(items: apps, columns: columns, store: store, navigation: navigation,
                                    caption: category == nil ? { Categories.name(of: $0) } : nil)
                        }
                    }
                }
            }
        }
    }
}

/// Starred apps, with Install All for setting up a new Mac.
struct FavoritesView: View {
    let store: Store
    let navigation: Navigation

    var body: some View {
        let favorites = store.favoriteItems
        let missing = store.favorites.installable(in: store.items)
        Group {
            if favorites.isEmpty {
                ContentUnavailableView {
                    Label("No Favorites Yet", systemImage: "heart")
                } description: {
                    Text("Click the heart on an app's page to keep it here. On a new Mac, install them all at once.")
                } actions: {
                    Button("Browse Apps") { navigation.show(.discover) }
                }
            } else {
                KeyboardGrid(sections: { _ in [favorites] }, navigation: navigation, store: store) { columns in
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        PageHeader(title: "Favorites",
                                   subtitle: missing.isEmpty ? "Apps you starred. They're all on this Mac."
                                       : "Apps you starred. Install the ones missing from this Mac in one go.") {
                            Button(missing.count > 1 ? "Install All (\(missing.count))" : "Install All") { store.installFavorites() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(missing.isEmpty || missing.allSatisfy { store.operations[$0.id] != nil })
                        }
                        Hairline()
                        AppGrid(items: favorites, columns: columns, store: store, navigation: navigation)
                    }
                }
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
                KeyboardGrid(sections: { _ in [results] }, navigation: navigation, store: store, autofocus: false) { columns in
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        PageHeader(title: "Results", subtitle: results.count == 1 ? "1 app" : "\(results.count) apps")
                        Hairline()
                        AppGrid(items: results, columns: columns, store: store, navigation: navigation,
                                caption: { Categories.name(of: $0) })
                    }
                }
            }
        }
    }
}
