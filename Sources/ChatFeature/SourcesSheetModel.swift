import Foundation
import MarkdownKit

/// What the Sources sheet lists, and which row a tapped citation chip points at.
struct SourcesSheetModel: Equatable, Identifiable {
    struct Entry: Equatable, Identifiable {
        /// The position in the turn's own list, so two searches that both return a "rank 1" stay two rows.
        let id: Int
        let title: String
        let hostLine: String?
        let snippet: String?
        /// Where a tap goes: only what the markdown layer's link policy lets out of the app.
        let url: URL?
        let isHighlighted: Bool

        init(id: Int, source: CitationSource, isHighlighted: Bool) {
            self.id = id
            self.isHighlighted = isHighlighted
            let url = ExternalLinkPolicy.openableURL(source.link)
            // No hover on a phone: the host line is the only hint of where a tap goes, so it is that URL's own host.
            let host = (url ?? URL(string: source.link))?.host()?.nilIfEmpty
            let siteName = source.siteName?.collapsedWhitespace.nilIfEmpty
            let title = source.title.collapsedWhitespace
            self.title = title.nilIfEmpty ?? siteName ?? host ?? source.link.collapsedWhitespace
            let age = source.age?.collapsedWhitespace ?? ""
            hostLine = [host, age.isEmpty ? nil : age].compactMap { $0 }.joined(separator: Self.separator).nilIfEmpty
            snippet = source.snippet.collapsedWhitespace.nilIfEmpty
            self.url = url
        }

        private static let separator = " \u{00B7} "
    }

    let id: String
    let entries: [Entry]
    /// The row to scroll to and mark, when the sheet was opened from a citation chip.
    let highlightedId: Int?

    /// The turn's own web-search results in the order they were found. A chip's number is resolved the way the chip was
    /// (the last source with that rank, `AssistantTurn.citation(forMarker:)`); a source cited from an earlier turn's
    /// search is not in this list, so it is added first rather than the tap doing nothing.
    init(turn: AssistantTurn, marker: Int? = nil) {
        var sources = turn.sources
        var highlighted: Int?
        if let marker {
            if let index = sources.lastIndex(where: { $0.rank == marker }) {
                highlighted = index
            } else if let earlier = turn.citation(forMarker: marker) {
                sources.insert(earlier, at: 0)
                highlighted = 0
            }
        }
        id = "\(turn.id)#\(marker.map(String.init) ?? "all")"
        entries = sources.enumerated().compactMap { index, source in
            guard Self.hasContent(source) else { return nil }
            return Entry(id: index, source: source, isHighlighted: index == highlighted)
        }
        highlightedId = entries.first(where: \.isHighlighted)?.id
    }

    /// A source with no title, host or link has nothing to show.
    private static func hasContent(_ source: CitationSource) -> Bool {
        [source.title, source.link, source.siteName ?? "", source.hostname ?? ""].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
