import SlopKit
import SwiftUI
import ZonesCore

/// Add a place: type a city, country, time zone, abbreviation or UTC offset.
/// ↑↓ move, Return adds, Esc goes back.
struct SearchView: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search", text: $panel.query, prompt: Text("City, country or time zone"))
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .accessibilityLabel("Search places")
                Button("Cancel") { panel.cancel() }
                    .buttonStyle(.borderless)
                    .help("Back to the list (Esc)")
            }
            .padding(.horizontal, PanelMetrics.margin)
            .padding(.vertical, Spacing.m)
            Hairline()
            resultsView
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    @ViewBuilder private var resultsView: some View {
        if let error = panel.loadError {
            message(error, symbol: "exclamationmark.triangle")
        } else if panel.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(Spacing.xl)
        } else if panel.results.isEmpty {
            VStack(spacing: Spacing.xs) {
                Text("No places match “\(panel.query)”")
                    .font(.headline)
                Text("Try a city, a country, or a time zone like PST, Europe/Paris or UTC+5:30.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.xl)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if panel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, PanelMetrics.margin)
                        .padding(.top, Spacing.s)
                        .accessibilityAddTraits(.isHeader)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(zip(panel.results.indices, panel.results)), id: \.1.id) { index, result in
                                ResultRow(result: result, isSelected: index == panel.resultSelection,
                                          isAdded: model.contains(result.place), instant: model.now,
                                          formatter: model.formatter)
                                    .onTapGesture { controller.addPlace(result) }
                                    .onHover { inside in
                                        // Ignore the pointer already resting there when the list changes.
                                        if inside, Date().timeIntervalSince(panel.resultsChangedAt) > 0.3 {
                                            panel.resultSelection = index
                                        }
                                    }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { controller.addPlace(result) }
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                    .frame(height: min(CGFloat(panel.results.count) * ResultRow.height + 2 * Spacing.xs,
                                       ResultRow.height * 9 + Spacing.xs))
                    .onChange(of: panel.resultSelection) { _, index in
                        if panel.results.indices.contains(index) { proxy.scrollTo(panel.results[index].id) }
                    }
                }
            }
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(Spacing.xl)
    }
}

struct ResultRow: View {
    static let height: CGFloat = 44
    @Environment(\.controlActiveState) private var activeState
    let result: SearchResult
    let isSelected: Bool
    let isAdded: Bool
    let instant: Date
    let formatter: TimeFormatter

    var body: some View {
        let time = formatter.time(instant, in: result.timeZone)
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.xs)
            if isAdded {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .help("Already in your list: choosing it shows the existing row")
            }
            Text(time)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, PanelMetrics.margin)
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .background {
            // Same inset and corners as a selected row in the list.
            RoundedRectangle(cornerRadius: PanelMetrics.shapeRadius, style: .continuous)
                .fill(isSelected ? Color.selectionTint(activeState, opacity: 0.18) : Color.clear)
                .padding(.horizontal, PanelMetrics.shapeInset)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.title), \(result.subtitle), \(time)\(isAdded ? ", already added" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
