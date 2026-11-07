import SlopappCore
import SlopKit
import SwiftUI

struct UpdatesView: View {
    @Bindable var store: Store
    let navigation: Navigation

    private var lastChecked: String {
        store.lastCheck.map { "Last checked \(relativeDate($0).lowercasedFirst)." } ?? "Not checked yet."
    }

    var body: some View {
        let updates = store.updates
        Group {
            if store.feed == nil {
                CatalogUnavailable(store: store)
            } else if updates.isEmpty && store.recentUpdates.isEmpty {
                ContentUnavailableView {
                    if store.feedError != nil {
                        Label("Couldn't Check for Updates", systemImage: "wifi.exclamationmark")
                    } else {
                        Label("All Apps Are Up to Date", systemImage: "checkmark.circle")
                    }
                } description: {
                    Text(store.feedError.map { "\($0) \(lastChecked)" } ?? lastChecked)
                } actions: {
                    Button("Check for Updates") { Task { await store.refresh() } }
                        .disabled(store.isChecking)
                }
            } else {
                KeyboardGrid(sections: { _ in [updates] }, navigation: navigation, store: store) { columns in
                    VStack(alignment: .leading, spacing: Spacing.xxl) {
                        if updates.isEmpty {
                            PageHeader(title: "Updates", subtitle: store.feedError != nil
                                       ? "Couldn't check for updates. \(lastChecked)"
                                       : "All apps are up to date. \(lastChecked)") {
                                Button("Check for Updates") { Task { await store.refresh() } }
                                    .disabled(store.isChecking)
                            }
                            Hairline()
                        } else {
                            PageHeader(
                                title: "Updates",
                                subtitle: "\(updates.count == 1 ? "A new version" : "New versions") of your apps, ready to install. \(lastChecked)"
                            ) {
                                Button {
                                    store.updateAll()
                                } label: {
                                    Label(updates.count > 1 ? "Update All (\(updates.count))" : "Update All", systemImage: "arrow.down")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(updates.allSatisfy { store.operations[$0.id] != nil })
                            }
                            Hairline()
                            AppGrid(items: updates, columns: columns) { item in
                                AppCard(item: item, store: store, navigation: navigation, caption: versionLine(item)) {
                                    ReleaseNotesButton(item: item)
                                }
                            }
                        }
                        if !store.recentUpdates.isEmpty {
                            RecentlyUpdated(store: store, navigation: navigation)
                                .padding(.top, updates.isEmpty ? 0 : Spacing.l)
                        }
                    }
                }
            }
        }
    }

    private func versionLine(_ item: CatalogItem) -> String {
        let from = item.primary?.info.version ?? "?"
        let to = item.app.version ?? "?"
        let size = item.app.size.map { " · \(SizeFormat.string($0))" } ?? ""
        return "\(from) → \(to)\(size)"
    }
}

/// "What's New" next to an update: the release notes in a popover.
struct ReleaseNotesButton: View {
    let item: CatalogItem
    @State private var showing = false

    var body: some View {
        if let notes = item.app.releaseNotes, !notes.isEmpty {
            Button("What's New") { showing.toggle() }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityLabel("What's New in \(item.app.name) \(item.app.version ?? "")")
                .popover(isPresented: $showing, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("\(item.app.name) \(item.app.version ?? "")").font(.headline)
                        Text(notes)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Spacing.l)
                    .frame(width: 320, alignment: .leading)
                }
        }
    }
}

/// Updates done in the last week: what changed, and when. Click one for its page.
struct RecentlyUpdated: View {
    let store: Store
    let navigation: Navigation

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Recently Updated").font(.title2).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(Array(store.recentUpdates.enumerated()), id: \.element.id) { index, update in
                    // Hairlines between rows, none after the last.
                    if index > 0 { Hairline() }
                    RecentUpdateRow(update: update, store: store, navigation: navigation)
                }
            }
        }
    }
}

private struct RecentUpdateRow: View {
    let update: RecentUpdate
    let store: Store
    let navigation: Navigation
    @State private var hovering = false

    private static let iconSize: CGFloat = 32

    var body: some View {
        Button {
            navigation.showDetail(update.slug)
        } label: {
            HStack(spacing: Spacing.m) {
                if let item = store.item(update.slug) {
                    AppIconView(item: item, icons: store.icons, size: Self.iconSize, alignsArt: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(update.name).font(.headline)
                    Text(update.from == update.to ? "Reinstalled \(update.to)" : "\(update.from) → \(update.to)")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Text(relativeDate(update.date))
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            .modifier(CardHighlight(isSelected: false, isHovered: hovering,
                                    artSide: AppIconView.artSide(Self.iconSize), padding: Spacing.s))
        }
        .buttonStyle(.plain)
        .padding(.vertical, Spacing.xs)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }
}

extension String {
    /// "Today at 10:31" reads better mid-sentence as "today at 10:31"; dates stay as they are.
    var lowercasedFirst: String {
        hasPrefix("Today") || hasPrefix("Yesterday") ? prefix(1).lowercased() + dropFirst() : self
    }
}
