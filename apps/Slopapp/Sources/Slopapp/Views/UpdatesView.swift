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
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        if updates.isEmpty {
                            PageHeader(title: "Updates", subtitle: store.feedError != nil
                                       ? "Couldn't check for updates. \(lastChecked)"
                                       : "All apps are up to date. \(lastChecked)") {
                                Button("Check for Updates") { Task { await store.refresh() } }
                                    .disabled(store.isChecking)
                            }
                        } else {
                            PageHeader(
                                title: "Updates",
                                subtitle: updates.count == 1 ? "1 update available" : "\(updates.count) updates available"
                            ) {
                                Button("Update All") { store.updateAll() }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .disabled(updates.allSatisfy { store.operations[$0.id] != nil })
                            }
                            VStack(spacing: 0) {
                                ForEach(updates) { item in
                                    UpdateRow(item: item, store: store, navigation: navigation)
                                }
                            }
                        }
                        if !store.recentUpdates.isEmpty {
                            RecentlyUpdated(store: store, navigation: navigation)
                                .padding(.top, updates.isEmpty ? 0 : Spacing.l)
                        }
                    }
                    .padding(Spacing.xxl)
                }
            }
        }
        .navigationTitle("Updates")
    }
}

/// Updates done in the last week: what changed, and when.
struct RecentlyUpdated: View {
    let store: Store
    let navigation: Navigation

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Recently Updated").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            ForEach(store.recentUpdates) { update in
                HStack(spacing: Spacing.m) {
                    if let item = store.item(update.slug) {
                        AppIconView(item: item, icons: store.icons, size: 32)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.name).font(.headline)
                        Text(update.from == update.to ? "Reinstalled \(update.to)" : "\(update.from) → \(update.to)")
                            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    Text(relativeDate(update.date))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { navigation.showDetail(update.slug) }
                .accessibilityElement(children: .combine)
                Divider()
            }
        }
    }
}

struct UpdateRow: View {
    let item: CatalogItem
    let store: Store
    let navigation: Navigation
    @State private var showNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                Button {
                    navigation.showDetail(item.id)
                } label: {
                    HStack(spacing: Spacing.m) {
                        AppIconView(item: item, icons: store.icons, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.app.name).font(.headline)
                            Text(versionLine).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.app.name), \(versionLine)")
                .accessibilityHint("Shows details")
                ActionButton(item: item, store: store)
            }
            ErrorLine(message: store.errors[item.id]?.message).padding(.leading, 48 + Spacing.m)
            NoticeLine(message: store.notices[item.id]).padding(.leading, 48 + Spacing.m)
            if let notes = item.app.releaseNotes, !notes.isEmpty {
                DisclosureGroup("What's New", isExpanded: $showNotes) {
                    Text(notes)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.top, Spacing.xs)
                }
                .font(.callout)
                .padding(.leading, 48 + Spacing.m)
            }
            Divider().padding(.leading, 48 + Spacing.m).padding(.top, Spacing.s)
        }
        .padding(.top, Spacing.s)
        .contextMenu { AppContextMenu(item: item, store: store, navigation: navigation) }
    }

    private var versionLine: String {
        let from = item.primary?.info.version ?? "?"
        let to = item.app.version ?? "?"
        let size = item.app.size.map { " · \(SizeFormat.string($0))" } ?? ""
        return "\(from) → \(to)\(size)"
    }
}

extension String {
    /// "Today at 10:31" reads better mid-sentence as "today at 10:31"; dates stay as they are.
    var lowercasedFirst: String {
        hasPrefix("Today") || hasPrefix("Yesterday") ? prefix(1).lowercased() + dropFirst() : self
    }
}
