import SlopappCore
import SlopKit
import SwiftUI

struct InstalledView: View {
    @Bindable var store: Store
    @Bindable var navigation: Navigation
    @FocusState private var listFocused: Bool

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
                List(selection: $navigation.selection) {
                    Section {
                        ForEach(installed) { item in
                            InstalledRow(item: item, store: store)
                                .tag(item.id)
                        }
                    } header: {
                        Text("Apps go to \(displayPath(store.config.roots.installDirectory)).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .focused($listFocused)
                // Like Discover: arrow keys work as soon as the page shows.
                .onAppear { listFocused = true }
                .contextMenu(forSelectionType: String.self) { slugs in
                    if let slug = slugs.first, let item = store.item(slug) {
                        AppContextMenu(item: item, store: store, navigation: navigation)
                    }
                } primaryAction: { slugs in
                    if let slug = slugs.first { navigation.showDetail(slug) }
                }
                .onKeyPress(.return) {
                    guard let selection = navigation.selection else { return .ignored }
                    navigation.showDetail(selection)
                    return .handled
                }
                .onDeleteCommand {
                    if let selection = navigation.selection, let item = store.item(selection) { store.requestUninstall(item) }
                }
            }
        }
        .navigationTitle("Installed")
        .navigationSubtitle(installed.isEmpty ? "" : (installed.count == 1 ? "1 app" : "\(installed.count) apps"))
    }
}

struct InstalledRow: View {
    let item: CatalogItem
    let store: Store

    var body: some View {
        HStack(spacing: Spacing.m) {
            AppIconView(item: item, icons: store.icons, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s) {
                    Text(item.app.name).font(.headline)
                    if let version = item.primary?.info.version {
                        Text(version).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if let copy = item.primary {
                    Text(locationText(copy))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                SignatureBadge(copy: item.primary, policy: store.config.signaturePolicy)
                ErrorLine(message: store.errors[item.id]?.message)
                NoticeLine(message: store.notices[item.id])
            }
            Spacer()
            ActionButton(item: item, store: store)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    private func locationText(_ copy: InstalledCopy) -> String {
        switch copy.location {
        case .managed, .applications: displayPath(copy.url)
        case .elsewhere: "\(displayPath(copy.url)) · not managed by Slopapp"
        }
    }
}
