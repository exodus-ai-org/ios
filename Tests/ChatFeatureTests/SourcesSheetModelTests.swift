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
        #expect(Set(model.entries.map(\.id)).count == 3)
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
                source(2, "https://x.example/b", title: "T", hostname: "host.example"),
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
                source(2, "https://x.example/b", hostname: "news.example"),
            ]))
        #expect(model.entries.map(\.title) == ["Example News", "x.example"])
        #expect(model.entries.map(\.hostLine) == ["x.example", "x.example"])
    }

    @Test("a snippet is shown as words: its markdown and HTML are taken off")
    func snippetIsPlain() {
        let model = SourcesSheetModel(
            turn: turn(
                sources: [
                    source(
                        1, "https://x.example/a", title: "A",
                        snippet: "**Swift 6.2** is <strong>out</strong> — see [the notes](https://x.example/n).")
                ]))
        #expect(model.entries.first?.snippet == "Swift 6.2 is out — see the notes.")
    }

    @Test("a row carries its site's icon as the desktop does: the one the search gave, else Google's for the site")
    func icons() {
        let given = CitationSource(rank: 1, link: "https://x.example/a", favicon: "https://icons.example/x.png")
        let none = CitationSource(rank: 2, link: "https://www.swift.org/blog/")
        let plainHTTP = CitationSource(rank: 3, link: "https://y.example/", favicon: "http://icons.example/y.png")
        let model = SourcesSheetModel(turn: turn(sources: [given, none, plainHTTP]))
        #expect(model.entries[0].iconURL == URL(string: "https://icons.example/x.png"))
        #expect(model.entries[1].iconURL?.host() == "www.google.com")
        #expect(model.entries[1].iconURL?.path() == "/s2/favicons")
        #expect(model.entries[1].iconURL?.query()?.contains("domain=www.swift.org") == true)
        // An icon that may not be fetched (plain http) gives way to Google's for the site.
        #expect(model.entries[2].iconURL?.query()?.contains("domain=y.example") == true)
    }

    @Test("when the search's own icon does not load, Google's for the site is tried; Google's own has nothing behind it")
    func iconFallback() {
        let given = CitationSource(rank: 1, link: "https://x.example/a", favicon: "https://icons.example/x.png")
        let none = CitationSource(rank: 2, link: "https://www.swift.org/blog/")
        #expect(SourceIcon.fallback(for: given) == SourceIcon.google(host: "x.example"))
        #expect(SourceIcon.fallback(for: given)?.query()?.contains("domain=x.example") == true)
        #expect(SourceIcon.url(for: none) == SourceIcon.google(host: "www.swift.org"))
        #expect(SourceIcon.fallback(for: none) == nil)
        let model = SourcesSheetModel(turn: turn(sources: [given, none]))
        #expect(model.entries.map(\.iconFallbackURL) == [SourceIcon.google(host: "x.example"), nil])
        // A source with no site to name has no icon at all: the default glyph is drawn.
        #expect(SourceIcon.url(for: CitationSource(rank: 3, link: "not a link")) == nil)
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
        #expect(Set(model.entries.map(\.id)).count == 2)
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

    @Test("the chip's source is a cited one: it stands first, marked, over the rest")
    func marksTheRank() {
        let model = SourcesSheetModel(turn: turn(sources: first), marker: 2)
        #expect(model.entries.map(\.title) == ["A2", "A1", "A3"])
        #expect(model.entries.map(\.isHighlighted) == [true, false, false])
        #expect(model.highlightedId == model.entries[0].id)
    }

    @Test("after a second search with reset numbering the last source with that rank is the one marked, like the chip")
    func lastRankWins() {
        let second = [source(1, "https://b.example/1", title: "B1"), source(2, "https://b.example/2", title: "B2")]
        let all = first + second
        let model = SourcesSheetModel(turn: turn(sources: all), marker: 1)
        #expect(model.entries.filter(\.isHighlighted).map(\.title) == ["B1"])
        #expect(model.entries.map(\.title) == ["B1", "A1", "A2", "A3", "B2"])
        // Rank 3 exists only in the first search.
        #expect(SourcesSheetModel(turn: turn(sources: all), marker: 3).entries.first?.title == "A3")
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
        #expect(model.entries.first?.isHighlighted == true)
    }

    @Test("a marker nothing resolves to opens the plain list with nothing marked")
    func unknownMarker() {
        let model = SourcesSheetModel(turn: turn(sources: first), marker: 9)
        #expect(model.entries.map(\.title) == ["A1", "A2", "A3"])
        #expect(model.highlightedId == nil)
    }

    @Test("the marked row keeps an id of its own when a source with nothing to show is left out")
    func highlightSurvivesADroppedSource() {
        let sources = [source(1, ""), source(2, "https://a.example/2", title: "A2")]
        let model = SourcesSheetModel(turn: turn(sources: sources), marker: 2)
        #expect(model.entries.map(\.title) == ["A2"])
        #expect(model.highlightedId == model.entries[0].id)
    }

    @Test("the sheet's id tells a plain open from a chip's, per turn, so opening one after the other is a new sheet")
    func identity() {
        let t = turn(sources: first)
        #expect(SourcesSheetModel(turn: t).id != SourcesSheetModel(turn: t, marker: 2).id)
        #expect(SourcesSheetModel(turn: t, marker: 2).id != SourcesSheetModel(turn: t, marker: 3).id)
        #expect(SourcesSheetModel(turn: t, marker: 2).id == SourcesSheetModel(turn: t, marker: 2).id)
    }
}

private func cite(_ ranks: Int...) -> String { "\u{3010}" + ranks.map(String.init).joined(separator: ",") + "-source\u{3011}" }

@Suite("SourcesSheetModel: what the answer cites, and what else it found")
struct SourcesSheetSectionTests {
    private func turn(_ body: String, sources: [CitationSource], citations: [CitationSource]? = nil) -> AssistantTurn {
        AssistantTurn(runId: "r2", body: body, sources: sources, citations: citations)
    }

    private let earlier = [
        source(1, "https://a.example/1", title: "A1"), source(2, "https://a.example/2", title: "A2"),
        source(3, "https://a.example/3", title: "A3")
    ]

    @Test("a turn that searched nothing itself lists every source it cites from an earlier turn, not the tapped one alone")
    func citesAnEarlierTurn() {
        let t = turn("Rain\(cite(3)) then sun\(cite(1)).", sources: [], citations: earlier)
        let model = SourcesSheetModel(turn: t, marker: 1)
        #expect(model.sections.map(\.kind) == [.cited])
        #expect(model.entries.map(\.title) == ["A3", "A1"])
        #expect(model.entries.map(\.isHighlighted) == [false, true])
        #expect(!model.showsHeaders)
    }

    @Test("what the answer cites stands first, in the order it cites it; the rest follows as found")
    func citedThenMore() {
        let found = (1...10).map { source($0, "https://s\($0).example/", title: "S\($0)") }
        let model = SourcesSheetModel(turn: turn("One\(cite(7)) two\(cite(2, 7)).", sources: found))
        #expect(model.sections.map(\.kind) == [.cited, .more])
        #expect(model.sections[0].entries.map(\.title) == ["S7", "S2"])
        #expect(model.sections[1].entries.map(\.title) == ["S1", "S3", "S4", "S5", "S6", "S8", "S9", "S10"])
        #expect(model.showsHeaders)
        #expect(Set(model.entries.map(\.id)).count == 10)
    }

    @Test("a page is one row, whatever ranks name it")
    func onePagePerRow() {
        let found = [
            source(1, "https://a.example/1", title: "A1"), source(2, "https://a.example/1", title: "A1 again"),
            source(3, "https://b.example/1", title: "B1")
        ]
        let cited = SourcesSheetModel(turn: turn("X\(cite(1, 2)).", sources: found))
        #expect(cited.entries.map(\.title) == ["A1", "B1"])
        let uncited = SourcesSheetModel(turn: turn("X.", sources: found))
        #expect(uncited.entries.map(\.title) == ["A1", "B1"])
    }

    @Test("a marker no source answers to is no row")
    func unresolved() {
        let model = SourcesSheetModel(turn: turn("X\(cite(9)).", sources: earlier))
        #expect(model.sections.map(\.kind) == [.more])
        #expect(model.entries.map(\.title) == ["A1", "A2", "A3"])
    }

    @Test("nothing cited: one list, no headings")
    func onlyMore() {
        let model = SourcesSheetModel(turn: turn("X.", sources: earlier))
        #expect(model.sections.map(\.kind) == [.more])
        #expect(!model.showsHeaders)
    }
}

@Suite("TurnSources: the Sources button")
struct TurnSourcesTests {
    @Test("a turn that only cites an earlier turn's search still offers its sources")
    func citedOnly() {
        let earlier = [source(1, "https://a.example/1", title: "A1"), source(2, "https://b.example/2", title: "B2")]
        let t = AssistantTurn(runId: "r2", body: "Rain\(cite(2)).", sources: [], citations: earlier)
        let bar = TurnActions.bar(for: t, isStreaming: false, canRegenerate: false)
        #expect(bar?.showsSources == true)
        #expect(bar?.sourceCount == 1)
        #expect(bar?.sourceIcons.map(\.id) == ["https://b.example"])
    }

    @Test("the button counts pages, cited first")
    func citedFirst() {
        let found = [
            source(1, "https://a.example/1", title: "A1"), source(2, "https://b.example/2", title: "B2"),
            source(3, "https://b.example/2", title: "B2 again")
        ]
        let t = AssistantTurn(runId: "r1", body: "Rain\(cite(2)).", sources: found)
        let bar = TurnActions.bar(for: t, isStreaming: false, canRegenerate: false)
        #expect(bar?.sourceCount == 2)
        #expect(bar?.sourceIcons.map(\.id) == ["https://b.example", "https://a.example"])
    }
}
