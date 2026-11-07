import SlopKit
import SwiftUI

// Module pages: an intro with a hero and one big round button, a scanning screen, result
// tiles with Review / Clean, and a completion screen. Written so it can move to SlopKit
// (no Tidy types in here).

/// Where a module page is in its scan → review flow.
enum ModuleStage: Equatable {
    case intro, scanning, results, review, running, done
}

/// The module's picture: an SF Symbol on a rounded, accent-tinted tile. In a background window
/// the tile goes to the system's unemphasized grey, like the sidebar's selection.
struct ModuleHero: View {
    let systemImage: String
    var size: CGFloat = 150
    var isBusy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        // An icon-like tile, so its corner follows the app-icon proportion.
        let radius = Radius.iconTile(side: size)
        let active = activeState.isActiveWindow
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(active
                      ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.6)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.selectionFill(active: false)))
            if active {
                // A soft sheen on the accent tile (translucent, not a surface of its own).
                RoundedRectangle(cornerRadius: Radius.nested(in: radius, padding: 2), style: .continuous)
                    .fill(LinearGradient(colors: [OnAccent.color.opacity(0.35), OnAccent.color.opacity(0)],
                                         startPoint: .top, endPoint: .center))
                    .padding(2)
            }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(active ? OnAccent.color.opacity(0.35) : Color(nsColor: .separatorColor), lineWidth: 1)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(active ? OnAccent.color : Color.secondary)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, options: .repeating, isActive: isBusy && !reduceMotion)
        }
        .frame(width: size, height: size)
        .modifier(DepthShadow(radius: size * 0.16, y: size * 0.07))
        .accessibilityHidden(true)
    }
}

/// White-on-accent, from the system (the text colour of a selected row), not a white we pick.
enum OnAccent {
    static var color: Color { Color(nsColor: .alternateSelectedControlTextColor) }
}

/// A shadow that reads in both appearances: a soft accent glow in light, darker and tighter in
/// dark (a light glow would read as a halo), neutral in a background window.
struct DepthShadow: ViewModifier {
    let radius: CGFloat
    let y: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var activeState

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.shadow(color: .black.opacity(0.45), radius: radius * 0.5, y: y * 0.6) // lint:allow shadow colour, dark mode only
        } else if activeState.isActiveWindow {
            content.shadow(color: Color.accentColor.opacity(0.35), radius: radius, y: y)
        } else {
            content.shadow(color: .black.opacity(0.12), radius: radius * 0.6, y: y * 0.6) // lint:allow shadow colour
        }
    }
}

/// A soft glow of the accent colour behind a module page (fainter and grey in a background
/// window).
struct ModuleBackground: View {
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let active = activeState.isActiveWindow
        RadialGradient(colors: [Color.windowAccent(active: active).opacity(active ? 0.14 : 0.06), .clear],
                       center: .center, startRadius: 10, endRadius: 520)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The big round button at the bottom centre of a module page (Scan, Stop, Clean).
struct RoundActionButton: View {
    let title: String
    var isBusy = false
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(RoundButtonStyle(isBusy: isBusy))
            .help(help ?? title)
    }
}

/// Accent with white text in the key window; in a background window it turns grey with label
/// text, the way a default button does.
struct RoundButtonStyle: ButtonStyle {
    var isBusy = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    func makeBody(configuration: Configuration) -> some View {
        let active = activeState.isActiveWindow
        configuration.label
            .font(.headline)
            .foregroundStyle(active ? OnAccent.color : Color.primary)
            .frame(width: 80, height: 80)
            .background {
                Circle().fill(active
                              ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                                             startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.selectionFill(active: false)))
            }
            .overlay {
                Circle().strokeBorder(active ? OnAccent.color.opacity(0.35) : Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .padding(Spacing.xs)
            .background { Circle().fill(Color.windowAccent(active: active).opacity(0.18)) }
            .overlay {
                if isBusy { BusyRing(reduceMotion: reduceMotion, active: active) }
            }
            .modifier(DepthShadow(radius: 12, y: 4))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Circle())
    }
}

/// An arc going round the button while something runs (still when Reduce Motion is on).
private struct BusyRing: View {
    let reduceMotion: Bool
    var active = true
    @State private var angle = 0.0

    var body: some View {
        // Centred in the 4 pt halo around the button (inset 2 for a 3 pt line), not straddling
        // its outer edge.
        Circle()
            .inset(by: 2)
            .trim(from: 0, to: 0.25)
            .stroke(Color.windowAccent(active: active), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { angle = 360 }
            }
            .accessibilityHidden(true)
    }
}

/// One line in an intro's list of what the module covers.
struct ModuleFeature: Identifiable {
    var id: String { title }
    let systemImage: String
    let title: String
}

/// A module's first screen: hero on the left, what it does on the right, the big button below.
struct ModuleIntro<Accessory: View>: View {
    @Environment(\.controlActiveState) private var activeState
    let systemImage: String
    let title: String
    let subtitle: String
    var features: [ModuleFeature] = []
    var buttonTitle = "Scan"
    var buttonHelp: String?
    let action: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        ZStack {
            ModuleBackground()
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.l)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.xxl) {
                        ModuleHero(systemImage: systemImage)
                        text(alignment: .leading)
                            .frame(maxWidth: 340, alignment: .leading)
                    }
                    VStack(spacing: Spacing.l) {
                        ModuleHero(systemImage: systemImage, size: 120)
                        text(alignment: .center)
                    }
                }
                .padding(.horizontal, Spacing.xl)
                Spacer(minLength: Spacing.l)
                accessory
                    .padding(.bottom, Spacing.m)
                RoundActionButton(title: buttonTitle, help: buttonHelp, action: action)
                    .keyboardShortcut(.defaultAction)
                    .padding(.bottom, Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func text(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Spacing.m) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if !features.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(features) { feature in
                        Label {
                            Text(feature.title)
                        } icon: {
                            Image(systemName: feature.systemImage)
                                .foregroundStyle(Color.windowAccent(activeState))
                                .frame(width: 22)
                        }
                        .font(.body.weight(.medium))
                    }
                }
                .padding(.top, Spacing.xs)
            }
        }
    }
}

/// The screen while a module scans: hero, what it's doing, where it's looking, Stop.
struct ModuleScanning: View {
    let systemImage: String
    let title: String
    var detail: String = ""
    var stopTitle = "Stop"
    var onStop: (() -> Void)?

    var body: some View {
        ZStack {
            ModuleBackground()
            VStack(spacing: Spacing.l) {
                Spacer()
                ModuleHero(systemImage: systemImage, isBusy: true)
                Text(title).font(.title.weight(.semibold))
                Text(detail.isEmpty ? " " : detail)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
                Spacer()
                if let onStop {
                    RoundActionButton(title: stopTitle, isBusy: true, action: onStop)
                        .keyboardShortcut(.cancelAction)
                        .padding(.bottom, Spacing.xl)
                } else {
                    ProgressView().controlSize(.large).padding(.bottom, Spacing.xxl)
                }
            }
            .padding(.horizontal, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// A button on a result tile.
struct TileAction: Identifiable {
    var id: String { title }
    let title: String
    var isProminent = false
    var isEnabled = true
    var help: String?
    let action: () -> Void
}

/// One result tile: "4.7 GB of junk / to clean" with Review and Clean.
struct TileModel: Identifiable {
    let id: String
    let systemImage: String
    /// The module or category ("Cleanup").
    let label: String
    /// The big value ("4.7 GB of junk").
    let value: String
    /// Under the value ("to clean").
    var caption: String = ""
    /// A sentence for the large tile.
    var detail: String?
    /// Include this tile in the page's main action.
    var isIncluded: Binding<Bool>?
    var actions: [TileAction] = []
    /// Greyed out (nothing found).
    var isQuiet = false
}

struct ResultTile: View {
    @Environment(\.controlActiveState) private var activeState
    let tile: TileModel
    var isLarge = false

    var body: some View {
        // Small tiles keep the value right under the header and the buttons on the bottom edge,
        // so tiles side by side line up whatever their captions' lengths. The large tile puts
        // its sentence first and the value just above the buttons.
        VStack(alignment: .leading, spacing: Spacing.s) {
            header
            if isLarge {
                if let detail = tile.detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.s)
                value
            } else {
                value
                Spacer(minLength: 0)
            }
            if !tile.actions.isEmpty {
                HStack(spacing: Spacing.s) {
                    Spacer(minLength: 0)
                    ForEach(tile.actions) { action in
                        Button(action.title, action: action.action)
                            .disabled(!action.isEnabled)
                            .help(action.help ?? action.title)
                            .controlSize(.regular)
                            .modifier(ProminentIf(isOn: action.isProminent))
                    }
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, minHeight: isLarge ? 240 : 130, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .fill(.background.opacity(0.6))
                .modifier(CardShadow())
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tile.label): \(tile.value) \(tile.caption)")
    }

    private var header: some View {
        HStack(alignment: .top) {
            if let included = tile.isIncluded {
                Toggle(isOn: included) {
                    Text(tile.label).font(.headline)
                }
                .toggleStyle(.checkbox)
                .help("Include \(tile.label) when you click the big button")
            } else {
                Text(tile.label).font(.headline)
            }
            Spacer()
            Image(systemName: tile.systemImage)
                .font(.system(size: isLarge ? 34 : 26, weight: .medium))
                .foregroundStyle(tile.isQuiet ? Color.secondary : Color.windowAccent(activeState))
                .symbolRenderingMode(.hierarchical)
                // One box height whatever the symbol, so every header (and the value under
                // it) is the same height in tiles side by side.
                .frame(height: isLarge ? 40 : 32, alignment: .top)
                .accessibilityHidden(true)
        }
    }

    private var value: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.value)
                .font((isLarge ? Font.title : Font.title2).weight(.semibold).monospacedDigit())
                .foregroundStyle(tile.isQuiet ? .secondary : .primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if !tile.caption.isEmpty {
                Text(tile.caption)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A card's shadow: faint and soft in light, darker and tighter in dark so it still reads.
struct CardShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        colorScheme == .dark
            ? content.shadow(color: .black.opacity(0.35), radius: 3, y: 1) // lint:allow shadow colour
            : content.shadow(color: .black.opacity(0.08), radius: 6, y: 2) // lint:allow shadow colour
    }
}

private struct ProminentIf: ViewModifier {
    let isOn: Bool
    func body(content: Content) -> some View {
        if isOn { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
    }
}

/// Tiles laid out like a mosaic: the first one tall on the left, the rest two by two.
struct TileMosaic: View {
    let tiles: [TileModel]

    var body: some View {
        if tiles.count <= 2 {
            HStack(alignment: .top, spacing: Spacing.m) {
                ForEach(tiles) { ResultTile(tile: $0, isLarge: true) }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            SplitRow(fraction: 0.36, spacing: Spacing.m) {
                ResultTile(tile: tiles[0], isLarge: true)
                let rest = Array(tiles.dropFirst())
                Grid(horizontalSpacing: Spacing.m, verticalSpacing: Spacing.m) {
                    ForEach(Array(stride(from: 0, to: rest.count, by: 2)), id: \.self) { start in
                        GridRow {
                            // An odd one out takes the whole row instead of leaving a hole.
                            ResultTile(tile: rest[start])
                                .gridCellColumns(start + 1 < rest.count ? 1 : 2)
                            if start + 1 < rest.count {
                                ResultTile(tile: rest[start + 1])
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Two views side by side: the first takes `fraction` of the width, both get the taller one's
/// height.
struct SplitRow: Layout {
    var fraction: CGFloat
    var spacing: CGFloat

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let first = ((total - spacing) * fraction).rounded()
        return (first, max(0, total - spacing - first))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let total = proposal.width ?? 700
        let (a, b) = widths(total)
        let height = max(subviews[0].sizeThatFits(ProposedViewSize(width: a, height: nil)).height,
                         subviews[1].sizeThatFits(ProposedViewSize(width: b, height: nil)).height)
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let (a, b) = widths(bounds.width)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: a, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + a + spacing, y: bounds.minY),
                          proposal: ProposedViewSize(width: b, height: bounds.height))
    }
}

/// The results screen: a headline, an optional "Review All" button, the tiles, and optionally
/// the big round button.
struct ModuleResults<Footer: View>: View {
    let headline: String
    var subheadline: String?
    var reviewAllTitle: String?
    var onReviewAll: (() -> Void)?
    let tiles: [TileModel]
    @ViewBuilder var footer: Footer

    var body: some View {
        ZStack {
            ModuleBackground()
            VStack(spacing: 0) {
                // The headline and the tiles stay together, centred in the space above the
                // button when they fit (no hole between them), and scroll when they don't.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: Spacing.xl) {
                            heading
                            TileMosaic(tiles: tiles)
                                .padding(.horizontal, Spacing.xl)
                        }
                        .padding(.vertical, Spacing.xl)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var heading: some View {
        VStack(spacing: Spacing.s) {
            Text(headline)
                .font(.title2.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.center)
            if let subheadline {
                Text(subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let reviewAllTitle, let onReviewAll {
                Button(reviewAllTitle, action: onReviewAll)
                    .controlSize(.large)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.xl)
    }
}

/// One line on the completion screen.
struct DoneLine: Identifiable {
    var id: String { title + subtitle }
    let systemImage: String
    let title: String
    let subtitle: String
    var isFailure = false
}

/// After a module's action: what happened, with View History, Review More and Done.
struct ModuleDone<Actions: View>: View {
    @Environment(\.controlActiveState) private var activeState
    let systemImage: String
    let title: String
    let lines: [DoneLine]
    @ViewBuilder var actions: Actions

    var body: some View {
        ZStack {
            ModuleBackground()
            VStack(spacing: Spacing.xl) {
                HStack(spacing: Spacing.xxl) {
                    ModuleHero(systemImage: systemImage, size: 120)
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        Text(title).font(.largeTitle.weight(.semibold))
                        ForEach(lines) { line in
                            HStack(alignment: .top, spacing: Spacing.s) {
                                Image(systemName: line.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(line.isFailure ? Color.orange : Color.windowAccent(activeState))
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(line.title).font(.headline)
                                    Text(line.subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Hero and text start at the card's padding, like the buttons under them
                // (centred, they floated 65 pt in from the buttons' edge).
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack { actions }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 720)
            .background {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(.background.opacity(0.6))
            }
            .overlay { RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
