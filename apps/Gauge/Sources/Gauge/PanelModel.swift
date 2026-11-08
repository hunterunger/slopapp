import AppKit
import GaugeCore
import Observation

/// A part of the panel: one row in the overview, one detail below it.
enum PanelSection: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, disk, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .battery: "battery.100percent"
        }
    }

    /// Sections with a process list to move through with ↑ and ↓.
    var processSort: ProcessSort? {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        default: nil
        }
    }
}

/// The open panel's state. Fed by the sampler once a tick while the panel is open.
@MainActor
@Observable
final class PanelModel {
    var update: PanelUpdate?
    var selection: PanelSection {
        didSet {
            if selection != oldValue { selectedRow = nil }
            defaults.set(selection.rawValue, forKey: Self.sectionKey)
        }
    }
    /// The keyboard-selected row in the detail's list.
    var selectedRow: Int?
    var hasBattery = true
    var thermal: ThermalLevel = .nominal

    @ObservationIgnored private let defaults: UserDefaults
    private static let sectionKey = "panelSection"

    /// `defaults`: where the last section is remembered (the app's settings, or the test suite).
    init(defaults: UserDefaults) {
        self.defaults = defaults
        selection = defaults.string(forKey: Self.sectionKey).flatMap(PanelSection.init(rawValue:)) ?? .cpu
    }

    func apply(_ update: PanelUpdate) {
        self.update = update
        if !sections.contains(selection) { selection = .cpu }
        if let row = selectedRow, row >= rows.count { selectedRow = rows.isEmpty ? nil : rows.count - 1 }
    }

    var hasGPU: Bool { update?.data.hasGPU ?? true }

    var sections: [PanelSection] {
        PanelSection.allCases.filter { section in
            switch section {
            case .gpu: hasGPU
            case .battery: hasBattery
            default: true
            }
        }
    }

    /// The process rows of the selected section.
    var rows: [ProcessGroup] {
        switch selection.processSort {
        case .cpu: update?.data.topCPU ?? []
        case .memory: update?.data.topMemory ?? []
        case nil: []
        }
    }

    func moveSelection(by offset: Int) {
        let rows = self.rows
        guard !rows.isEmpty else { return }
        if let row = selectedRow {
            selectedRow = min(rows.count - 1, max(0, row + offset))
        } else {
            selectedRow = offset > 0 ? 0 : rows.count - 1
        }
    }

    func moveSection(by offset: Int) {
        let sections = self.sections
        guard let index = sections.firstIndex(of: selection) else { return }
        selection = sections[(index + offset + sections.count) % sections.count]
    }

    func selectSection(number: Int) {
        let sections = self.sections
        guard sections.indices.contains(number - 1) else { return }
        selection = sections[number - 1]
    }

    func panelClosed() {
        selectedRow = nil
    }
}
