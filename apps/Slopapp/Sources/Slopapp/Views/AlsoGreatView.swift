import AppKit
import SlopappCore
import SlopKit
import SwiftUI

/// Free, open-source apps we recommend instead of rebuilding. Links only: Slopapp doesn't
/// install or update these.
struct AlsoGreatView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                PageHeader(title: "Also Great", subtitle: "Free, open-source Mac apps we use and don't need to rebuild. Get them from their websites.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Spacing.xxl, alignment: .top)], alignment: .leading, spacing: Spacing.l) {
                    ForEach(RecommendedApp.all) { app in
                        RecommendedRow(app: app)
                    }
                }
            }
            .padding(Spacing.xxl)
        }
        .navigationTitle("Also Great")
    }
}

struct RecommendedRow: View {
    let app: RecommendedApp
    @State private var installedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                Group {
                    if let installedURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: installedURL.path)).resizable()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: app.symbol)
                                    .font(.title2)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(5)
                    }
                }
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.s) {
                        Text(app.name).font(.headline)
                        if installedURL != nil {
                            Text("Installed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    Text(app.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let installedURL {
                    Button("Open") {
                        NSWorkspace.shared.openApplication(at: installedURL, configuration: .init())
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .accessibilityLabel("Open \(app.name)")
                } else {
                    Link(destination: app.website) {
                        Text("Website")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help(app.website.absoluteString)
                    .accessibilityLabel("Visit \(app.name)'s website")
                }
            }
            Divider().padding(.leading, 56 + Spacing.m)
        }
        .contextMenu {
            Link("Visit Website", destination: app.website)
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.website.absoluteString, forType: .string)
            }
        }
        .task {
            installedURL = app.bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
        }
    }
}
