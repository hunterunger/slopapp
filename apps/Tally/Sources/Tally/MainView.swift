import AppKit
import SlopKit
import SwiftUI
import TallyCore

/// The window: an optional sidebar of sheets, the sheet itself, and a slim bar along the
/// bottom with the running total. The title bar takes the theme's background so the window
/// reads as one quiet surface.
struct ContentView: View {
    let model: SheetModel
    @State private var columns: NavigationSplitViewVisibility =
        Pref.defaults.bool(forKey: Pref.showsSidebar) ? .all : .detailOnly
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SheetSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 320)
        } detail: {
            SheetDetail(model: model)
        }
        .navigationTitle(model.currentTitle)
        .modifier(ToolbarSurface(theme: model.theme))
        .preferredColorScheme(model.theme.colorScheme)
        .frame(minWidth: 360, minHeight: 240)
        .onChange(of: columns) { _, value in
            Pref.defaults.set(value != .detailOnly, forKey: Pref.showsSidebar)
        }
        .onAppear {
            model.openSettingsAction = { openSettingsWindow() }
            WindowToggler.openMain = { openWindow(id: WindowID.main) }
            WindowFloat.apply()
        }
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async { SettingsWindow.bringToFront() }
    }
}

/// System theme: the system draws the toolbar (Golden Gate glass, scroll-edge effect). A
/// palette theme paints the toolbar in its own background, or a navy sheet would sit under a
/// grey title bar.
private struct ToolbarSurface: ViewModifier {
    let theme: Theme

    func body(content: Content) -> some View {
        if theme.id == Theme.system.id {
            content
        } else {
            content
                .toolbarBackground(theme.swiftUIBackground, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
        }
    }
}

/// The sheet plus its bottom bar.
struct SheetDetail: View {
    let model: SheetModel
    var compact = false
    var openWindow: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            SheetEditor(model: model)
            BottomBar(model: model, compact: compact, openWindow: openWindow)
        }
        .background(model.theme.swiftUIBackground)
    }
}

/// Left: theme. Middle: the total (click to copy). Right: a new sheet (or, in the menu bar
/// panel, open the window). The side controls line up with the sheet's text and results
/// edges; the total's label ends and its value starts at the centre, so neither slides
/// sideways as the value changes width.
struct BottomBar: View {
    let model: SheetModel
    var compact = false
    var openWindow: (() -> Void)?
    @State private var hovering = false

    /// Matches the sidebar's bottom bar (8 + 16 + 8), so both share a centre line.
    static let height: CGFloat = Spacing.xxl + Spacing.s
    /// Both side slots are this wide, so the centre is the bar's centre.
    static let sideSlot: CGFloat = Spacing.xxl
    /// A button-style menu's built-in inset before its label (measured on macOS 26).
    static let menuInset: CGFloat = Spacing.xs

    var body: some View {
        HStack(spacing: Spacing.s) {
            Menu {
                ThemeMenuItems(model: model)
            } label: {
                // Menus draw their label with AppKit, which ignores the bar's foreground
                // style unless the symbol carries its own colour.
                Image(systemName: "paintpalette")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color(nsColor: model.theme.opaqueComment))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Theme")
            .accessibilityLabel("Theme")
            .frame(width: Self.sideSlot + Self.menuInset, alignment: .leading)

            totalView
                .frame(maxWidth: .infinity)

            Group {
                if compact {
                    Button { openWindow?() } label: { Image(systemName: "macwindow") }
                        .help("Open the Tally window")
                        .accessibilityLabel("Open Tally Window")
                } else {
                    Button { model.newSheet() } label: { Image(systemName: "square.and.pencil") }
                        .help("New Sheet")
                        .accessibilityLabel("New Sheet")
                }
            }
            .frame(width: Self.sideSlot, alignment: .trailing)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color(nsColor: model.theme.comment))
        .font(.callout)
        // The menu draws its symbol `menuInset` in from its frame; the leading side makes up
        // for it so both symbols sit on the text and results edges.
        .padding(.leading, SheetTextView.margin - Self.menuInset)
        .padding(.trailing, SheetTextView.margin)
        .frame(height: Self.height)
        .background(model.theme.swiftUIBackground)
    }

    @ViewBuilder private var totalView: some View {
        let footer = model.footer
        if let total = footer.total {
            HStack(spacing: Spacing.xs) {
                Text(footer.isSelection ? "Selection:" : "Total:")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
                Button { model.copyTotal() } label: {
                    Text(total)
                        .monospacedDigit()
                        .foregroundStyle(Color(nsColor: hovering ? model.theme.result : model.theme.text))
                        .truncationMode(.middle)
                }
                .onHover { hovering = $0 }
                .help("Click to copy")
                .accessibilityLabel("\(footer.isSelection ? "Selection total" : "Total") \(total)")
                .accessibilityHint("Copies the total")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .lineLimit(1)
        } else {
            Text("No answers yet")
                .lineLimit(1)
                .accessibilityLabel("No total yet")
        }
    }
}

struct ThemeMenuItems: View {
    let model: SheetModel

    var body: some View {
        Picker("Theme", selection: Binding(get: { model.theme.id }, set: { model.setTheme($0) })) {
            ForEach(Theme.all) { theme in
                Text(theme.name).tag(theme.id)
            }
        }
        .pickerStyle(.inline)
    }
}

/// Every sheet, newest edit first. Return or a click opens one; Delete removes it.
struct SheetSidebar: View {
    let model: SheetModel

    var body: some View {
        List(selection: Binding(get: { model.currentID }, set: { id in if let id { model.select(id) } })) {
            ForEach(model.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .lineLimit(1)
                    Text(Self.dateText(row.modified))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(row.id)
                .contextMenu {
                    Button("Delete Sheet…") { model.deleteSheet(row.id) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand { model.deleteSheet(model.currentID) }
        .modifier(SidebarFooter { newSheetButton })
    }

    /// The sidebar's row text starts this far in (macOS 26+ sidebar list, measured), and the
    /// plus symbol sits this far inside its button: the symbol lines up with the titles.
    static let rowTextInset: CGFloat = Spacing.l
    static let buttonSymbolInset: CGFloat = 2

    private var newSheetButton: some View {
        HStack {
            Button { model.newSheet() } label: { Label("New Sheet", systemImage: "plus") }
                .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.leading, Self.rowTextInset - Self.buttonSymbolInset)
        .padding(.trailing, Spacing.s)
        .padding(.vertical, Spacing.s)
    }

    static func dateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// The sidebar's bottom button. On macOS 26+ it's a scroll-edge bar, so rows scrolling
/// under it fade out instead of showing through; earlier, a bar material with a hairline.
private struct SidebarFooter<Bar: View>: ViewModifier {
    @ViewBuilder var bar: Bar

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.safeAreaBar(edge: .bottom) { bar }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Hairline()
                    bar
                }
                .background(.bar)
            }
        }
    }
}

/// Window ▸ Float on Top.
@MainActor
enum WindowFloat {
    static var isOn: Bool { Pref.defaults.bool(forKey: Pref.floatsOnTop) }

    static func toggle() {
        Pref.defaults.set(!isOn, forKey: Pref.floatsOnTop)
        apply()
    }

    static func apply() {
        DispatchQueue.main.async {
            WindowToggler.mainWindow?.level = isOn ? .floating : .normal
        }
    }
}
