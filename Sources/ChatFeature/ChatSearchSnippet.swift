import Foundation

/// Builds the one-line context shown under a search result's title.
enum ChatSearchSnippet {
    static let charactersBefore = 40
    static let charactersAfter = 80
    static let fallbackLength = 120

    /// `text` is a hit's `searchText`. The window is centred on the first case- and
    /// diacritic-insensitive match of `query`; with no match it is the start of the text. Nil when
    /// there is no text.
    static func make(from text: String?, query: String) -> String? {
        guard let text else { return nil }
        let collapsed = text.collapsedWhitespace
        guard !collapsed.isEmpty else { return nil }
        let needle = query.collapsedWhitespace
        if !needle.isEmpty,
            let match = collapsed.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
        {
            let start =
                collapsed.index(match.lowerBound, offsetBy: -charactersBefore, limitedBy: collapsed.startIndex)
                ?? collapsed.startIndex
            let end =
                collapsed.index(match.upperBound, offsetBy: charactersAfter, limitedBy: collapsed.endIndex)
                ?? collapsed.endIndex
            return window(of: collapsed, from: start, to: end)
        }
        let end =
            collapsed.index(collapsed.startIndex, offsetBy: fallbackLength, limitedBy: collapsed.endIndex)
            ?? collapsed.endIndex
        return window(of: collapsed, from: collapsed.startIndex, to: end)
    }

    private static func window(of text: String, from start: String.Index, to end: String.Index) -> String {
        var snippet = text[start..<end].trimmingCharacters(in: .whitespaces)
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet += "…" }
        return snippet
    }
}
