import AppKit
import PDFKit
import PaperCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Bindable var model: DocumentModel
    let actions: SidebarActions

    var body: some View {
        VStack(spacing: 0) {
            switch model.sidebarMode {
            case .thumbnails, .outline, .annotations:
                Picker("Sidebar", selection: $model.sidebarMode) {
                    Label("Thumbnails", systemImage: "square.grid.2x2").tag(SidebarMode.thumbnails)
                    if model.hasOutline { Label("Outline", systemImage: "list.bullet.indent").tag(SidebarMode.outline) }
                    Label("Notes", systemImage: "text.bubble").tag(SidebarMode.annotations)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .labelsHidden()
                .fixedSize()
                .padding(.horizontal, Spacing.s)
                .frame(maxWidth: .infinity)
                .frame(height: PaperMetrics.barHeight)
                .disabled(model.isLocked)
                Hairline()
            case .search, .redact:
                EmptyView()
            }
            Group {
                if model.isLocked {
                    Color.clear
                } else {
                    switch model.sidebarMode {
                    case .thumbnails: ThumbnailList(model: model, actions: actions)
                    case .outline: OutlineList(pdf: model.pdf, actions: actions)
                    case .annotations: AnnotationList(model: model, actions: actions)
                    case .search: SearchResults(model: model, actions: actions)
                    case .redact: FindAndRedact(model: model, actions: actions)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 160)
    }
}

// MARK: Thumbnails

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 400 }

    func image(for page: PDFPage, version: Int, width: CGFloat) -> NSImage? {
        cache.object(forKey: key(page, version, width))
    }

    func render(_ page: PDFPage, version: Int, width: CGFloat) -> NSImage {
        let box = page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        let size = NSSize(width: width * 2, height: width * 2 * rotated.height / max(rotated.width, 1))
        let image = page.thumbnail(of: size, for: .cropBox)
        cache.setObject(image, forKey: key(page, version, width))
        return image
    }

    private func key(_ page: PDFPage, _ version: Int, _ width: CGFloat) -> NSString {
        "\(ObjectIdentifier(page).hashValue)-\(version)-\(Int(width))" as NSString
    }
}

struct ThumbnailList: View {
    @Bindable var model: DocumentModel
    let actions: SidebarActions

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $model.selectedPages) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, item in
                    ThumbnailRow(page: item.page, number: index + 1, count: model.pages.count,
                                 version: model.pageVersions[item.id, default: 0],
                                 isCurrent: index == model.currentPageIndex,
                                 isSelected: model.selectedPages.contains(item.id))
                        .tag(item.id)
                        .id(item.id)
                }
                .onMove { source, destination in
                    guard !model.isReadOnly else { return }
                    actions.movePages(source, destination)
                }
                .onInsert(of: [.fileURL]) { index, providers in
                    guard !model.isReadOnly else { return }
                    Task { @MainActor in
                        var urls: [URL] = []
                        for provider in providers {
                            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                               let fileURL = URL(dataRepresentation: url, relativeTo: nil) {
                                urls.append(fileURL)
                            }
                        }
                        if !urls.isEmpty { actions.insertFiles(urls, index) }
                    }
                }
            }
            .listStyle(.sidebar)
            // The rows draw their own selection (a ring around the page), not the list's pill.
            .background(ListSelectionHighlightRemover())
            .accessibilityLabel("Pages")
            .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
                if !ids.isEmpty {
                    let indexes = IndexSet(ids.compactMap { id in model.pages.firstIndex { $0.id == id } })
                    Button("Rotate Left") { actions.rotate(indexes, -90) }.disabled(model.isReadOnly)
                    Button("Rotate Right") { actions.rotate(indexes, 90) }.disabled(model.isReadOnly)
                    Divider()
                    Button(indexes.count == 1 ? "Extract Page…" : "Extract \(indexes.count) Pages…") {
                        model.selectedPages = ids
                        actions.extract()
                    }
                    Divider()
                    Button(indexes.count == 1 ? "Delete Page" : "Delete \(indexes.count) Pages") {
                        model.selectedPages = ids
                        actions.deletePages()
                    }
                    .disabled(model.isReadOnly || indexes.count >= model.pages.count)
                }
            }
            .onDeleteCommand {
                guard !model.isReadOnly else { return }
                actions.deletePages()
            }
            .onChange(of: model.selectedPages) { _, selection in
                guard selection.count == 1, let id = selection.first,
                      let index = model.pages.firstIndex(where: { $0.id == id }), index != model.currentPageIndex else { return }
                actions.goToPage(index)
            }
            .onChange(of: model.currentPageIndex) { _, index in
                guard index < model.pages.count else { return }
                proxy.scrollTo(model.pages[index].id)
            }
        }
    }
}

struct ThumbnailRow: View {
    let page: PDFPage
    let number: Int
    let count: Int
    let version: Int
    let isCurrent: Bool
    let isSelected: Bool
    @State private var image: NSImage?
    @Environment(\.appearsActive) private var appearsActive
    static let width = PaperMetrics.thumbnailWidth

    var body: some View {
        VStack(spacing: Spacing.s) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // A blank sheet while the thumbnail renders: paper is white in both modes.
                    Rectangle().fill(.white).aspectRatio(aspect, contentMode: .fit)
                }
            }
            .frame(width: Self.width)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            .overlay {
                RoundedRectangle(cornerRadius: PaperMetrics.thumbnailRingRadius)
                    .strokeBorder(appearsActive ? Color.accentColor : Color(nsColor: .systemGray), lineWidth: PaperMetrics.thumbnailRingWidth)
                    .padding(-PaperMetrics.thumbnailRingRadius)
                    .opacity(isSelected ? 1 : 0)
            }
            Text("\(number)")
                .font(.caption)
                .monospacedDigit()
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(numberStyle)
                .padding(.horizontal, Spacing.xs + 2) // lint:allow capsule padding: 6 pt around a caption digit
                .padding(.vertical, 1)
                .background(Capsule().fill(ringColor).opacity(isSelected ? 1 : 0))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(number) of \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: version) {
            if let cached = ThumbnailCache.shared.image(for: page, version: version, width: Self.width) {
                image = cached
                return
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            image = ThumbnailCache.shared.render(page, version: version, width: Self.width)
        }
    }

    private var numberStyle: AnyShapeStyle {
        if isSelected {
            return appearsActive ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor)) : AnyShapeStyle(.primary)
        }
        return isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    /// The number's capsule: accent in the key window, the list's inactive selection grey
    /// otherwise (the ring uses system gray instead: a thin line needs the stronger grey).
    private var ringColor: Color {
        appearsActive ? Color.accentColor : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    private var aspect: CGFloat {
        let box = page.bounds(for: .cropBox)
        return page.rotation % 180 == 0 ? box.width / max(box.height, 1) : box.height / max(box.width, 1)
    }
}

// MARK: Outline

struct OutlineNode: Identifiable {
    let id = UUID()
    let title: String
    let destination: PDFDestination?
    let children: [OutlineNode]?

    static func build(_ outline: PDFOutline) -> [OutlineNode] {
        (0..<outline.numberOfChildren).compactMap { index in
            guard let child = outline.child(at: index) else { return nil }
            let kids = build(child)
            return OutlineNode(title: child.label ?? "Untitled", destination: child.destination,
                               children: kids.isEmpty ? nil : kids)
        }
    }
}

struct OutlineList: View {
    let pdf: PDFDocument
    let actions: SidebarActions
    @State private var nodes: [OutlineNode] = []

    var body: some View {
        List(nodes, children: \.children) { node in
            Button {
                if let destination = node.destination { actions.goToOutline(destination) }
            } label: {
                Text(node.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Outline")
        .onAppear { nodes = pdf.outlineRoot.map(OutlineNode.build) ?? [] }
    }
}

// MARK: Annotations

struct AnnotationItem: Identifiable {
    let id: ObjectIdentifier
    let annotation: PDFAnnotation
    let pageIndex: Int
    let title: String
    let detail: String?
    let symbol: String
}

struct AnnotationList: View {
    @Bindable var model: DocumentModel
    let actions: SidebarActions

    var body: some View {
        let items = collect()
        VStack(spacing: 0) {
            if items.isEmpty {
                FillingUnavailable("No Notes Yet", systemImage: "text.bubble",
                                       description: Text("Highlights, notes, shapes and marks you add show up here."))
            } else {
                List(items) { item in
                    Button { actions.selectAnnotation(item.annotation) } label: {
                        HStack(alignment: .top, spacing: Spacing.s) {
                            Image(systemName: item.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(item.annotation.color.alphaComponent < 0.1 ? Color.secondary : Color.readable(item.annotation.color.withAlphaComponent(1), on: .windowBackgroundColor, target: ReadableColor.symbolTarget))
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.callout)
                                if let detail = item.detail {
                                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
                            Spacer(minLength: 0)
                            Text("\(item.pageIndex + 1)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.title), page \(item.pageIndex + 1)\(item.detail.map { ": \($0)" } ?? "")")
                }
                .listStyle(.sidebar)
                Hairline()
                Button("Copy Highlights & Notes", action: actions.copyNotes)
                    .controlSize(.small)
                    .padding(Spacing.s)
            }
        }
    }

    private func collect() -> [AnnotationItem] {
        _ = model.annotationsRevision
        var items: [AnnotationItem] = []
        for index in 0..<model.pdf.pageCount {
            guard let page = model.pdf.page(at: index) else { continue }
            for annotation in page.annotations where AnnotationGeometry.isEditable(annotation) {
                let (title, symbol): (String, String)
                if RedactionMarks.isMark(annotation) {
                    (title, symbol) = ("Redaction mark", "rectangle.dashed")
                } else if Signature.isSignature(annotation) {
                    (title, symbol) = ("Signature", "signature")
                } else {
                    switch annotation.type ?? "" {
                    case "Highlight": (title, symbol) = ("Highlight", "highlighter")
                    case "Underline": (title, symbol) = ("Underline", "underline")
                    case "StrikeOut": (title, symbol) = ("Strikethrough", "strikethrough")
                    case "Text": (title, symbol) = ("Note", "note.text")
                    case "FreeText": (title, symbol) = ("Text box", "character.textbox")
                    case "Ink": (title, symbol) = ("Drawing", "scribble")
                    case "Square": (title, symbol) = ("Rectangle", "rectangle")
                    case "Circle": (title, symbol) = ("Oval", "circle")
                    case "Line": (title, symbol) = (annotation.endLineStyle == .none ? "Line" : "Arrow", "arrow.up.right")
                    default: (title, symbol) = (annotation.type ?? "Annotation", "pencil")
                    }
                }
                var detail = annotation.contents.flatMap { $0.isEmpty || RedactionMarks.isMark(annotation) ? nil : $0 }
                if AnnotationGeometry.isMarkup(annotation) {
                    let quote = NotesExport.quotedText(annotation, on: page)
                    detail = [quote.map { "“\($0)”" }, detail].compactMap { $0 }.joined(separator: "\n")
                }
                items.append(AnnotationItem(id: ObjectIdentifier(annotation), annotation: annotation, pageIndex: index,
                                            title: title, detail: detail?.isEmpty == true ? nil : detail, symbol: symbol))
            }
        }
        return items
    }
}

// MARK: Search

struct PanelHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
                    .help("Close")
                    .accessibilityLabel("Close \(title)")
            }
            .padding(.horizontal, Spacing.m)
            .frame(height: PaperMetrics.barHeight)
            Hairline()
        }
    }
}

struct SearchResults: View {
    @Bindable var model: DocumentModel
    let actions: SidebarActions

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Search Results", close: actions.closeSearch)
            if !model.hasTextLayer {
                FillingUnavailable("No Text to Search", systemImage: "doc.viewfinder",
                                       description: Text("This document has no text layer. It looks like a scan."))
            } else if model.searchHits.isEmpty, !model.isSearching {
                ContentUnavailableView.search(text: model.searchedQuery).frame(maxHeight: .infinity)
            } else {
                HStack {
                    Text(summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    if model.isSearching { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                List(selection: Binding(get: { model.searchIndex }, set: { if let index = $0 { actions.selectHit(index) } })) {
                    ForEach(Array(model.searchHits.enumerated()), id: \.offset) { index, hit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Page \(hit.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                            Text(highlighted(hit)).font(.callout).lineLimit(2)
                        }
                        .tag(index)
                        .accessibilityElement(children: .combine)
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel("Search results")
                if !model.isReadOnly, !model.searchHits.isEmpty {
                    Hairline()
                    HStack(spacing: Spacing.s) {
                        Button {
                            actions.highlightAll()
                        } label: {
                            Label(model.searchHits.count == 1 ? "Highlight Result" : "Highlight All \(model.searchHits.count)",
                                  systemImage: "highlighter")
                        }
                        Circle()
                            .fill(Color(nsColor: model.highlightColor.nsColor))
                            .overlay(Circle().strokeBorder(.separator))
                            .frame(width: 12, height: 12)
                            .help("\(model.markupStyle.title), \(model.highlightColor.title). Change it in the Highlight menu.")
                            .accessibilityLabel("Highlight color \(model.highlightColor.title)")
                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)
                    .padding(Spacing.s)
                }
            }
        }
    }

    private var summary: String {
        let count = model.searchHits.count
        return count == 1 ? "1 result" : "\(count) results"
    }

    private func highlighted(_ hit: TextHit) -> AttributedString {
        var text = AttributedString(hit.context)
        if let range = text.range(of: hit.matched, options: .caseInsensitive) {
            text[range].font = .callout.bold()
        }
        return text
    }
}

// MARK: Find and Redact

struct FindAndRedact: View {
    @Bindable var model: DocumentModel
    let actions: SidebarActions
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Find and Redact", close: actions.closeRedact)
            VStack(alignment: .leading, spacing: Spacing.s) {
                TextField("Text to redact", text: $model.redactQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(actions.findForRedaction)
                Toggle("Match case", isOn: $model.redactOptions.caseSensitive)
                Toggle("Whole words only", isOn: $model.redactOptions.wholeWord)
                Button("Find All", action: actions.findForRedaction)
                    .disabled(model.redactQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.small)
            .padding(Spacing.m)
            Hairline()
            if !model.hasTextLayer {
                FillingUnavailable("No Text to Find", systemImage: "doc.viewfinder",
                                       description: Text("This document looks like a scan. Use the Redact tool (⌘9) to drag boxes over what to hide."))
            } else if model.redactSearched, model.redactHits.isEmpty {
                ContentUnavailableView.search(text: model.redactQuery).frame(maxHeight: .infinity)
            } else if model.redactHits.isEmpty {
                FillingUnavailable("Find Every Occurrence", systemImage: "rectangle.and.text.magnifyingglass",
                                       description: Text("Search for a name or number, review the results, then mark them all."))
            } else {
                HStack {
                    Text("\(model.redactChecked.count) of \(model.redactHits.count) selected").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button(model.redactChecked.count == model.redactHits.count ? "Select None" : "Select All") {
                        model.redactChecked = model.redactChecked.count == model.redactHits.count ? [] : Set(model.redactHits.map(\.id))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                List(model.redactHits) { hit in
                    Toggle(isOn: Binding(
                        get: { model.redactChecked.contains(hit.id) },
                        set: { on in if on { model.redactChecked.insert(hit.id) } else { model.redactChecked.remove(hit.id) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Page \(hit.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                            Text(hit.context).font(.callout).lineLimit(2)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .listStyle(.sidebar)
                .accessibilityLabel("Results to redact")
                Hairline()
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Button(model.redactChecked.count == 1 ? "Mark 1 Result" : "Mark \(model.redactChecked.count) Results",
                           action: actions.markRedactionHits)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.redactChecked.isEmpty)
                    Text("Marked text stays until you choose Apply Redactions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { focused = true }
    }
}

/// An empty state that takes the rest of the panel, so the panel's controls stay at the top.
struct FillingUnavailable: View {
    let title: String
    let systemImage: String
    let description: Text

    init(_ title: String, systemImage: String, description: Text) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: description)
            .frame(maxHeight: .infinity)
    }
}

/// Turns off the selection pill of the list it sits behind, for lists whose rows draw their own
/// selection (the page thumbnails' ring). Selection, keyboard navigation, drag and the context
/// menu keep working; only the drawing changes. If AppKit's structure ever changes, the list
/// simply keeps its standard pill.
struct ListSelectionHighlightRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) { (view as? Probe)?.apply() }

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            DispatchQueue.main.async { [weak self] in
                var ancestor = self?.superview
                for _ in 0..<6 {
                    guard let view = ancestor else { return }
                    if let table = Self.firstTable(in: view) {
                        if table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
                        return
                    }
                    ancestor = view.superview
                }
            }
        }

        private static func firstTable(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for subview in view.subviews {
                if let table = firstTable(in: subview) { return table }
            }
            return nil
        }
    }
}
