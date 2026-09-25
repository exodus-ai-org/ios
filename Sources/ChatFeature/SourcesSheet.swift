import SwiftUI

/// The web-search results behind an answer, in the order they were found. A tap on a row opens its page; a sheet opened
/// from a citation chip scrolls to that source and marks it.
struct SourcesSheet: View {
    let model: SourcesSheetModel
    @Environment(\.dismiss) private var dismiss
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
            List(model.entries) { entry in
                SourceRow(entry: entry) { openURL($0) }
                    .listRowBackground(entry.isHighlighted ? Color.accentColor.opacity(0.14) : nil)
                    .id(entry.id)
            }
            .task {
                guard let id = model.highlightedId else { return }
                proxy.scrollTo(id, anchor: .center)
            }
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
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if let hostLine = entry.hostLine {
                    Text(verbatim: hostLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                if let snippet = entry.snippet {
                    Text(verbatim: snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
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
