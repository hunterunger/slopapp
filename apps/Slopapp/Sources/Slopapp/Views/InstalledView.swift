import SlopappCore
import SlopKit
import SwiftUI

/// The apps on this Mac, as cards: version and where each lives, Open / Update.
struct InstalledView: View {
    @Bindable var store: Store
    @Bindable var navigation: Navigation

    var body: some View {
        let installed = store.installed
        Group {
            if installed.isEmpty {
                if store.hasScanned {
                    ContentUnavailableView {
                        Label("No Apps Installed", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Apps you install from Discover show up here.")
                    } actions: {
                        Button("Browse Apps") { navigation.show(.discover) }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                KeyboardGrid(sections: { _ in [installed] }, navigation: navigation, store: store) { columns in
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        PageHeader(title: "Installed",
                                   subtitle: "\(installed.count == 1 ? "1 app" : "\(installed.count) apps") on this Mac. New apps go to \(displayPath(store.config.roots.installDirectory)).")
                        Hairline()
                        AppGrid(items: installed, columns: columns) { item in
                            AppCard(item: item, store: store, navigation: navigation, caption: caption(item)) {
                                SignatureBadge(copy: item.primary, policy: store.config.signaturePolicy)
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
            }
        }
    }

    private func caption(_ item: CatalogItem) -> String? {
        guard let copy = item.primary else { return nil }
        let version = "Version \(copy.info.version)"
        switch copy.location {
        case .managed, .applications: return version
        case .elsewhere: return "\(version) · not managed"
        }
    }
}
