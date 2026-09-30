import Foundation

/// The `【N-source】` markers of an answer's text.
enum CitationMarkers {
    /// `【1-source】`, `【1, 2-source】`.
    nonisolated(unsafe) private static let marker = #/\u{3010}([0-9,\s]+)-source\u{3011}/#

    /// The ranks a text cites, each once, in the order it first cites them.
    static func ranks(in text: String) -> [Int] {
        var ranks: [Int] = []
        for match in text.matches(of: marker) {
            for part in match.1.split(separator: ",") {
                guard let rank = Int(part.trimmingCharacters(in: .whitespaces)), !ranks.contains(rank) else { continue }
                ranks.append(rank)
            }
        }
        return ranks
    }
}

/// The sources of a turn as the Sources sheet and the Sources button show them — the desktop's panel: what the
/// answer cites, then what else its searches found. What it cites is resolved the way its chips are
/// (`AssistantTurn.citation(forMarker:)`: every source seen up to this turn, the last of a rank), so a turn that
/// searched nothing itself and cites an earlier turn's results has sources too. A page is listed once, whatever
/// ranks name it.
struct TurnSources: Equatable {
    /// In the order the answer first cites them.
    let cited: [CitationSource]
    /// The turn's own results the answer does not cite, in the order they were found.
    let more: [CitationSource]

    var all: [CitationSource] { cited + more }

    /// `marker` is a chip that was tapped: a chip stands where the answer cites, so its source is a cited one.
    init(turn: AssistantTurn, tapped marker: Int? = nil) {
        var ranks = CitationMarkers.ranks(in: turn.body)
        if let marker, !ranks.contains(marker) { ranks.append(marker) }
        var pages = Set<String>()
        var cited: [CitationSource] = []
        for rank in ranks {
            guard let source = turn.citation(forMarker: rank), pages.insert(Self.page(source)).inserted else { continue }
            cited.append(source)
        }
        self.cited = cited
        more = turn.sources.filter { pages.insert(Self.page($0)).inserted }
    }

    /// What makes two sources the same page: their link. A source without one is a page of its own.
    static func page(_ source: CitationSource) -> String {
        let link = source.link.trimmingCharacters(in: .whitespacesAndNewlines)
        return link.isEmpty ? "rank:\(source.rank):\(source.title)" : link
    }
}
