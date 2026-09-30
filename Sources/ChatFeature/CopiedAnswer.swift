import Foundation

/// An answer as it leaves the app — the bar's Copy, the long press's Copy, Select Text: its markdown as written,
/// with `[n]` where it cited and the sources listed under it, instead of the `【N-source】` markers only this app
/// can read. The desktop copies by the same rule, string for string, and its PDF of a research report is where
/// the rule comes from. (Read aloud has its own: the markers are dropped, `SpeechText`.)
enum CopiedAnswer {
    /// `【1-source】`, `【1, 2-source】`.
    nonisolated(unsafe) private static let marker = #/\u{3010}([0-9,\s]+)-source\u{3011}/#

    /// A source as the references list it.
    struct Reference: Equatable {
        let number: Int
        let title: String
        let host: String?
        let link: String

        /// `- [1] Title (host) link`; the host is not said twice when it is the title.
        var line: String {
            guard let host, host != title else { return "- [\(number)] \(title) \(link)" }
            return "- [\(number)] \(title) (\(host)) \(link)"
        }
    }

    /// The answer of a turn, with the sources of that turn: a marker means the last source of its rank.
    static func text(of turn: AssistantTurn, heading: String = CopiedAnswer.heading) -> String {
        text(markdown: turn.body, heading: heading) { turn.citation(forMarker: $0) }
    }

    /// - A marker's numbers that a source answers to become `[n]`, n being the source's place in order of first
    ///   appearance; a source is its link, so one cited again — under another rank too — keeps its number, and is
    ///   written once where a marker names it twice. A number nothing answers to is dropped, and a marker left
    ///   with none leaves nothing. No space is added or taken away.
    /// - With a reference written, the text loses its trailing white space and gains the list.
    static func text(markdown: String, heading: String, source: (Int) -> CitationSource?) -> String {
        var references: [Reference] = []
        var numberOfLink: [String: Int] = [:]
        let replaced = markdown.replacing(marker) { match in
            var written: [Int] = []
            for part in match.1.split(separator: ",") {
                guard let rank = Int(part.trimmingCharacters(in: .whitespaces)), let cited = source(rank) else { continue }
                let number: Int
                if let known = numberOfLink[cited.link] {
                    number = known
                } else {
                    number = references.count + 1
                    numberOfLink[cited.link] = number
                    references.append(reference(number, cited))
                }
                if !written.contains(number) { written.append(number) }
            }
            return written.map { "[\($0)]" }.joined()
        }
        guard !references.isEmpty else { return replaced }
        let text = String(replaced.trimmingSuffix(while: \.isWhitespace))
        return text + "\n\n---\n\n## \(heading)\n\n" + references.map(\.line).joined(separator: "\n")
    }

    /// Named by its title, else its site, else its host, else its link.
    static func reference(_ number: Int, _ source: CitationSource) -> Reference {
        let host = host(of: source.link)
        let names = [source.title, source.siteName ?? "", host ?? ""]
        let title = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? source.link
        return Reference(number: number, title: title, host: host, link: source.link)
    }

    /// The link's host as a browser names it, lower case; nil when the link has none.
    static func host(of link: String) -> String? {
        guard let host = URL(string: link)?.host(), !host.isEmpty else { return nil }
        return host.lowercased()
    }

    static var heading: String {
        String(
            localized: "chat:deepResearchCard.referencesHeading", defaultValue: "References",
            comment: "Heading of the list of sources under a copied answer, and under a research report.")
    }
}

extension Substring {
    fileprivate func trimmingSuffix(while predicate: (Character) -> Bool) -> Substring {
        var end = endIndex
        while end > startIndex, predicate(self[index(before: end)]) { end = index(before: end) }
        return self[startIndex..<end]
    }
}

extension String {
    fileprivate func trimmingSuffix(while predicate: (Character) -> Bool) -> Substring {
        self[...].trimmingSuffix(while: predicate)
    }
}
