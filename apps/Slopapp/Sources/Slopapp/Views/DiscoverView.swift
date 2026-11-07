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
                .foregroundStyle(activeState == .inactive ? AnyShapeStyle(.secondary) : AnyShapeStyle(Flavour.forCategory(name).ink))
                .accessibilityLabel("See All \(name)")
            }
            AppGrid(items: Array(apps.prefix(columns * 2)), columns: columns, store: store, navigation: navigation)
        }
    }
}

/// A category's name with its flavour in front (the dot hangs in the margin, so the title
/// stays on the page's leading edge).
struct CategoryTitle: View {
    let name: String

    var body: some View {
        Text(name).font(.largeTitle)
            .accessibilityAddTraits(.isHeader)
            .overlay(alignment: .leading) {
                FlavourDot(flavour: Flavour.forCategory(name), size: 12)
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
                        FeaturedBanner(item: item, flavour: BannerPalette.forIndex(index), store: store)
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
        .frame(height: 220 + 2 * Self.shadowRoom)
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

/// Banner flavours, alternating so neighbours differ (the launcher's strawberry first).
enum BannerPalette {
    static let order: [Flavour] = [.strawberry, .lagoon, .tangerine, .grape, .lime, .blueberry]
    static func forIndex(_ index: Int) -> Flavour { order[index % order.count] }
}

/// A banner's colours for one appearance. Light mode: bright candy with graphite text on
/// tangerine, lime and lagoon; white on blueberry, grape and the strawberry → tangerine hero
/// (deepened, like the website's primary button). Dark mode: every flavour as a deep jewel
/// tone with white text. The side under the text is darkened (or not) until it measures at
/// least 5.2:1 (headroom for the sheen), so contrast is computed, not hoped for.
struct BannerColors {
    let lead: Color
    let trail: Color
    let text: Color
    let isDeep: Bool

    init(_ flavour: Flavour, dark: Bool) {
        let base = flavour.nsBase
        if dark || !flavour.carriesDarkText {
            var fraction: CGFloat = dark ? 0.38 : 0
            var lead = base.blended(withFraction: fraction, of: .black) ?? base
            while Contrast.ratio(.white, lead) < 5.2, fraction < 0.8 {
                fraction += 0.03
                lead = base.blended(withFraction: fraction, of: .black) ?? base
            }
            self.lead = Color(nsColor: lead)
            // The hero runs into tangerine, the icon's other end.
            let trailBase = flavour == .strawberry ? Flavour.tangerine.nsBase : base
            trail = Color(nsColor: trailBase.blended(withFraction: flavour == .strawberry ? (dark ? 0.4 : 0.2) : (dark ? 0.1 : 0),
                                                     of: .black) ?? trailBase)
            text = .white
            isDeep = true
        } else {
            lead = flavour.base
            trail = flavour.base.mixed(with: .white, by: 0.15)
            text = Brand.Candy.graphite
            isDeep = false
        }
    }
}

/// One banner: a small uppercase line, the app's pitch large, its name and category, and
/// its icon large on the right. Candy glass: a saturated gradient, a sheen across the top
/// like light on moulded plastic, a light rim and a soft shadow in its own colour.
struct FeaturedBanner: View {
    let item: CatalogItem
    let flavour: Flavour
    let store: Store
    @Environment(\.colorScheme) private var colorScheme

    /// Text from the left edge, icon art from the right.
    private static let inset: CGFloat = 40
    private static let iconSize: CGFloat = 176

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        let dark = colorScheme == .dark
        let colors = BannerColors(flavour, dark: dark)
        HStack(alignment: .center, spacing: Spacing.xxl) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(item.isInstalled ? "ON THIS MAC" : "FREE DOWNLOAD")
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(colors.text)
                Text(item.app.tagline.trimmingTrailingPeriod)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(colors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text([item.app.name, item.app.category].compactMap { $0 }.joined(separator: " · "))
                    .font(.title3)
                    .foregroundStyle(colors.text)
                    .padding(.top, 2)
            }
            .padding(.leading, Self.inset)
            Spacer(minLength: Spacing.xxl)
            AppIconView(item: item, icons: store.icons, size: Self.iconSize, alignsArt: true)
                .shadow(color: .black.opacity(dark ? 0.45 : 0.22), radius: dark ? 12 : 16, y: dark ? 6 : 9)
                .rotationEffect(.degrees(-7))
                .offset(y: 22)
                // The tile's art as far from the right edge as the text is from the left.
                .padding(.trailing, Self.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            ZStack {
                // The lead colour holds under the whole text block; the gradient happens behind
                // the icon.
                shape.fill(LinearGradient(stops: [.init(color: colors.lead, location: 0), .init(color: colors.lead, location: 0.55),
                                                  .init(color: colors.trail, location: 1)],
                                          startPoint: .leading, endPoint: .trailing))
                // Frosted ice behind the icon, like the white inner panel of a coloured case.
                Circle()
                    .fill(Color.white.opacity(dark ? 0.07 : 0.16))
                    .frame(width: 260, height: 260)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: 30, y: 20)
                // The case's thickness: a little shade along the bottom edge.
                LinearGradient(colors: [.clear, Color.black.opacity(dark ? 0.22 : 0.10)],
                               startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom)
                GeometryReader { geometry in
                    // The sheen: a wide ellipse catching the light along the top.
                    Ellipse()
                        .fill(LinearGradient(colors: [Color.white.opacity(dark ? 0.12 : 0.24), Color.white.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        // Ends above the text (the eyebrow starts about a quarter of the way down).
                        .frame(width: geometry.size.width * 1.3, height: geometry.size.height * 0.7)
                        .offset(x: -geometry.size.width * 0.15, y: -geometry.size.height * 0.45)
                }
            }
        }
        .clipShape(shape)
        // A light rim (1 pt clipped to the inside: 0.5 pt on the pixel grid).
        .overlay { shape.stroke(Color.white.opacity(dark ? 0.16 : 0.45), lineWidth: 1).clipShape(shape).allowsHitTesting(false) }
        .contentShape(shape)
        // Depth: a soft shadow in the banner's own colour (darker and tighter in dark mode),
        // cast by a plain shape behind it, so the banner itself isn't rendered offscreen.
        .background {
            shape.fill(colors.lead)
                .shadow(color: dark ? .black.opacity(0.5) : flavour.base.opacity(0.32), radius: dark ? 8 : 10, y: dark ? 4 : 5)
        }
    }
}
