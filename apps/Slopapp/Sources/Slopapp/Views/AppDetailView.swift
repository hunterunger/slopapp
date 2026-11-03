import SlopappCore
import SlopKit
import SwiftUI

struct AppDetailView: View {
    let slug: String
    @Bindable var store: Store
    let navigation: Navigation

    var body: some View {
        if let item = store.item(slug) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header(item)
                    Divider()
                    InfoStrip(item: item)
                    Divider()
                    whatsNew(item)
                    if !item.copies.isEmpty {
                        onThisMac(item)
                    }
                }
                .padding(Spacing.xxl)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(item.app.name)
            // Pushed pages cover the column's own banner, so they carry their own.
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBanner(store: store) }
        } else {
            ContentUnavailableView("App Not Found", systemImage: "questionmark.app",
                                   description: Text("It's no longer in the catalog."))
        }
    }

    private func header(_ item: CatalogItem) -> some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            AppIconView(item: item, icons: store.icons, size: 128)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(item.app.name).font(.largeTitle.bold())
                Text(item.app.tagline).font(.title3).foregroundStyle(.secondary)
                if let alternative = item.app.alternativeText {
                    Text(alternative).font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: Spacing.s) {
                    ActionButton(item: item, store: store, large: true)
                    if item.primary != nil || item.app.isInstallable {
                        moreMenu(item)
                    }
                }
                .padding(.top, Spacing.s)
                ErrorLine(message: store.errors[item.id]?.message)
                NoticeLine(message: store.notices[item.id])
                if item.isOnlyElsewhere {
                    Text(item.newerVersionForElsewhereCopy
                         ? "Version \(item.app.version ?? "") is available. The copy on this Mac is outside Applications, so Slopapp won't change it. Install a copy in Applications to keep it up to date."
                         : "The copy on this Mac is outside Applications, so Slopapp won't change it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func moreMenu(_ item: CatalogItem) -> some View {
        Menu {
            if item.primary != nil {
                Button("Open") { store.open(item) }
                Button("Reveal in Finder") { store.reveal(item) }
            }
            if item.isOnlyElsewhere, item.app.isInstallable {
                Button("Install a Copy in Applications") { store.installOrUpdate(item) }
            }
            if item.state == .installed, item.app.isInstallable, item.primary?.location.canModify == true {
                Button("Reinstall") { store.reinstall(item) }
            }
            if item.primary?.location.canModify == true {
                Divider()
                Button("Move to Trash…") { store.requestUninstall(item) }
            }
        } label: {
            // The label is the accessible name; keep it stable across states.
            Label("More actions for \(item.app.name)", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .fixedSize()
        .accessibilityLabel("More actions for \(item.app.name)")
        .help("More actions")
        .disabled(store.operations[item.id] != nil)
    }

    private func whatsNew(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("What's New").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if !item.app.isInstallable {
                Text(item.isInstalled
                     ? "\(item.app.name) isn't available to download from the catalog right now."
                     : "\(item.app.name) is on the roadmap and isn't available yet.")
                    .foregroundStyle(.secondary)
            } else if let notes = item.app.releaseNotes, !notes.isEmpty {
                Text(notes).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No release notes for version \(item.app.version ?? "").")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func onThisMac(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("On This Mac").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            ForEach(item.copies, id: \.url) { copy in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(copy.info.version)").font(.headline).monospacedDigit()
                        Text(displayPath(copy.url))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(locationNote(copy.location))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SignatureBadge(copy: copy, policy: store.config.signaturePolicy)
                    }
                    Spacer()
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([copy.url]) }
                        .controlSize(.small)
                        .accessibilityLabel("Reveal \(displayPath(copy.url)) in Finder")
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    private func locationNote(_ location: CopyLocation) -> String {
        switch location {
        case .managed: "Installed by Slopapp. Updated and removed here."
        case .applications: "In Applications. Slopapp updates it in place."
        case .elsewhere: "Outside Applications. Slopapp shows it but never changes it."
        }
    }
}

/// Version, size, category, requirements: what you're getting, at a glance.
struct InfoStrip: View {
    let item: CatalogItem

    var body: some View {
        let app = item.app
        HStack(alignment: .top, spacing: 0) {
            column("Version", app.version ?? "—")
            Divider().frame(height: 36)
            column("Size", app.size.map(SizeFormat.string) ?? "—",
                   detail: app.installedSize.map { "\(SizeFormat.string($0)) installed" })
            Divider().frame(height: 36)
            column("Category", app.category ?? "—")
            Divider().frame(height: 36)
            column("Requires", app.minimumMacOS.map { "macOS \($0)" } ?? "—")
            Divider().frame(height: 36)
            column("Lives In", app.menuBarOnly == true ? "Menu bar" : (app.menuBarOnly == false ? "Window" : "—"))
        }
        .frame(maxWidth: .infinity)
    }

    private func column(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).textCase(.uppercase).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit().lineLimit(1)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
