import SlopappCore
import SlopKit
import SwiftUI

/// An app's page: big icon, name and pitch with the state button (its arrow holds the
/// other actions), heart and share; its screenshots, when it has a set; a strip of facts;
/// highlights; then What's New and the copies on this Mac, with more apps from the same
/// category alongside.
struct AppDetailView: View {
    let slug: String
    @Bindable var store: Store
    let navigation: Navigation
    @State private var pageSize: CGSize = .zero

    var body: some View {
        if let item = store.item(slug) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header(item)
                    if !item.app.shots.isEmpty {
                        ShotGallery(app: item.app, images: store.shotImages, pageSize: pageSize)
                            .id(item.id)
                    }
                    InfoStrip(item: item)
                    Highlights(lines: Browse.highlights(for: item.app, license: Brand.license))
                    Hairline()
                    let related = Browse.related(to: item, in: store.items)
                    HStack(alignment: .top, spacing: PageLayout.sectionGap) {
                        VStack(alignment: .leading, spacing: Spacing.xxl) {
                            whatsNew(item)
                            if !item.copies.isEmpty {
                                onThisMac(item)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if !related.isEmpty {
                            RelatedApps(category: Categories.name(of: item), items: related, store: store, navigation: navigation)
                                .frame(width: 250)
                        }
                    }
                }
                // The same edges and top as every other page.
                .padding(.horizontal, PageLayout.margin)
                .padding(.top, Spacing.xxl)
                .padding(.bottom, PageLayout.margin)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .reportsPageScroll()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
        } else {
            ContentUnavailableView("App Not Found", systemImage: "questionmark.app",
                                   description: Text("It's no longer in the catalog."))
        }
    }

    private func header(_ item: CatalogItem) -> some View {
        HStack(alignment: .top, spacing: Spacing.xxl) {
            // The tile's art on the page's leading edge, level with the top of the page.
            AppIconView(item: item, icons: store.icons, size: 148, alignsArt: true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(item.app.name).font(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(item.app.tagline).font(.title3).foregroundStyle(.secondary)
                HStack(spacing: Spacing.s) {
                    PrimaryActionButton(item: item, store: store, navigation: navigation)
                    FavoriteButton(item: item, store: store)
                    if let url = sourceURL(item) {
                        ShareLink(item: url) {
                            SymbolButtonLabel(systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .help("Share")
                        .accessibilityLabel("Share \(item.app.name)")
                    }
                }
                .padding(.top, Spacing.m)
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
            Spacer(minLength: 0)
        }
    }

    private func whatsNew(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("What's New").font(.title2).accessibilityAddTraits(.isHeader)
                if item.app.isInstallable, let version = item.app.version {
                    Text("Version \(version)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
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
            Text("On This Mac").font(.title2).accessibilityAddTraits(.isHeader)
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

/// The app's folder in the source repository (what Share and the strip's "Source" link to).
/// Planned apps have no folder yet.
func sourceURL(_ item: CatalogItem) -> URL? {
    guard item.app.version != nil || item.isInstalled else { return nil }
    return Brand.repoURL.appendingPathComponent("tree/main/apps/\(item.app.name)")
}

/// The big state button with an arrow for everything else (Reveal in Finder, Reinstall,
/// Favorites, Move to Trash…). While something runs it shows progress instead.
struct PrimaryActionButton: View {
    let item: CatalogItem
    @Bindable var store: Store
    let navigation: Navigation

    var body: some View {
        if let operation = store.operations[item.id] {
            ButtonHeightSlot(controlSize: .large) {
                OperationProgress(item: item, operation: operation, store: store)
            }
        } else if item.state == .comingSoon {
            HStack(spacing: Spacing.s) {
                ComingSoonPill(large: true)
                if item.primary != nil { menu(title: "Open", action: { store.open(item) }) }
            }
        } else {
            let retry = store.errors[item.id]?.isInstallFailure == true
            switch item.state {
            case .notInstalled:
                menu(title: retry ? "Retry" : "Install", prominent: true, label: retry ? "Retry installing \(item.app.name)" : "Install \(item.app.name)") {
                    store.installOrUpdate(item)
                }
            case .updateAvailable:
                menu(title: retry ? "Retry" : "Update", prominent: true, label: retry ? "Retry updating \(item.app.name)" : "Update \(item.app.name)") {
                    store.installOrUpdate(item)
                }
            default:
                menu(title: "Open", label: "Open \(item.app.name)") { store.open(item) }
            }
        }
    }

    private func menu(title: String, prominent: Bool = false, label: String? = nil, action: @escaping () -> Void) -> some View {
        SplitButton(title: title, prominent: prominent, accessibilityLabel: label ?? title,
                    menuLabel: "More actions for \(item.app.name)", action: action) {
            menuItems(primaryTitle: title)
        }
    }

    /// Everything else you can do with the app, under the arrow.
    private func menuItems(primaryTitle: String) -> [MenuAction] {
        var items: [MenuAction] = []
        if item.primary != nil {
            if primaryTitle != "Open" { items.append(.init("Open") { store.open(item) }) }
            items.append(.init("Reveal in Finder") { store.reveal(item) })
        }
        if item.isOnlyElsewhere, item.app.isInstallable {
            items.append(.init("Install a Copy in Applications") { store.installOrUpdate(item) })
        }
        if item.state == .installed, item.app.isInstallable, item.primary?.location.canModify == true {
            items.append(.init("Reinstall") { store.reinstall(item) })
        }
        items.append(.init(store.isFavorite(item) ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(item) })
        if item.primary?.location.canModify == true {
            items.append(.separator)
            items.append(.init("Move to Trash…") { store.requestUninstall(item) })
        }
        return items
    }
}

/// The heart: adds the app to Favorites (and takes it off again).
struct FavoriteButton: View {
    let item: CatalogItem
    let store: Store

    var body: some View {
        let isFavorite = store.isFavorite(item)
        SymbolButton(systemImage: isFavorite ? "heart.fill" : "heart",
                     tint: isFavorite ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)) {
            store.toggleFavorite(item)
        }
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(isFavorite ? "Remove \(item.app.name) from Favorites" : "Add \(item.app.name) to Favorites")
    }
}

/// Version, size, requirements, category and the source link, on one rounded strip.
struct InfoStrip: View {
    let item: CatalogItem

    var body: some View {
        let app = item.app
        HStack(spacing: PageLayout.columnSpacing) {
            if let version = app.version {
                fact("Version \(version)")
            } else if let copy = item.primary {
                fact("Version \(copy.info.version)", help: "The version on this Mac")
            } else {
                fact("Coming soon")
            }
            if let size = app.size {
                fact(SizeFormat.string(size), help: app.installedSize.map { "\(SizeFormat.string($0)) installed" } ?? "Download size")
            }
            if let macOS = app.minimumMacOS { fact("macOS \(macOS.trimmingZeroMinor)+", help: "Requires macOS \(macOS) or later") }
            if let menuBar = app.menuBarOnly { fact(menuBar ? "Menu bar app" : "Window app") }
            if let category = app.category { fact(category) }
            Spacer(minLength: Spacing.l)
            if let url = sourceURL(item) {
                HStack(spacing: Spacing.xs) {
                    Text("Source:").foregroundStyle(.secondary)
                    Link("GitHub", destination: url)
                        .accessibilityLabel("Source code on GitHub")
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.l)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    private func fact(_ text: String, help: String? = nil) -> some View {
        Text(text)
            .monospacedDigit()
            .lineLimit(1)
            .help(help ?? "")
    }
}

private extension String {
    /// "14.0" → "14".
    var trimmingZeroMinor: String { hasSuffix(".0") ? String(dropLast(2)) : self }
}

/// Short facts in two columns under the header.
struct Highlights: View {
    let lines: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                  alignment: .leading, spacing: Spacing.m) {
            ForEach(lines, id: \.self) { line in
                Label {
                    Text(line).font(.body)
                } icon: {
                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                }
            }
        }
    }
}

/// "More in Utilities": a short column of apps from the same category.
struct RelatedApps: View {
    let category: String
    let items: [CatalogItem]
    let store: Store
    let navigation: Navigation

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("More in \(category)").font(.title2).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Spacing.l) {
                ForEach(items) { item in
                    RelatedAppRow(item: item, store: store, navigation: navigation)
                }
            }
        }
    }
}

private struct RelatedAppRow: View {
    let item: CatalogItem
    let store: Store
    let navigation: Navigation
    @State private var hovering = false

    private static let iconSize: CGFloat = 48

    var body: some View {
        Button {
            navigation.showDetail(item.id)
        } label: {
            HStack(spacing: Spacing.m) {
                AppIconView(item: item, icons: store.icons, size: Self.iconSize, alignsArt: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.app.tagline.trimmingTrailingPeriod)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.app.name).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .modifier(CardHighlight(isSelected: false, isHovered: hovering, artSide: AppIconView.artSide(Self.iconSize)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(item.app.name). \(item.app.tagline)")
        .accessibilityHint("Shows details")
        .contextMenu { AppContextMenu(item: item, store: store, navigation: navigation) }
    }
}
