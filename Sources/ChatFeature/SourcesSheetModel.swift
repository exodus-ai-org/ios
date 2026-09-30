import Foundation
import MarkdownKit

/// What the Sources sheet lists, and which row a tapped citation chip points at.
struct SourcesSheetModel: Equatable, Identifiable {
    struct Entry: Equatable, Identifiable {
        /// The row's place among the turn's sources, cited ones first: ranks repeat from one search to the next.
        let id: Int
        let title: String
        let hostLine: String?
        let snippet: String?
        /// Where a tap goes: only what the markdown layer's link policy lets out of the app.
        let url: URL?
        /// The site's icon, where one may be fetched, and what is tried when it does not load.
        let iconURL: URL?
        let iconFallbackURL: URL?
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
            // A snippet is the page's or the search engine's own text, markdown and HTML included: shown as words.
            snippet = MarkdownPlainText.strip(source.snippet).nilIfEmpty
            self.url = url
            iconURL = SourceIcon.url(for: source)
            iconFallbackURL = SourceIcon.fallback(for: source)
        }

        private static let separator = " \u{00B7} "
    }

    /// What the answer cites, or what else its searches found: the desktop panel's "Citations" and "More".
    struct Section: Equatable, Identifiable {
        enum Kind: Equatable, Sendable {
            case cited, more
        }

        let kind: Kind
        let entries: [Entry]

        var id: Kind { kind }
    }

    let id: String
    /// The cited sources, then the rest; a section with no rows is not there.
    let sections: [Section]
    /// The row to scroll to and mark, when the sheet was opened from a citation chip.
    let highlightedId: Int?

    var entries: [Entry] { sections.flatMap(\.entries) }
    /// With one section there is nothing to tell apart.
    var showsHeaders: Bool { sections.count > 1 }

    /// A chip's number is resolved the way the chip was (`AssistantTurn.citation(forMarker:)`), and its source is
    /// among the cited ones whether the turn found it itself or an earlier turn did (`TurnSources`).
    init(turn: AssistantTurn, marker: Int? = nil) {
        let sources = TurnSources(turn: turn, tapped: marker)
        let tapped = marker.flatMap { turn.citation(forMarker: $0) }.map(TurnSources.page)
        var next = 0
        var highlighted: Int?
        func entries(_ list: [CitationSource]) -> [Entry] {
            list.compactMap { source in
                defer { next += 1 }
                guard Self.hasContent(source) else { return nil }
                let marked = highlighted == nil && tapped == TurnSources.page(source)
                if marked { highlighted = next }
                return Entry(id: next, source: source, isHighlighted: marked)
            }
        }
        id = "\(turn.id)#\(marker.map(String.init) ?? "all")"
        sections = [Section(kind: .cited, entries: entries(sources.cited)), Section(kind: .more, entries: entries(sources.more))]
            .filter { !$0.entries.isEmpty }
        highlightedId = highlighted
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
