import SlopappCore
import SlopKit
import SwiftUI

/// The home page: a featured banner you can page through, then one row of cards per
/// category with "See All" leading to the category page.
struct DiscoverView: View {
    let store: Store
    let navigation: Navigation

    var body: some View {
        Group {
            if store.feed == nil {
                CatalogUnavailable(store: store)
            } else {
                let categories = store.categories
                let rows = categories.map { Browse.apps(store.items, category: $0) }
                KeyboardGrid(sections: { columns in rows.map { Array($0.prefix(columns * 2)) } },
                             navigation: navigation, store: store) { columns in
                    VStack(alignment: .leading, spacing: PageLayout.sectionGap) {
                        let featured = Browse.featured(store.items)
                        if !featured.isEmpty {
                            FeaturedCarousel(items: featured, store: store, navigation: navigation)
                        }
                        // A hairline between category rows, as far from the cards above as
                        // from the title below; none after the last.
                        ForEach(Array(zip(categories, rows).enumerated()), id: \.element.0) { index, row in
                            if index > 0 { Hairline() }
                            CategoryRow(name: row.0, apps: row.1, columns: columns, store: store, navigation: navigation)
                        }
                    }
                }
            }
        }
    }
}

/// "Utilities", one line about it, See All, and its first two rows of cards.
struct CategoryRow: View {
    let name: String
    let apps: [CatalogItem]
    let columns: Int
    let store: Store
    let navigation: Navigation
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    CategoryTitle(name: name)
                    Text(Categories.blurb(for: name)).font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    navigation.show(.category(name))
                } label: {
                    HStack(spacing: 2) {
                        Text(apps.count > columns * 2 ? "See All \(apps.count)" : "See All")
                            .monospacedDigit()
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(activeState == .inactive ? AnyShapeStyle(.secondary) : AnyShapeStyle(Tone.category(name).ink))
                .accessibilityLabel("See All \(name)")
            }
            AppGrid(items: Array(apps.prefix(columns * 2)), columns: columns, store: store, navigation: navigation)
        }
    }
}

/// A category's name with its colour in front (the dot hangs in the margin, so the title
/// stays on the page's leading edge).
struct CategoryTitle: View {
    let name: String

    var body: some View {
        Text(name).font(.largeTitle)
            .accessibilityAddTraits(.isHeader)
            .overlay(alignment: .leading) {
                CategoryDot(tone: .category(name), size: 12)
                    .alignmentGuide(.leading) { $0.width + Spacing.m }
            }
    }
}

/// Wide banners for a handful of apps you can install, one page at a time; the next one
/// peeks in at the right edge. Swipe or scroll sideways, or click a peeking banner to bring
/// it in; clicking the one in view opens the app's page.
struct FeaturedCarousel: View {
    let items: [CatalogItem]
    let store: Store
    let navigation: Navigation
    @State private var current: String?
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Space between banners; what's left of the page margin shows the next one.
    private let gap: CGFloat = Spacing.m
    private static let shadowRoom: CGFloat = Spacing.xxl

    var body: some View {
        // As wide as the page's content, so a banner lines up with the cards' leading and
        // trailing edges.
        let bannerWidth = max(width, 200)
        ScrollView(.horizontal) {
            // Lazy: only the banner in view and its neighbours are drawn.
            LazyHStack(spacing: gap) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isCurrent = (current ?? items.first?.id) == item.id
                    Button {
                        if isCurrent {
                            navigation.showDetail(item.id)
                        } else {
                            // Under 250 ms; with Reduce Motion it moves without the slide.
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { current = item.id }
                        }
                    } label: {
                        FeaturedBanner(item: item, plate: .forBanner(index), store: store)
                            .frame(width: bannerWidth)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Featured: \(item.app.name). \(item.app.tagline)")
                    .accessibilityHint(isCurrent ? "Shows details" : "Scrolls to it")
                    .contextMenu { AppContextMenu(item: item, store: store, navigation: navigation) }
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
            // Room for the banners' shadows (the scroll view clips to its bounds).
            .padding(.vertical, Self.shadowRoom)
        }
        .contentMargins(.horizontal, PageLayout.margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current, anchor: .leading)
        .scrollIndicators(.never)
        .frame(height: FeaturedBanner.height + 2 * Self.shadowRoom)
        .padding(.vertical, -Self.shadowRoom)
        // Full width of the panel (the page's margins hold the peeking neighbours).
        .padding(.horizontal, -PageLayout.margin)
        // Measured outside the negative padding: the page's content width.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: items.map(\.id)) { current = items.first?.id }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Featured Apps")
    }
}

/// One banner, mounted like a herbarium sheet: a print panel in one of the Nordic colours, the
/// app's label on a paper card at the left (a small uppercase line, the pitch, name and
/// category), and its icon on the print at the right in a clear (unprinted) zone.
struct FeaturedBanner: View {
    let item: CatalogItem
    let plate: Plate
    let store: Store
    @Environment(\.colorScheme) private var colorScheme

    static let height: CGFloat = 220
    private static let iconSize: CGFloat = 168
    /// The card sits this far inside the panel; the icon keeps this much print-free margin.
    private static let mat: CGFloat = Spacing.m
    private static let radius: CGFloat = Radius.xxl

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let dark = colorScheme == .dark
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size, iconSize: Self.iconSize, mat: Self.mat)
            ZStack(alignment: .topLeading) {
                PrintPanel(plate: plate, shape: shape, clearZones: [layout.iconZone])
                card
                    .frame(width: layout.card.width, height: layout.card.height)
                    .offset(x: layout.card.minX, y: layout.card.minY)
                AppIconView(item: item, icons: store.icons, size: Self.iconSize, alignsArt: true)
                    .shadow(color: .black.opacity(dark ? 0.4 : 0.18), radius: dark ? 6 : 8, y: dark ? 3 : 4)
                    .offset(x: layout.icon.minX, y: layout.icon.minY)
            }
        }
        .frame(height: Self.height)
        .contentShape(shape)
        // Matte: a soft neutral shadow, cast by a plain shape behind the banner so the banner
        // itself isn't rendered offscreen.
        .background {
            shape.fill(Color(nsColor: plate.tone.panel))
                .shadow(color: .black.opacity(dark ? 0.45 : 0.12), radius: dark ? 6 : 8, y: dark ? 3 : 4)
        }
    }

    /// The label: text on paper, like a herbarium sheet's.
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.nested(in: Self.radius, padding: Self.mat), style: .continuous)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text(item.isInstalled ? "ON THIS MAC" : "FREE DOWNLOAD")
                .font(.caption.weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(Color(nsColor: Herbarium.muted))
            Text(item.app.tagline.trimmingTrailingPeriod)
                .font(.title.weight(.medium))
                .fontDesign(.serif)
                .foregroundStyle(Color(nsColor: Herbarium.text))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Text([item.app.name, item.app.category].compactMap { $0 }.joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(Color(nsColor: Herbarium.muted))
                .lineLimit(1)
                .padding(.top, 2)
        }
        .padding(.horizontal, Spacing.xxl + Spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: Herbarium.paper), in: shape)
    }

    /// Where the card and the icon go in a banner of `size`.
    struct Layout {
        let card: CGRect
        /// The icon view's frame (its art, since it lays out by the art).
        let icon: CGRect
        let iconZone: ClearZone

        @MainActor init(size: CGSize, iconSize: CGFloat, mat: CGFloat) {
            // The card takes about half the banner; the icon is centred in the rest.
            let cardWidth = min(max(size.width * 0.5, 300), 520)
            card = CGRect(x: mat, y: mat, width: cardWidth, height: max(0, size.height - 2 * mat))
            let art = AppIconView.artSide(iconSize)
            let centre = CGPoint(x: card.maxX + (size.width - card.maxX) / 2, y: size.height / 2)
            icon = CGRect(x: (centre.x - art / 2).rounded(), y: (centre.y - art / 2).rounded(), width: art, height: art)
            iconZone = ClearZone(rect: icon.insetBy(dx: -mat, dy: -mat), radius: Radius.iconTile(side: art) + mat)
        }
    }
}
