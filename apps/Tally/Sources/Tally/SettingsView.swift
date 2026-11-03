import SlopKit
import SwiftUI
import TallyCore

/// General, Currency, Shortcuts, About.
struct SettingsView: View {
    let model: SheetModel
    let info: AppInfo
    @AppStorage(Pref.settingsTab) private var tab = "general"
    @AppStorage(Pref.copyIncludesUnit) private var copyIncludesUnit = true

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsTab(isMenuBarApp: false, appName: info.name) {
                Toggle("Copied results include the unit", isOn: $copyIncludesUnit)
                Text(copyIncludesUnit ? "Copies “1.2 m” and “$25.00”." : "Copies “1.2” and “25.00”, ready to paste into a spreadsheet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag("general")

            CurrencySettings(model: model)
                .tabItem { Label("Currency", systemImage: "dollarsign.circle") }
                .tag("currency")

            SettingsForm {
                Section {
                    ShortcutRow("Show or hide Tally", name: .toggleWindow)
                    Text("Works from any app. While a shortcut is set, closing the window keeps Tally ready in the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

struct CurrencySettings: View {
    let model: SheetModel
    @AppStorage(Pref.downloadRates) private var downloadRates = false
    @AppStorage(Pref.dollarCode) private var dollarCode = "USD"

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Download exchange rates", isOn: $downloadRates)
                    .onChange(of: downloadRates) { _, on in model.downloadRatesChanged(on) }
                Text("Tally gets the European Central Bank’s daily reference rates, at most once a day. Nothing else is sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.orange)
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
                Picker("$ means", selection: $dollarCode) {
                    ForEach(Currencies.dollarCodes, id: \.self) { code in
                        Text(Self.name(of: code)).tag(code)
                    }
                }
                .onChange(of: dollarCode) { _, _ in model.settingsChanged() }
                Text("Offline? Write a rate on its own line, like 1 USD = 1.37 CAD. It works for the lines below it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
