import SlopappCore
import SlopKit
import SwiftUI

/// The app page's screenshots (docs/screenshots.md): one large 16:10 image at a time with the
/// next one peeking in, the title and caption under it as real text, arrows on hover, page
/// dots, ←/→ when focused, and a click for the full-size viewer. Light or dark set to match
/// the window. Nothing at all when the app has no set.
struct ShotGallery: View {
    let app: FeedApp
    let images: ShotImages
    /// The page's size, for the viewer sheet.
    let pageSize: CGSize

    @State private var current: String?
    @State private var width: CGFloat = 0
    @State private var hovering = false
    @State private var viewing: ViewerPage?
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shots: [FeedShot] { app.shots }
    private var appearance: FeedShot.Appearance { colorScheme == .dark ? .dark : .light }
    private var paging: GalleryPaging {
        GalleryPaging(count: shots.count, index: shots.firstIndex { $0.id == current } ?? 0)
    }

    /// Space between images; the page's trailing margin shows the next one.
    private let gap: CGFloat = Spacing.m
    static let aspect: CGFloat = 1800.0 / 2880.0

    var body: some View {
        let paging = paging
        VStack(alignment: .leading, spacing: Spacing.m) {
            strip(paging)
            footer(paging)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenshots")
        .sheet(item: $viewing) { page in
            ShotViewer(app: app, images: images, index: page.index, appearance: appearance, pageSize: pageSize) { index in
                scroll(to: index, animated: false)
            }
        }
    }

    // MARK: The strip

    /// As wide as the page, but never so tall that the title and caption fall out of a short
    /// window: then narrower, and more of the next one shows.
    private var imageWidth: CGFloat {
        // The page's header and the gallery's own text take about this much of the height.
        let tallest = max(Self.minimumHeight, pageSize.height - Self.reservedHeight)
        return max(240, min(width, (tallest / Self.aspect).rounded()))
    }

    static let minimumHeight: CGFloat = 260
    static let reservedHeight: CGFloat = 300

    private func strip(_ paging: GalleryPaging) -> some View {
        let imageWidth = imageWidth
        let imageHeight = (imageWidth * Self.aspect).rounded()
        return ScrollView(.horizontal) {
            LazyHStack(spacing: gap) {
                ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                    let isCurrent = index == paging.index
                    Button {
                        if isCurrent {
                            viewing = ViewerPage(index: index)
                        } else {
                            scroll(to: index)
                        }
                    } label: {
                        ShotImage(app: app, shot: shot, appearance: appearance, size: .page,
                                  maxPixel: Int(imageWidth * displayScale), images: images)
                            .frame(width: imageWidth, height: imageHeight)
                            .overlay {
                                // Our own focus ring, around the image in view (the system's would
                                // wrap the whole strip, peek included).
                                if focused && isCurrent {
                                    RoundedRectangle(cornerRadius: ShotImage.radius + Self.ringGap, style: .continuous)
                                        .strokeBorder(Color.accentColor, lineWidth: 3)
                                        .padding(-Self.ringGap)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Screenshot \(index + 1) of \(shots.count): \(shot.accessibilityText)")
                    .accessibilityHint(isCurrent ? "Opens it full size" : "Shows it")
                    .id(shot.id)
                }
            }
            .scrollTargetLayout()
            // Room for the focus ring (the scroll view clips to its bounds).
            .padding(.vertical, Self.ringGap + 3)
        }
        .contentMargins(.horizontal, PageLayout.margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current, anchor: .leading)
        .scrollIndicators(.never)
        .frame(height: imageHeight + 2 * (Self.ringGap + 3))
        .padding(.vertical, -(Self.ringGap + 3))
        // Full width of the panel: the page's margins hold the peeking neighbour.
        .padding(.horizontal, -PageLayout.margin)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay(alignment: .leading) {
            arrows(paging, height: imageHeight)
                .frame(width: imageWidth)
                .padding(.leading, PageLayout.margin)
        }
        .onHover { hovering = $0 }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        // ←/→ also work without clicking the gallery first, unless a field or list has focus.
        .modifier(ArrowKeys(inSheet: false) { step($0) == .handled })
        .onKeyPress(.space) {
            viewing = ViewerPage(index: paging.index)
            return .handled
        }
        .onChange(of: app.slug) { current = nil }
        .onChange(of: paging.index, initial: true) { prefetch() }
        .onChange(of: colorScheme) { prefetch() }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: _ = step(1)
            case .decrement: _ = step(-1)
            @unknown default: break
            }
        }
    }

    static let ringGap: CGFloat = 3

    /// ‹ and › over the image in view, while the pointer is over the gallery or it has focus.
    private func arrows(_ paging: GalleryPaging, height: CGFloat) -> some View {
        let shown = hovering || focused
        return HStack {
            GalleryArrow(direction: .back, enabled: paging.canGoBack) { _ = step(-1) }
                .opacity(shown && paging.canGoBack ? 1 : 0)
            Spacer()
            GalleryArrow(direction: .forward, enabled: paging.canGoForward) { _ = step(1) }
                .opacity(shown && paging.canGoForward ? 1 : 0)
        }
        .padding(.horizontal, Spacing.m)
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: shown)
    }

    // MARK: Title, caption, dots

    private func footer(_ paging: GalleryPaging) -> some View {
        let shot = shots.indices.contains(paging.index) ? shots[paging.index] : nil
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(shot?.title ?? "").font(.headline)
                Text(shot?.caption ?? "")
                    .foregroundStyle(.secondary)
                    // Two lines kept, so paging between short and long captions doesn't move the page.
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if shots.count > 1 {
                PageDots(count: shots.count, index: paging.index, titles: shots.map(\.title)) { scroll(to: $0) }
            }
        }
    }

    // MARK: Paging

    private func step(_ delta: Int) -> KeyPress.Result {
        var paging = paging
        let before = paging.index
        delta < 0 ? paging.goBack() : paging.goForward()
        guard paging.index != before else { return .ignored }
        scroll(to: paging.index)
        return .handled
    }

    private func scroll(to index: Int, animated: Bool = true) {
        guard shots.indices.contains(index) else { return }
        // Under 250 ms; with Reduce Motion it moves without the slide.
        withAnimation(animated && !reduceMotion ? .smooth(duration: 0.25) : nil) { current = shots[index].id }
    }

    /// The image in view and its neighbours, at the size they're drawn.
    private func prefetch() {
        let pixels = Int(imageWidth * displayScale)
        for index in paging.prefetch {
            images.load(shots[index].url(appearance, ShotImage.Size.page.feedSize(forPixels: pixels)), app: app, maxPixel: pixels)
        }
    }
}

struct ViewerPage: Identifiable {
    let index: Int
    var id: Int { index }
}

/// One screenshot, or a quiet placeholder while it loads (and if it can't).
struct ShotImage: View {
    let app: FeedApp
    let shot: FeedShot
    let appearance: FeedShot.Appearance
    let size: Size
    let maxPixel: Int
    let images: ShotImages

    static let radius = Radius.l

    enum Size {
        case page, full

        /// The 1440-wide copy is enough up to 1440 pixels; past that, the master.
        func feedSize(forPixels pixels: Int) -> FeedShot.Size {
            self == .full || pixels > 1440 ? .full : .page
        }
    }

    var body: some View {
        let url = shot.url(appearance, size.feedSize(forPixels: maxPixel))
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        ZStack {
            shape.fill(.quaternary.opacity(0.6))
            switch images.phase(url, maxPixel: maxPixel) {
            case .loaded(let image):
                picture(image)
            case .failed:
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            case .loading, nil:
                // A new size is loading (the window was resized): keep showing the old one.
                if let image = images.anySize(of: url) { picture(image) }
            }
        }
        .clipShape(shape)
        .hairlineBorder(shape)
        .contentShape(shape)
        .animation(.easeOut(duration: 0.15), value: images.phase(url, maxPixel: maxPixel) != nil)
        .onAppear { images.load(url, app: app, maxPixel: maxPixel) }
        // The URL, or the size it's decoded at (a resize can cross a size bucket).
        .onChange(of: ShotImages.key(url, maxPixel: maxPixel)) { images.load(url, app: app, maxPixel: maxPixel) }
    }

    private func picture(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .transition(.opacity)
    }
}

/// A round ‹ or › button over the image.
struct GalleryArrow: View {
    enum Direction { case back, forward }
    let direction: Direction
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .back ? "chevron.backward" : "chevron.forward")
                .font(.title3.weight(.semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(!enabled)
        .help(direction == .back ? "Previous screenshot (←)" : "Next screenshot (→)")
        .accessibilityLabel(direction == .back ? "Previous Screenshot" : "Next Screenshot")
    }
}

/// A dot per screenshot; the current one is filled. Each is a button for VoiceOver and the mouse.
struct PageDots: View {
    let count: Int
    let index: Int
    let titles: [String]
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<count, id: \.self) { dot in
                Button { select(dot) } label: {
                    Circle()
                        .fill(dot == index ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.45)))
                        .frame(width: 7, height: 7)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Screenshot \(dot + 1) of \(count)\(titles.indices.contains(dot) ? ": \(titles[dot])" : "")")
                .accessibilityAddTraits(dot == index ? .isSelected : [])
            }
        }
    }
}

/// The full-size viewer: the 2880-wide image as large as the window allows, with the same
/// title, caption, arrows, dots and ←/→. Esc or Done closes it.
struct ShotViewer: View {
    let app: FeedApp
    let images: ShotImages
    @State var index: Int
    let appearance: FeedShot.Appearance
    let pageSize: CGSize
    /// Where it was left, so the page's gallery follows.
    let onClose: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    init(app: FeedApp, images: ShotImages, index: Int, appearance: FeedShot.Appearance, pageSize: CGSize,
         onClose: @escaping (Int) -> Void) {
        self.app = app
        self.images = images
        _index = State(initialValue: index)
        self.appearance = appearance
        self.pageSize = pageSize
        self.onClose = onClose
    }

    private var paging: GalleryPaging { GalleryPaging(count: app.shots.count, index: index) }

    var body: some View {
        let width = max(640, min(pageSize.width - 2 * Spacing.xxl, (pageSize.height - 150) / ShotGallery.aspect, 1440)).rounded()
        let shot = app.shots[paging.index]
        VStack(alignment: .leading, spacing: Spacing.l) {
            ShotImage(app: app, shot: shot, appearance: appearance, size: .full,
                      maxPixel: Int(width * displayScale), images: images)
                .frame(width: width, height: (width * ShotGallery.aspect).rounded())
                .overlay {
                    HStack {
                        GalleryArrow(direction: .back, enabled: paging.canGoBack) { go(-1) }
                            .opacity(paging.canGoBack ? 1 : 0)
                        Spacer()
                        GalleryArrow(direction: .forward, enabled: paging.canGoForward) { go(1) }
                            .opacity(paging.canGoForward ? 1 : 0)
                    }
                    .padding(.horizontal, Spacing.m)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Screenshot \(paging.index + 1) of \(paging.count): \(shot.accessibilityText)")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(shot.title).font(.headline)
                    Text(shot.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if paging.count > 1 {
                    PageDots(count: paging.count, index: paging.index, titles: app.shots.map(\.title)) { index = $0 }
                }
                Button("Done") { close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { go(-1); return .handled }
        .onKeyPress(.rightArrow) { go(1); return .handled }
        .modifier(ArrowKeys(inSheet: true) { go($0); return true })
        .onExitCommand { close() }
        .onChange(of: index, initial: true) {
            // The next one, so paging forward is instant.
            if paging.canGoForward {
                let next = app.shots[paging.index + 1]
                images.load(next.url(appearance, .full), app: app, maxPixel: Int(width * displayScale))
            }
        }
    }

    private func go(_ delta: Int) {
        var paging = paging
        delta < 0 ? paging.goBack() : paging.goForward()
        index = paging.index
    }

    private func close() {
        onClose(index)
        dismiss()
    }
}

/// ← and → for a gallery whose window is key, without it needing keyboard focus: ignored
/// while a text field, list or table has focus (they use the arrows), and with modifiers.
/// `inSheet` picks the viewer sheet's window instead of the page's.
struct ArrowKeys: ViewModifier {
    let inSheet: Bool
    let action: @MainActor (Int) -> Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let key = event.keyCode, flags = event.modifierFlags
                    let handled = MainActor.assumeIsolated { handle(key: key, flags: flags) }
                    return handled ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    @MainActor
    private func handle(key: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard key == 123 || key == 124,
              flags.intersection([.command, .option, .control, .shift]).isEmpty,
              let window = NSApp.keyWindow, (window.sheetParent != nil) == inSheet,
              inSheet || window.attachedSheet == nil else { return false }
        if let responder = window.firstResponder,
           responder is NSText || responder is NSTableView || responder is NSCollectionView || responder is NSTextField {
            return false
        }
        return action(key == 123 ? -1 : 1)
    }
}
