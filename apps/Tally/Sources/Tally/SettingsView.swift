import SlopKit
import SwiftUI
import TallyCore

/// General, Appearance, Currency, Shortcuts, About.
struct SettingsView: View {
    let model: SheetModel
    let info: AppInfo
    @AppStorage(Pref.settingsTab, store: Pref.defaults) private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(model: model, info: info)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")

            AppearanceSettings(model: model)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag("appearance")

            CurrencySettings(model: model)
                .tabItem { Label("Currency", systemImage: "dollarsign.circle") }
                .tag("currency")

            SettingsForm {
                Section {
                    ShortcutRow("Show or hide Tally",
                                subtitle: "Works from any app. While a shortcut is set, closing the window keeps Tally ready in the background. With the Dock icon hidden, it opens the menu bar panel.",
                                name: .toggleWindow)
                }
            }
            .tabItem { Label("Shortcuts", systemImage: "command") }
            .tag("shortcuts")

            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag("about")
        }
        .frame(width: Metrics.settingsWidth)
    }
}

struct GeneralSettings: View {
    let model: SheetModel
    let info: AppInfo
    @AppStorage(Pref.copyIncludesUnit, store: Pref.defaults) private var copyIncludesUnit = true
    @AppStorage(Pref.showsMenuBarIcon, store: Pref.defaults) private var showsMenuBarIcon = false
    @AppStorage(Pref.showsDockIcon, store: Pref.defaults) private var showsDockIcon = true
    @AppStorage(Pref.suggestsNames, store: Pref.defaults) private var suggestsNames = true
    @AppStorage(Pref.cssEm, store: Pref.defaults) private var em = 16.0
    @AppStorage(Pref.cssPPI, store: Pref.defaults) private var ppi = 96.0

    var body: some View {
        SettingsForm {
            Section {
                LaunchAtLoginToggle()
            }
            Section {
                Toggle(isOn: $showsMenuBarIcon) {
                    Text("Show Tally in the menu bar")
                    Text("Click the icon for the current sheet in a panel. Right-click for a menu.")
                }
                .onChange(of: showsMenuBarIcon) { _, _ in MenuBarController.shared.update() }
                Toggle(isOn: $showsDockIcon) {
                    Text("Show Dock icon")
                    Text(showsMenuBarIcon ? "Without it, Tally lives in the menu bar." : "Can be hidden while Tally is in the menu bar.")
                }
                .disabled(!showsMenuBarIcon)
                .onChange(of: showsDockIcon) { _, _ in MenuBarController.shared.update() }
            }
            Section {
                Toggle(isOn: $copyIncludesUnit) {
                    Text("Copied results include the unit")
                    Text(copyIncludesUnit ? "Copies “1.2 m” and “$25.00”." : "Copies “1.2” and “25.00”, ready to paste into a spreadsheet.")
                }
                Toggle(isOn: $suggestsNames) {
                    Text("Suggest names as you type")
                    Text("Shows the rest of a variable, unit or place in grey. Press Tab to accept, or Esc for a list.")
                }
            }
            Section {
                LabeledContent("1 em") {
                    HStack(spacing: Spacing.xs) {
                        TextField("1 em", value: $em, format: .number.precision(.fractionLength(0...2)))
                            .labelsHidden()
                            .frame(width: Self.numberField)
                            .multilineTextAlignment(.trailing)
                        Text("px")
                            .frame(width: Self.unitSlot, alignment: .leading)
                    }
                }
                LabeledContent("Pixel density") {
                    HStack(spacing: Spacing.xs) {
                        TextField("Pixel density", value: $ppi, format: .number.precision(.fractionLength(0...2)))
                            .labelsHidden()
                            .frame(width: Self.numberField)
                            .multilineTextAlignment(.trailing)
                        Text("ppi")
                            .frame(width: Self.unitSlot, alignment: .leading)
                    }
                }
            } header: {
                Text("Screen units")
            } footer: {
                Text("Used for px, pt and em. A sheet can change them for the lines below with em = 20px or ppi = 326.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: em) { _, _ in model.settingsChanged() }
        .onChange(of: ppi) { _, _ in model.settingsChanged() }
    }
}

extension GeneralSettings {
    static let numberField: CGFloat = 64
    /// "px" and "ppi" take the same slot, so both fields end on one edge.
    static let unitSlot: CGFloat = 24
}

struct AppearanceSettings: View {
    let model: SheetModel
    /// The checkmark greys out with the window, like a selection.
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        SettingsForm {
            Section {
                ForEach(Theme.all) { theme in
                    Button { model.setTheme(theme.id) } label: {
                        HStack(spacing: Spacing.m) {
                            ThemeSwatch(theme: theme)
                            Text(theme.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(activeState != .inactive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .opacity(model.theme.id == theme.id ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.name)
                    .accessibilityAddTraits(model.theme.id == theme.id ? .isSelected : [])
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("System follows your Mac’s appearance and accent colour. The others keep their own colours in light and dark mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A sample line in the theme's colours and the editor's own type.
struct ThemeSwatch: View {
    let theme: Theme
    static let size = CGSize(width: 170, height: 24)

    var body: some View {
        HStack(spacing: 0) {
            Text("price").foregroundStyle(Color(nsColor: theme.variable))
            Text(" × ").foregroundStyle(Color(nsColor: theme.text))
            Text("3").foregroundStyle(Color(nsColor: theme.number))
            Text(" in ").foregroundStyle(Color(nsColor: theme.keyword))
            Text("€").foregroundStyle(Color(nsColor: theme.unit))
            Spacer(minLength: Spacing.s)
            Text("€27.65").fontWeight(.medium).foregroundStyle(Color(nsColor: theme.result))
        }
        .font(.callout.monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, Spacing.s)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(RoundedRectangle(cornerRadius: Radius.s).fill(Color(nsColor: theme.background)))
        .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s))
        .modifier(SchemeOverride(scheme: theme.colorScheme))
        .accessibilityHidden(true)
    }
}

struct CurrencySettings: View {
    let model: SheetModel
    @AppStorage(Pref.downloadRates, store: Pref.defaults) private var downloadRates = false
    @AppStorage(Pref.dollarCode, store: Pref.defaults) private var dollarCode = "USD"

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: $downloadRates) {
                    Text("Download exchange rates")
                    Text("Tally gets the European Central Bank’s daily reference rates, at most once a day. Nothing else is sent.")
                }
                .onChange(of: downloadRates) { _, on in model.downloadRatesChanged(on) }
            }
            Section {
                LabeledContent("Rates") {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if case .failed(let message) = model.rates.status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.textOrange)
                }
                HStack {
                    Spacer()
                    Button("Delete Rates") { model.deleteRates() }
                        .disabled(model.rates.stored == .none)
                    Button("Update Now") { model.updateRatesNow() }
                        .disabled(model.rates.status == .updating)
                }
            }
            Section {
                Picker(selection: $dollarCode) {
                    ForEach(Currencies.dollarCodes, id: \.self) { code in
                        Text(Self.name(of: code)).tag(code)
                    }
                } label: {
                    Text("$ means")
                    Text("Offline? Write a rate on its own line, like 1 USD = 1.37 CAD. It works for the lines below it.")
                }
                .onChange(of: dollarCode) { _, _ in model.settingsChanged() }
            }
        }
        .id(model.ratesRevision)
    }

    private var statusText: String {
        if model.rates.status == .updating { return "Updating…" }
        switch model.rates.stored {
        case .none: return "None downloaded"
        case .unreadable: return "The saved rates can’t be read"
        case .table(let t):
            return "From \(t.displayDate()), \(t.rates.count + 1) currencies"
        }
    }

    static func name(of code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(name) (\(code))"
    }
}

/// Applies a colour scheme only when the theme has one (System follows the window).
private struct SchemeOverride: ViewModifier {
    let scheme: ColorScheme?

    func body(content: Content) -> some View {
        if let scheme {
            content.environment(\.colorScheme, scheme)
        } else {
            content
        }
    }
}
