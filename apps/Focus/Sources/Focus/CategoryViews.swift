import AppKit
import FocusCore
import SlopKit
import SwiftUI

extension CategoryColor {
    /// System colours, so categories adapt to light, dark and increased contrast.
    var color: Color {
        switch self {
        case .accent: .accentColor
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

extension CategoryColor {
    /// The AppKit colour, for images drawn into menus.
    var nsColor: NSColor {
        switch self {
        case .accent: .controlAccentColor
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .cyan: .systemCyan
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .brown: .systemBrown
        case .gray: .systemGray
        }
    }
}

/// A filled circle as a non-template image: menus and menu-button labels only draw images and
/// text, and tint template images.
@MainActor
enum DotImage {
    static func make(_ color: NSColor, diameter: CGFloat = 9) -> NSImage {
        let size = NSSize(width: diameter + 2, height: diameter + 2)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

extension Optional where Wrapped == FocusCore.Category {
    /// The colour a session in this category is drawn in. No category: the accent colour.
    var tint: Color { self?.color.color ?? .accentColor }

    /// The colour sessions in this category are drawn in wherever categories are compared
    /// (stats chart, category table, session rows, the timeline): gray for none, the same as
    /// the chart's "No Category", so it never looks like a blue category.
    var dataTint: Color { self?.color.color ?? .gray }
}

/// Colour of a phase's dial and blocks.
func phaseTint(_ phase: Phase?, category: FocusCore.Category?) -> Color {
    guard let phase, phase.isBreak else { return category.tint }
    return .green
}

/// "● Work ⌄": picks the category for this and the next sessions. Lists every category, then
/// "No Category" and "Edit Categories…".
struct CategoryPicker: View {
    let controller: FocusController
    var compact = false

    var body: some View {
        let current = controller.category
        Menu {
            ForEach(controller.settings.categories) { category in
                Button {
                    controller.setCategory(category.id)
                } label: {
                    Label { Text(category.name) } icon: { ColorDot(color: category.color) }
                }
            }
            Divider()
            Button {
                controller.setCategory(nil)
            } label: {
                Label { Text("No Category") } icon: { Image(nsImage: DotImage.make(.systemGray)) }
            }
            Divider()
            Button("Edit Categories…") { FocusSettingsOpener.open(.categories) }
        } label: {
            Label {
                Text(current?.name ?? "No Category")
                    .lineLimit(1)
            } icon: {
                Image(nsImage: DotImage.make(current?.color.nsColor ?? .systemGray))
            }
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(compact ? .small : .regular)
        .fixedSize()
        .accessibilityLabel("Category: \(current?.name ?? "none")")
        .help("Category for this session")
    }
}

/// A coloured dot image for menus (menus only show images, not shapes).
struct ColorDot: View {
    let color: CategoryColor

    var body: some View {
        Image(nsImage: DotImage.make(color.nsColor))
    }
}

/// One dot per session in the daily goal, filled as sessions are done.
struct GoalDots: View {
    let done: Int
    let goal: Int
    var tint: Color = .accentColor
    var size: CGFloat = 7

    var body: some View {
        if goal > 0 {
            HStack(spacing: size * 0.6) {
                ForEach(0..<max(goal, min(done, goal + 8)), id: \.self) { index in
                    Circle()
                        .fill(index < done ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                        .frame(width: size, height: size)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily goal: \(done) of \(goal) sessions")
            .help("\(done) of \(goal) sessions today")
        }
    }
}
