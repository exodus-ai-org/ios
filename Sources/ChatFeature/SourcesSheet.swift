import Models
import SwiftUI

/// The sources behind an answer, as the desktop's panel lists them: what the answer cites, then what else its
/// searches found. A tap on a row opens its page; a sheet opened from a citation chip scrolls to that source and
/// marks it.
struct SourcesSheet: View {
    let model: SourcesSheetModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.screenTitle) private var enclosingTitle
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                if model.entries.isEmpty {
                    ContentUnavailableView("ios:chat.message.sources.empty", systemImage: "globe")
                } else {
                    list
                }
            }
            .navigationTitle("chat:messageAction.sources")
            .navigationBarTitleDisplayMode(.inline)
            .screenTitle(
                ScreenTitles.join(
                    String(
                        localized: "chat:messageAction.sources", defaultValue: "Sources",
                        comment: "Reused from the desktop catalog: same meaning on iOS."),
                    enclosingTitle))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            // The rows lie on the sheet itself: a grouped list would set a second, grey surface into the sheet's glass.
            List {
                ForEach(model.sections) { section in
                    // Two kinds of source are told apart; one kind needs no name. The heading is a row of the
                    // list, not a section's header: a plain list pins those, and with no surface of its own the
                    // rows would pass under its words.
                    if model.showsHeaders {
                        SourcesSectionHeader(section: section)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                EdgeInsets(top: section.kind == .cited ? 4 : 16, leading: 20, bottom: 0, trailing: 20))
                    }
                    ForEach(section.entries) { entry in
                        SourceRow(entry: entry) { openURL($0) }
                            .listRowBackground(highlight(entry))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                            .id(entry.id)
                    }
                }
            }
            .listStyle(.plain)
            // A heading is a line of small print, not a row a finger needs.
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .task {
                guard let id = model.highlightedId else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}

extension SourcesSheet {
    /// The source a chip led to, marked: a tinted shape set in from the sheet's edges, in the cards' corner.
    @ViewBuilder
    fileprivate func highlight(_ entry: SourcesSheetModel.Entry) -> some View {
        if entry.isHighlighted {
            CardStyle.innerShape
                .fill(.tint.opacity(0.12))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        } else {
            Color.clear
        }
    }
}

/// "Citations (2)" over what the answer cites, "More" over the rest: the desktop panel's words.
struct SourcesSectionHeader: View {
    let section: SourcesSheetModel.Section

    var body: some View {
        Text(verbatim: Self.title(section))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    static func title(_ section: SourcesSheetModel.Section) -> String {
        switch section.kind {
        case .cited:
            // The desktop's catalog takes the number as text.
            let count = section.entries.count.formatted()
            return String(
                localized: "chat:sourcesPanel.citations", defaultValue: "Citations (\(count))",
                comment: "Heading over the sources an answer cites, in the Sources sheet. %@ is how many.")
        case .more:
            return String(
                localized: "chat:sourcesPanel.more", defaultValue: "More",
                comment: "Heading over the sources an answer's searches found and it does not cite.")
        }
    }
}

struct SourceRow: View {
    let entry: SourcesSheetModel.Entry
    let open: (URL) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let url = entry.url {
            Button { open(url) } label: { content(opensPage: true) }
                .buttonStyle(.plain)
                .accessibilityHint(Text("ios:chat.message.sources.openHint"))
                .accessibilityAddTraits(entry.isHighlighted ? [.isLink, .isSelected] : .isLink)
        } else {
            content(opensPage: false)
        }
    }

    private func content(opensPage: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Where it is from, before what it says: the site's icon and name lead, as they do on its chip.
            SourceIconView(url: entry.iconURL, fallback: entry.iconFallbackURL)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                if let hostLine = entry.hostLine {
                    Text(verbatim: hostLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                Text(verbatim: entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if let snippet = entry.snippet {
                    Text(verbatim: snippet)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 5 : 3)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if opensPage {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
