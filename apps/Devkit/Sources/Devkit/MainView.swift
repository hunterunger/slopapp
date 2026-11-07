import DevkitCore
import SlopKit
import SwiftUI

// Archetype: library window (docs/design-system.md, 2c). A sidebar of tools; each tool is
// input → options → live output.

struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } detail: {
            ToolDetail(model: model)
                .id(model.selection)
                .navigationTitle(model.selection.title)
                .navigationSubtitle(model.selection.subtitle)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.pasteAndDetect()
                } label: {
                    Label("Paste and Detect", systemImage: "doc.on.clipboard")
                }
                .help("Paste the clipboard into the tool that fits it (⇧⌘V)")
                Button {
                    model.useOutputAsInput()
                } label: {
                    Label("Use Output as Input", systemImage: "arrow.turn.down.left")
                }
                .help("Send the output on to the next tool (⌘↩)")
                .disabled(!model.canCopyOutput)
                Button {
                    model.copyOutput()
                } label: {
                    Label("Copy Output", systemImage: "doc.on.doc")
                }
                .help("Copy the output (⇧⌘C)")
                .disabled(!model.canCopyOutput)
                Toggle(isOn: $model.keepOnTop) {
                    Label("Keep on Top", systemImage: model.keepOnTop ? "pin.fill" : "pin")
                }
                .help(model.keepOnTop ? "Stop floating above other windows" : "Float above other windows")
            }
        }
        .background(WindowAccessor { _ in model.applyWindowLevel() })
        .frame(minWidth: 760, minHeight: 460)
    }
}

struct Sidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: Binding<Tool?>(get: { model.selection }, set: { if let tool = $0 { model.selection = tool } })) {
            let tools = model.visibleTools
            if tools.isEmpty {
                Text("No tools match “\(model.sidebarFilter)”")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            ForEach(tools) { tool in
                Label {
                    Text(tool.title)
                } icon: {
                    // Fixed width so wide symbols don't push their titles out of line.
                    Image(systemName: tool.symbol)
                        .frame(width: 22)
                }
                .tag(tool)
                .help(tool.subtitle)
                .contextMenu {
                    Button("Hide “\(tool.title)”") { model.hide(tool) }
                        .disabled(model.shownTools.count <= 1)
                    Button("Show Hidden Tools") { model.hiddenTools = [] }
                        .disabled(model.hiddenTools.isEmpty)
                }
            }
        }
        .searchable(text: $model.sidebarFilter, placement: .sidebar, prompt: "Filter Tools")
        .onSubmit(of: .search) {
            if let first = model.visibleTools.first { model.selection = first }
        }
        .onChange(of: model.sidebarFilter) {
            // Typing a filter selects the first match, so Return isn't even needed.
            if let first = model.visibleTools.first, !model.visibleTools.contains(model.selection) {
                model.selection = first
            }
        }
    }
}

struct ToolDetail: View {
    let model: AppModel

    var body: some View {
        switch model.selection {
        case .json: JSONToolView(model: model.json, app: model)
        case .jwt: JWTToolView(model: model.jwt, app: model)
        case .base64: Base64ToolView(model: model.base64, app: model)
        case .url: URLToolView(model: model.url, app: model)
        case .timestamp: TimestampToolView(model: model.timestamp, app: model)
        case .uuid: UUIDToolView(model: model.uuid, app: model)
        case .hash: HashToolView(model: model.hash, app: model)
        case .regex: RegexToolView(model: model.regex, app: model)
        case .diff: DiffToolView(model: model.diff, app: model)
        case .color: ColorToolView(model: model.color, app: model)
        case .numberBase: NumberBaseToolView(model: model.numberBase, app: model)
        case .textCase: CaseToolView(model: model.textCase, app: model)
        case .urlParser: URLParserToolView(model: model.urlParser, app: model)
        case .stringInspector: StringInspectorToolView(model: model.stringInspector, app: model)
        case .lorem: LoremToolView(model: model.lorem, app: model)
        case .randomString: RandomStringToolView(model: model.randomString, app: model)
        case .qrCode: QRToolView(model: model.qrCode, app: model)
        case .certificate: CertificateToolView(model: model.certificate, app: model)
        case .cron: CronToolView(model: model.cron, app: model)
        case .yamlToJSON, .jsonToYAML, .csvToJSON, .jsonToCSV, .htmlEntities, .backslash, .htmlFormat, .cssFormat,
             .xmlFormat, .sqlFormat, .svgToCSS, .hexText, .lineSort, .gzip:
            TransformToolView(model: model.transform(model.selection), app: model)
        }
    }
}

/// Calls back when the view lands in a window (to apply the window level on launch).
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
