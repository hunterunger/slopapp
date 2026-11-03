import AppKit
import SlopKit
import SwiftUI
import ZonesCore

/// The menu bar panel: a time bar, the list of clocks, and a footer.
struct PanelView: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            if panel.mode == .search {
                SearchView(model: model, panel: panel, controller: controller)
            } else {
                TimeBar(model: model)
                Divider()
                ClockList(model: model, panel: panel, controller: controller)
                PanelMessages(model: model, panel: panel, controller: controller)
                Divider()
                PanelFooter(model: model, panel: panel, controller: controller)
            }
        }
        .frame(width: Metrics.menuBarWindowWidth)
    }
}

// MARK: - Time bar

/// "Now · Tue, Nov 3" with ‹ › to move an hour; shows how far from now you are once moved.
struct TimeBar: View {
    @Bindable var model: ZonesModel

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button { model.step(.hour, by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .help("1 hour earlier (⇧←). Drag sideways on the list or press ← → to move 15 minutes.")
            .accessibilityLabel("1 Hour Earlier")

            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(model.deltaText)
                    .font(.headline)
                    .monospacedDigit()
                Text(model.dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // An incrementor for VoiceOver: up/down moves 15 minutes, and the value reads
            // "3 hours 15 minutes later, Wednesday, November 4, 3:00 PM".
            .accessibilityRepresentation {
                Stepper("Shown time", onIncrement: { model.step(.quarterHour, by: 1) },
                        onDecrement: { model.step(.quarterHour, by: -1) })
                    .accessibilityValue(model.timeAccessibilityValue)
            }
            Spacer(minLength: 0)

            if model.isScrubbed {
                Button("Now") { model.resetToNow() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Back to now (Esc)")
                    .accessibilityLabel("Back to Now")
            }
            Button { model.step(.hour, by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .help("1 hour later (⇧→). Drag sideways on the list or press ← → to move 15 minutes.")
            .accessibilityLabel("1 Hour Later")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }
}

// MARK: - List

struct ClockList: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController
    static let maxVisibleRows = 9

    var body: some View {
        let rows = model.rows
        Group {
            if rows.isEmpty {
                EmptyPlaces(controller: controller, panel: panel)
            } else if rows.count > Self.maxVisibleRows {
                ScrollViewReader { proxy in
                    ScrollView {
                        content(rows)
                    }
                    .frame(height: 440)
                    .onChange(of: model.selection) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            } else {
                content(rows)
            }
        }
    }

    private func content(_ rows: [ClockRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                ClockRowView(row: row, model: model, panel: panel, controller: controller)
                    .id(row.id)
            }
        }
        .padding(.vertical, Spacing.xs)
        .background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                    panel.listFrame = frame
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let x = panel.markerX {
                Rectangle()
                    .fill(.tint)
                    .frame(width: 2)
                    .offset(x: x - panel.listFrame.minX - 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct EmptyPlaces: View {
    let controller: AppController
    let panel: PanelState

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "globe")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No places to show")
                .font(.headline)
            Text("Add one with Add Place… below, or show local time again in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xxl)
    }
}

/// Lines under the list: the first-run hint, a removed place with Undo, a note about a
/// typed time, or a typing error. At most a couple at once.
struct PanelMessages: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let error = panel.editError {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
            if let undo = model.pendingUndo {
                HStack {
                    Text(undo.message)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Undo") { model.undo() }
                        .buttonStyle(.borderless)
                        .help("Undo (⌘Z)")
                }
            }
            if model.showsAddHint && !model.isEmpty {
                Label("Add the cities you work with (Add Place… below, or ⌘N) to see their time at a glance.",
                      systemImage: "plus.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .symbolRenderingMode(.hierarchical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, hasContent ? Spacing.m : 0)
        .padding(.bottom, hasContent ? Spacing.s : 0)
    }

    private var hasContent: Bool {
        panel.editError != nil || model.notice != nil || model.pendingUndo != nil || (model.showsAddHint && !model.isEmpty)
    }
}

// MARK: - Footer

struct PanelFooter: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController

    var body: some View {
        HStack(spacing: Spacing.m) {
            Button { panel.beginSearch() } label: {
                Label("Add Place…", systemImage: "plus")
            }
            .help("Add a city or time zone (⌘N)")
            Button { controller.copyTimes() } label: {
                Label("Copy Times", systemImage: "doc.on.doc")
            }
            .help("Copy the shown time in every place (⌘C)")
            .disabled(model.isEmpty)
            Spacer()
            Button { controller.showMoreMenu() } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                        panel.moreButtonFrame = frame
                    }
                }
            }
            .help("More")
            .accessibilityLabel("More")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }
}
