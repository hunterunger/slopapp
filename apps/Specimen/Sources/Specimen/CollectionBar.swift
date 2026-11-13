import SlopKit
import SpecimenCore
import SwiftUI

/// The bar above a library folder's or a document's fonts: what's there, how much is on, and
/// one place to turn it all on (for good or until you quit) or off. Documents also say which
/// of their fonts are missing.
struct CollectionBar: View {
    @Bindable var model: AppModel
    @State private var showsDocumentFonts = false

    static func applies(to item: SidebarItem) -> Bool {
        switch item {
        case .folder, .document: true
        default: false
        }
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(summary)
                    .font(.callout)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.m)
            if case .document = model.sidebar {
                Button("Fonts in Document…") { showsDocumentFonts = true }
                    .popover(isPresented: $showsDocumentFonts, arrowEdge: .bottom) {
                        if case .document(let id) = model.sidebar { DocumentFontsList(model: model, documentID: id) }
                    }
                    .help("Every font the document names, and where each one is")
            }
            CollectionActivationButtons(model: model, item: model.sidebar)
        }
        .controlSize(.small)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    private var icon: String {
        if case .document = model.sidebar { return "doc.text" }
        if case .folder(let path) = model.sidebar, model.offlineFolders.contains(path) { return "externaldrive.badge.exclamationmark" }
        return "folder"
    }

    private var summary: String {
        switch model.sidebar {
        case .folder(let path):
            let faces = model.facesIn(folder: path)
            let families = Set(faces.map(\.familyName)).count
            let on = faces.filter(\.isEnabled)
            let temporary = on.filter(\.isTemporary).count
            var parts = [families == 1 ? "1 family" : "\(families.formatted()) families"]
            parts.append(on.isEmpty ? "none active" : on.count == faces.count ? "all active" : "\(on.count.formatted()) of \(faces.count.formatted()) styles active")
            if temporary > 0 { parts.append("\(temporary.formatted()) until you quit") }
            return parts.joined(separator: " · ")
        case .document(let id):
            let matches = model.documentMatches[id] ?? []
            guard model.documentProblems[id] == nil else { return model.documentProblems[id] ?? "" }
            let active = matches.filter { $0.status == .active }.count
            let inLibrary = matches.filter { $0.status == .inactive || $0.status == .partlyActive }.count
            let missing = missingMatches(id).count
            var parts = [matches.count == 1 ? "Uses 1 font" : "Uses \(matches.count) fonts"]
            if active > 0 { parts.append("\(active) active") }
            if inLibrary > 0 { parts.append("\(inLibrary) to activate") }
            if missing > 0 { parts.append("\(missing) missing") }
            return parts.joined(separator: " · ")
        default:
            return ""
        }
    }

    private func missingMatches(_ id: UUID) -> [DocumentFontMatch] {
        (model.documentMatches[id] ?? []).filter { $0.status == .missing && !$0.reference.isProvidedByDocument }
    }

    private var detail: String? {
        switch model.sidebar {
        case .folder(let path):
            var text = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            if let root = model.folders.first(where: { $0.path == path }), let unreadable = model.unreadableCounts[root.path], unreadable > 0 {
                text += " · \(unreadable) file\(unreadable == 1 ? "" : "s") macOS can’t read"
            }
            return text
        case .document(let id):
            let missing = missingMatches(id)
            guard !missing.isEmpty else { return model.document(id)?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
            return "Missing: " + missing.map(\.reference.name).joined(separator: ", ")
        default:
            return nil
        }
    }
}

/// Activate ▾ (Activate Temporarily) and Deactivate for a whole sidebar item.
struct CollectionActivationButtons: View {
    var model: AppModel
    let item: SidebarItem

    var body: some View {
        // Only what Specimen may change (macOS's own fonts stay as they are).
        let faces = model.faces(in: item).filter { model.lockReason(for: $0) == nil }
        let off = faces.filter { !$0.isEnabled }
        let on = faces.filter(\.isEnabled)
        let inPlace = off.contains(where: model.isInPlace)
        Group {
            if inPlace {
                Menu(off.count == faces.count ? "Activate All" : "Activate \(off.count.formatted())") {
                    Button("Activate Temporarily") { model.request(true, faces: off, temporary: true) }
                        .help("Until you quit Specimen")
                } primaryAction: {
                    model.request(true, faces: off)
                }
                .fixedSize()
                .help("Turn these fonts on where they are, without copying them. Temporarily: until you quit Specimen.")
            } else {
                Button(off.isEmpty || off.count == faces.count ? "Activate All" : "Activate \(off.count.formatted())") { model.request(true, faces: off) }
                    .disabled(off.isEmpty)
            }
            Button("Deactivate All") { model.request(false, faces: on) }
                .disabled(on.isEmpty)
        }
        .disabled(model.isChangingFonts)
    }
}

/// The same actions as menu items (sidebar context menus).
struct CollectionActivationItems: View {
    var model: AppModel
    let item: SidebarItem

    var body: some View {
        Button("Activate All") { model.request(true, faces: model.faces(in: item).filter { !$0.isEnabled || $0.isTemporary }) }
        Button("Activate All Temporarily") { model.request(true, faces: model.faces(in: item).filter { !$0.isEnabled }, temporary: true) }
        Button("Deactivate All") { model.request(false, faces: model.faces(in: item).filter(\.isEnabled)) }
    }
}

/// Every font a document names: its status, the matching style and where it is, and a way
/// to open it or say why it's missing.
struct DocumentFontsList: View {
    @Bindable var model: AppModel
    let documentID: UUID

    var body: some View {
        let matches = model.documentMatches[documentID] ?? []
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(model.document(documentID)?.name ?? "Document").font(.headline)
            if matches.isEmpty {
                Text("No fonts named.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.s, verticalSpacing: Spacing.s) {
                        ForEach(matches) { match in
                            GridRow {
                                Image(systemName: symbol(match))
                                    .foregroundStyle(match.status == .missing ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                                    .accessibilityLabel(statusText(match))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.reference.name).textSelection(.enabled)
                                    Text(detail(match)).font(.caption).foregroundStyle(.secondary)
                                }
                                if let face = match.faces.first {
                                    Button("Show") { model.openDetail(face: face) }
                                        .controlSize(.small)
                                        .help("Open \(face.familyName)")
                                } else {
                                    Color.clear.frame(width: 1, height: 1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(Spacing.l)
        .frame(width: 400)
    }

    private func symbol(_ match: DocumentFontMatch) -> String {
        switch match.status {
        case .active: match.faces.allSatisfy(\.isTemporary) ? "circle.dashed.inset.filled" : "circle.fill"
        case .partlyActive: "circle.lefthalf.filled"
        case .inactive: "circle"
        case .missing: match.reference.isProvidedByDocument ? "globe" : "questionmark.circle"
        }
    }

    private func statusText(_ match: DocumentFontMatch) -> String {
        switch match.status {
        case .active: "Active"
        case .partlyActive: "Partly active"
        case .inactive: "In your library, inactive"
        case .missing: match.reference.isProvidedByDocument ? "Provided by the document" : "Missing"
        }
    }

    private func detail(_ match: DocumentFontMatch) -> String {
        var parts = [statusText(match)]
        if let face = match.faces.first {
            let styles = match.faces.count == 1 ? face.styleName : "\(match.faces.count) styles"
            parts.append("\(face.familyName) \(styles)")
            if let folder = face.path.map({ URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }) { parts.append(folder) }
        } else if match.reference.isEmbedded {
            parts.append("embedded in the file, so it prints; you need it to edit the original")
        }
        return parts.joined(separator: " · ")
    }
}
