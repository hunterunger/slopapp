import AppKit
import DropperCore
import Observation
import SlopKit
import SwiftUI

/// The two colors being compared, their text fields, and any newer picks on offer.
/// The pair is saved, so it survives closing the window and relaunching.
@MainActor
@Observable
final class ContrastState {
    enum Slot: String { case text, background }

    private(set) var pair: ContrastPair
    var textField = ""
    var backgroundField = ""
    private(set) var textInvalid = false
    private(set) var backgroundInvalid = false
    /// Newer picks the person can switch to with one click.
    private(set) var offer: (text: ColorValue, background: ColorValue)?

    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "contrastPair"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        pair = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(ContrastPair.self, from: $0) }
            ?? .blackOnWhite
        hasStoredPair = defaults.data(forKey: Self.storageKey) != nil
    }

    @ObservationIgnored private var hasStoredPair: Bool

    var text: ColorValue { pair.text }
    var background: ColorValue { pair.background }
    var isValid: Bool { !textInvalid && !backgroundInvalid }
    var report: ContrastReport { ContrastReport(text: pair.text, background: pair.background) }

    /// Called when the window opens: first time ever, start from the last picks; after that
    /// keep the pair and offer newer picks.
    func prepare(history: ColorHistory, options: FormatOptions) {
        if !hasStoredPair {
            pair = .initial(from: history)
            hasStoredPair = true
            save()
        }
        refreshOffer(history: history)
        refreshFields(options: options)
    }

    func refreshOffer(history: ColorHistory) {
        offer = pair.offer(from: history).map { (text: $0.text, background: $0.background) }
    }

    func useOffer(history: ColorHistory, options: FormatOptions) {
        pair.useOffer(from: history)
        offer = nil
        save()
        refreshFields(options: options)
    }

    /// A color picked from the screen with the checker's own eyedropper buttons.
    func set(_ color: ColorValue, for slot: Slot, history: ColorHistory, options: FormatOptions) {
        switch slot {
        case .text: pair.text = color
        case .background: pair.background = color
        }
        pair.markOffered(history)
        offer = nil
        save()
        refreshFields(options: options)
    }

    /// Applies typed or pasted text (hex, rgb(), hsl(), color(display-p3 …)). Invalid text
    /// keeps the old color and marks the field.
    func apply(_ string: String, to slot: Slot, options: FormatOptions) {
        let color = ColorParser.color(string, in: options.space)
        let invalid = color == nil
        switch slot {
        case .text:
            textInvalid = invalid
            if let color { pair.text = color }
        case .background:
            backgroundInvalid = invalid
            if let color { pair.background = color }
        }
        if color != nil { save() }
    }

    /// A color changed with the sliders or Fix: replaces the slot and rewrites its field.
    func adjust(_ color: ColorValue, for slot: Slot, options: FormatOptions) {
        switch slot {
        case .text:
            pair.text = color
            textField = ColorFormatter.string(color, as: .hex, options: options)
            textInvalid = false
        case .background:
            pair.background = color
            backgroundField = ColorFormatter.string(color, as: .hex, options: options)
            backgroundInvalid = false
        }
        save()
    }

    func color(for slot: Slot) -> ColorValue {
        slot == .text ? pair.text : pair.background
    }

    func swap() {
        (pair.text, pair.background) = (pair.background, pair.text)
        (textField, backgroundField) = (backgroundField, textField)
        (textInvalid, backgroundInvalid) = (backgroundInvalid, textInvalid)
        save()
    }

    /// Rewrites both fields as hex in the current options (after a pick, on submit, or when
    /// the color space changes).
    func refreshFields(options: FormatOptions) {
        textField = ColorFormatter.string(pair.text, as: .hex, options: options)
        backgroundField = ColorFormatter.string(pair.background, as: .hex, options: options)
        textInvalid = false
        backgroundInvalid = false
    }

    /// After Return in a field: show a valid value as hex (pasted rgb() becomes #RRGGBB).
    func normalizeField(_ slot: Slot, options: FormatOptions) {
        switch slot {
        case .text where !textInvalid:
            textField = ColorFormatter.string(pair.text, as: .hex, options: options)
        case .background where !backgroundInvalid:
            backgroundField = ColorFormatter.string(pair.background, as: .hex, options: options)
        default:
            break
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pair) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

