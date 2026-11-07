import AppKit
import SwiftUI

// Golden Gate greys selections and accent-coloured marks in windows you aren't using, like
// Finder and Mail (design system §4, "Active vs inactive"). These pick the right colour for
// the window's state, from either environment value:
//
//     @Environment(\.controlActiveState) private var activeState
//     .background(RoundedRectangle(cornerRadius: Radius.m).fill(isSelected ? Color.selectionTint(activeState) : .clear))
//
//     @Environment(\.appearsActive) private var appearsActive
//     Image(systemName: "star.fill").foregroundStyle(Color.windowAccent(active: appearsActive))
//
// (From Specimen's WindowAccent.swift.)

public extension ControlActiveState {
    /// The window is key, or main under its own sheet.
    var isActiveWindow: Bool { self != .inactive }
}

public extension Color {
    /// The accent in an active window; secondary grey in a background one.
    static func windowAccent(_ state: ControlActiveState) -> Color {
        windowAccent(active: state.isActiveWindow)
    }

    /// The accent in an active window; secondary grey in a background one.
    static func windowAccent(active: Bool) -> Color {
        active ? .accentColor : Color(nsColor: .secondaryLabelColor)
    }

    /// A selected item's tint: accent in an active window, the system's unemphasized
    /// selection grey in a background one.
    static func selectionTint(_ state: ControlActiveState, opacity: Double = 0.12) -> Color {
        selectionTint(active: state.isActiveWindow, opacity: opacity)
    }

    /// A selected item's tint: accent in an active window, the system's unemphasized
    /// selection grey in a background one.
    static func selectionTint(active: Bool, opacity: Double = 0.12) -> Color {
        active ? Color.accentColor.opacity(opacity) : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    /// A solid selection fill (glyph cells, chips): accent, or the unemphasized grey.
    static func selectionFill(_ state: ControlActiveState) -> Color {
        selectionFill(active: state.isActiveWindow)
    }

    /// A solid selection fill (glyph cells, chips): accent, or the unemphasized grey.
    static func selectionFill(active: Bool) -> Color {
        active ? .accentColor : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    /// The selection ring: accent, or system grey.
    static func selectionRing(_ state: ControlActiveState) -> Color {
        selectionRing(active: state.isActiveWindow)
    }

    /// The selection ring: accent, or system grey.
    static func selectionRing(active: Bool) -> Color {
        active ? .accentColor : Color(nsColor: .systemGray)
    }
}
