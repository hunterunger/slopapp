import AppKit
import PDFKit
import PaperCore
import SlopKit
import SwiftUI

/// Pages > Headers & Footers…: page numbers, Bates numbers or any text in six slots, stamped
/// into the pages. One undo step.
@MainActor
enum HeadersFootersSheet {
    static let key = "headerFooter"

    static var saved: HeaderFooter {
        Prefs.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(HeaderFooter.self, from: $0) } ?? .pageNumbers
    }

    static func present(controller: PaperWindowController, window: NSWindow) {
        let selected = controller.model.selectedIndexes
        let count = controller.model.pdf.pageCount
        Sheet.present(on: window) { dismiss in
            HeadersFootersView(stamp: saved, pageCount: count, selectedCount: selected.count) { result in
                dismiss()
                guard let (stamp, onlySelected) = result else { return }
                Prefs.defaults.set(try? JSONEncoder().encode(stamp), forKey: key)
                apply(stamp, pages: onlySelected ? selected : IndexSet(integersIn: 0..<count), controller: controller)
            }
        }
    }

    static func apply(_ stamp: HeaderFooter, pages: IndexSet, controller: PaperWindowController) {
        let pdf = controller.model.pdf
        let name = controller.paperDocument.map(Exporting.baseName) ?? "Document"
        let date = Date()
        var replacements: [(index: Int, page: PDFPage)] = []
        for (sequence, index) in pages.enumerated() {
            guard let page = pdf.page(at: index),
                  let stamped = stamp.stamped(page, .init(page: index + 1, pageCount: pdf.pageCount, sequence: sequence, date: date, name: name))
            else { continue }
            replacements.append((index, stamped))
        }
        controller.editor.replace(replacements, name: "Add Headers & Footers")
        HUD.show(replacements.count == 1 ? "Added to 1 page" : "Added to \(replacements.count) pages", systemImage: "doc.plaintext")
    }
}

struct HeadersFootersView: View {
    @State var stamp: HeaderFooter
    let pageCount: Int
    let selectedCount: Int
    let finish: ((HeaderFooter, Bool)?) -> Void
    @State private var onlySelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text("Headers & Footers").font(.headline)
                Spacer()
                Menu("Presets") {
                    Button("Page Numbers") { stamp = .pageNumbers }
                    Button("Bates Numbers") {
                        var value = HeaderFooter()
                        value.bottomRight = "{bates}"
                        value.batesPrefix = stamp.batesPrefix
                        stamp = value
                    }
                    Button("Clear All") { stamp = HeaderFooter() }
                }
                .fixedSize()
            }
            Grid(alignment: .leading, horizontalSpacing: Spacing.s, verticalSpacing: Spacing.s) {
                GridRow {
                    Text("")
                    Text("Left").font(.caption).foregroundStyle(.secondary)
                    Text("Center").font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.center)
                    Text("Right").font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("Header")
                    slot($stamp.topLeft, "Header left", .leading)
                    slot($stamp.topCenter, "Header center", .center)
                    slot($stamp.topRight, "Header right", .trailing)
                }
                GridRow {
                    Text("Footer")
                    slot($stamp.bottomLeft, "Footer left", .leading)
                    slot($stamp.bottomCenter, "Footer center", .center)
                    slot($stamp.bottomRight, "Footer right", .trailing)
                }
            }
            Text("Use {page}, {pages}, {date}, {name} and {bates} in any box.")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                Picker("Text size", selection: $stamp.fontSize) {
                    ForEach([8, 9, 10, 11, 12, 14] as [CGFloat], id: \.self) { Text("\(Int($0)) pt").tag($0) }
                }
                Picker("Distance from edge", selection: $stamp.margin) {
                    Text("Narrow").tag(CGFloat(18))
                    Text("Normal").tag(CGFloat(28))
                    Text("Wide").tag(CGFloat(42))
                }
                if usesBates {
                    TextField("Bates prefix", text: $stamp.batesPrefix)
                    Stepper("Bates starts at \(stamp.batesStart)", value: $stamp.batesStart, in: 0...9_999_999)
                    Stepper("\(stamp.batesDigits) digits", value: $stamp.batesDigits, in: 1...12)
                }
                if selectedCount < pageCount {
                    Picker("Pages", selection: $onlySelected) {
                        Text("All \(pageCount) pages").tag(false)
                        Text(selectedCount == 1 ? "Selected page" : "Selected \(selectedCount) pages").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                }
            }
            Text("The text becomes part of the pages. Undo removes it.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
                Button("Add") { finish((stamp, onlySelected)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(stamp.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 560)
    }

    private var usesBates: Bool {
        [stamp.topLeft, stamp.topCenter, stamp.topRight, stamp.bottomLeft, stamp.bottomCenter, stamp.bottomRight]
            .contains { $0.contains("{bates}") }
    }

    /// Each box's text sits where it will on the page: left, centred or right.
    private func slot(_ text: Binding<String>, _ label: String, _ alignment: TextAlignment) -> some View {
        TextField(label, text: text, prompt: Text(""))
            .multilineTextAlignment(alignment)
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .accessibilityLabel(label)
    }
}
