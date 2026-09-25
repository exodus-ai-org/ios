import Foundation
import Models
import Testing

@testable import ChatFeature

private func turn(sources: [CitationSource], citations: [CitationSource]? = nil) -> AssistantTurn {
    AssistantTurn(runId: "r1", body: "Answer", sources: sources, citations: citations)
}

private func source(
    _ rank: Int, _ link: String, title: String = "", snippet: String = "", siteName: String? = nil,
    hostname: String? = nil, age: String? = nil
) -> CitationSource {
    CitationSource(
        rank: rank, link: link, title: title, snippet: snippet, siteName: siteName, hostname: hostname, age: age)
}

@Suite("SourcesSheetModel: rows")
struct SourcesSheetRowTests {
    @Test("rows keep the order the searches found them in, one per source, even when two searches both have a rank 1")
    func order() {
        let sources = [
            source(1, "https://a.example/1", title: "A1"), source(2, "https://a.example/2", title: "A2"),
            source(1, "https://b.example/1", title: "B1")
        ]
        let model = SourcesSheetModel(turn: turn(sources: sources))
        #expect(model.entries.map(\.title) == ["A1", "A2", "B1"])
        #expect(model.entries.map(\.id) == [0, 1, 2])
        #expect(model.highlightedId == nil)
        #expect(model.entries.allSatisfy { !$0.isHighlighted })
    }

    @Test("a row shows title, site and age, then the snippet on one line")
    func rowText() {
        let model = SourcesSheetModel(
            turn: turn(sources: [
                source(
                    1, "https://www.swift.org/blog/", title: "Swift 6.2\nReleased", snippet: "First line.\n\n  Second   line.",
                    siteName: "Swift.org", hostname: "www.swift.org", age: "2 weeks ago")
            ]))
        let entry = try! #require(model.entries.first)
        #expect(entry.title == "Swift 6.2 Released")
        #expect(entry.hostLine == "www.swift.org \u{00B7} 2 weeks ago")
        #expect(entry.snippet == "First line. Second line.")
        #expect(entry.url == URL(string: "https://www.swift.org/blog/"))
    }

    @Test("the host line is the host a tap opens: never the site name or the search's hostname")
    func hostIsTheLinksOwn() {
        let model = SourcesSheetModel(
            turn: turn(sources: [
                source(1, "https://x.example/a", title: "T", siteName: "Site", hostname: "host.example"),
                source(2, "https://x.example/a", title: "T", hostname: "host.example"),
                source(3, "https://apple.com@evil.com/login", title: "T", siteName: "Apple"),
                source(4, "javascript://example.com/%0Aalert(1)", title: "T", siteName: "Site"),
                source(5, "not a link", title: "T")
            ]))
        #expect(model.entries.map(\.hostLine) == ["x.example", "x.example", "evil.com", "example.com", nil])
        #expect(model.entries[3].url == nil)
    }

    @Test("a source with no title is named by its site name, then the link's host")
    func titleFallsBackToSiteName() {
        let model = SourcesSheetModel(
            turn: turn(sources: [
                source(1, "https://x.example/a", siteName: "Example News", hostname: "news.example"),
                source(2, "https://x.example/a", hostname: "news.example"),
            ]))
        #expect(model.entries.map(\.title) == ["Example News", "x.example"])
        #expect(model.entries.map(\.hostLine) == ["x.example", "x.example"])
    }

    @Test("a source with no title is named by its host, then by its link; blank snippets and ages are dropped")
    func missingPieces() {
        let model = SourcesSheetModel(
            turn: turn(sources: [
                source(1, "https://x.example/a", hostname: "x.example", age: "  "),
                source(2, "mailto:someone@example.com", title: "  "),
            ]))
        #expect(model.entries[0].title == "x.example")
        #expect(model.entries[0].hostLine == "x.example")
        #expect(model.entries[0].snippet == nil)
        #expect(model.entries[1].title == "mailto:someone@example.com")
    }

    @Test("a source with nothing to show is left out, and the others keep their positions")
    func degenerateSources() {
        let model = SourcesSheetModel(
            turn: turn(sources: [
                source(1, "https://a.example", title: "A"), source(2, ""), source(3, "  ", title: " "),
                source(4, "https://d.example", title: "D")
            ]))
        #expect(model.entries.map(\.title) == ["A", "D"])
        #expect(model.entries.map(\.id) == [0, 3])
    }

    @Test("an empty list is empty, not an error")
    func empty() {
        let model = SourcesSheetModel(turn: turn(sources: []))
        #expect(model.entries.isEmpty)
        #expect(SourcesSheetModel(turn: turn(sources: []), marker: 3).entries.isEmpty)
    }

    @Test("only web and mail links are openable; every other scheme, and a link that is not one, gets no URL")
    func linkPolicy() {
        let links = [
            ("https://ok.example/a", true), ("HTTP://ok.example/a", true), ("mailto:a@b.example", true),
            ("javascript:alert(1)", false), ("tel:+15551234", false), ("sms:+15551234", false),
            ("shortcuts://run-shortcut?name=x", false), ("file:///etc/passwd", false), ("exodus://pair?c=1", false),
            ("exodus-cite://2", false), ("/relative/path", false), ("no scheme.example", false), ("", false)
        ]
        let sources = links.enumerated().map { source($0.offset + 1, $0.element.0, title: "T\($0.offset)") }
        let model = SourcesSheetModel(turn: turn(sources: sources))
        #expect(model.entries.count == links.count)
        for (index, expected) in links.map(\.1).enumerated() {
            #expect((model.entries[index].url != nil) == expected, "\(links[index].0) should\(expected ? "" : " not") open")
        }
        #expect(model.entries.filter { $0.url != nil }.count == 3)
    }

    @Test("whitespace around a link does not stop it opening")
    func paddedLink() {
        let model = SourcesSheetModel(turn: turn(sources: [source(1, "  https://ok.example/a \n", title: "T")]))
        #expect(model.entries.first?.url == URL(string: "https://ok.example/a"))
    }
}

@Suite("SourcesSheetModel: a citation chip's source")
struct SourcesSheetChipTests {
    private let first = [
        source(1, "https://a.example/1", title: "A1"), source(2, "https://a.example/2", title: "A2"),
        source(3, "https://a.example/3", title: "A3")
    ]

    @Test("marker N marks the source with rank N")
    func marksTheRank() {
        let model = SourcesSheetModel(turn: turn(sources: first), marker: 2)
        #expect(model.highlightedId == 1)
        #expect(model.entries.map(\.isHighlighted) == [false, true, false])
        #expect(model.entries.count == 3)
    }

    @Test("after a second search with reset numbering the last source with that rank is the one marked, like the chip")
    func lastRankWins() {
        let second = [source(1, "https://b.example/1", title: "B1"), source(2, "https://b.example/2", title: "B2")]
        let all = first + second
        let model = SourcesSheetModel(turn: turn(sources: all), marker: 1)
        #expect(model.highlightedId == 3)
        #expect(model.entries.filter(\.isHighlighted).map(\.title) == ["B1"])
        // Rank 3 exists only in the first search.
        #expect(SourcesSheetModel(turn: turn(sources: all), marker: 3).highlightedId == 2)
        // The chip's own resolution agrees with the row that is marked.
        let t = turn(sources: all)
        #expect(t.citation(forMarker: 1)?.title == "B1")
    }

    @Test("a chip citing an earlier turn's search puts that source first and marks it")
    func earlierTurnsSource() {
        let earlier = source(4, "https://old.example/4", title: "Old 4")
        let t = turn(sources: first, citations: [earlier] + first)
        let model = SourcesSheetModel(turn: t, marker: 4)
        #expect(model.entries.map(\.title) == ["Old 4", "A1", "A2", "A3"])
        #expect(model.highlightedId == 0)
        #expect(model.entries.first?.isHighlighted == true)
    }

    @Test("a turn with no searches of its own still shows the one source its chip names")
    func onlyAnEarlierSource() {
        let earlier = source(1, "https://old.example/1", title: "Old 1")
        let model = SourcesSheetModel(turn: turn(sources: [], citations: [earlier]), marker: 1)
        #expect(model.entries.map(\.title) == ["Old 1"])
        #expect(model.highlightedId == 0)
    }

    @Test("a marker nothing resolves to opens the plain list with nothing marked")
    func unknownMarker() {
        let model = SourcesSheetModel(turn: turn(sources: first), marker: 9)
        #expect(model.entries.count == 3)
        #expect(model.highlightedId == nil)
    }

    @Test("the marked row's position is its id, so it survives a degenerate source before it")
    func highlightSurvivesADroppedSource() {
        let sources = [source(1, ""), source(2, "https://a.example/2", title: "A2")]
        let model = SourcesSheetModel(turn: turn(sources: sources), marker: 2)
        #expect(model.highlightedId == 1)
        #expect(model.entries.map(\.id) == [1])
    }

    @Test("the sheet's id tells a plain open from a chip's, per turn, so opening one after the other is a new sheet")
    func identity() {
        let t = turn(sources: first)
        #expect(SourcesSheetModel(turn: t).id != SourcesSheetModel(turn: t, marker: 2).id)
        #expect(SourcesSheetModel(turn: t, marker: 2).id != SourcesSheetModel(turn: t, marker: 3).id)
        #expect(SourcesSheetModel(turn: t, marker: 2).id == SourcesSheetModel(turn: t, marker: 2).id)
    }
}
