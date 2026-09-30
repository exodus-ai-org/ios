import Foundation
import Testing

@testable import ChatFeature

@Suite("Timeline: the sites a search found, as pills")
struct TimelineSourcesTests {
    private func source(_ rank: Int, _ link: String, site: String? = nil, title: String = "") -> CitationSource {
        CitationSource(rank: rank, link: link, title: title, siteName: site)
    }

    @Test("one pill per site, in the order the sites were first seen, each with how many results it gave")
    func groupsBySite() {
        let pills = TimelineSources.pills([
            source(1, "https://finance.yahoo.com/a", site: "Yahoo! Finance"),
            source(2, "https://www.fool.com/a", site: "The Motley Fool"),
            source(3, "https://www.fool.com/b", site: "The Motley Fool"),
            source(4, "https://finance.yahoo.com/b", site: "Yahoo! Finance"),
            source(5, "https://finance.yahoo.com/c", site: "Yahoo! Finance"),
        ])
        #expect(pills.sites.map(\.name) == ["Yahoo! Finance", "The Motley Fool"])
        #expect(pills.sites.map(\.count) == [3, 2])
        #expect(pills.sites.map(\.first.rank) == [1, 2])
        #expect(pills.more == 0)
    }

    @Test("a site is what its pill reads: two hosts under one name are one pill, whatever the case")
    func sameNameIsOneSite() {
        let pills = TimelineSources.pills([
            source(1, "https://www.investing.com/a", site: "Investing.com"),
            source(2, "https://uk.investing.com/a", site: "investing.com"),
        ])
        #expect(pills.sites.map(\.name) == ["Investing.com"])
        #expect(pills.sites.map(\.count) == [2])
    }

    @Test("a result with no site name goes by its host")
    func hostWhenNoName() {
        let pills = TimelineSources.pills([
            source(1, "https://www.reddit.com/r/a"), source(2, "https://www.reddit.com/r/b"),
        ])
        #expect(pills.sites.map(\.name) == ["www.reddit.com"])
        #expect(pills.sites.map(\.count) == [2])
    }

    @Test("a single result is a single pill with no count to show")
    func oneResult() {
        let pills = TimelineSources.pills([source(1, "https://swift.org/a", site: "Swift.org")])
        #expect(pills.sites.count == 1)
        #expect(pills.sites[0].count == 1)
        #expect(pills.sites[0].countText == nil)
        #expect(pills.more == 0)
    }

    @Test("the count is shown from two results up")
    func countText() {
        let pills = TimelineSources.pills([source(1, "https://a.example/1"), source(2, "https://a.example/2")])
        #expect(pills.sites[0].countText == "2")
    }

    private func sites(_ count: Int) -> [CitationSource] {
        (1...count).map { source($0, "https://site\($0).example/page", site: "Site \($0)") }
    }

    @Test("eight sites are eight pills and nothing more")
    func exactlyTheLimit() {
        let pills = TimelineSources.pills(sites(8))
        #expect(pills.sites.count == 8)
        #expect(pills.more == 0)
    }

    @Test("the ninth site and those after it are counted, not shown")
    func pastTheLimit() {
        let nine = TimelineSources.pills(sites(9))
        #expect(nine.sites.map(\.name) == (1...8).map { "Site \($0)" })
        #expect(nine.more == 1)
        let many = TimelineSources.pills(sites(30) + [source(31, "https://site1.example/again", site: "Site 1")])
        #expect(many.sites.count == 8)
        #expect(many.more == 22)
        // A result of a site that is shown still counts on its pill.
        #expect(many.sites[0].count == 2)
    }

    @Test("a result whose link has no host is a pill of its own, by its title, else its link")
    func noHost() {
        let pills = TimelineSources.pills([
            source(1, "not a link", title: "A pasted note"), source(2, "mailto:someone", title: ""),
            source(3, "also not a link", title: "A pasted note"),
        ])
        #expect(pills.sites.map(\.name) == ["A pasted note", "mailto:someone"])
        #expect(pills.sites.map(\.count) == [2, 1])
    }

    @Test("no results, no pills")
    func empty() {
        let pills = TimelineSources.pills([])
        #expect(pills.sites.isEmpty)
        #expect(pills.more == 0)
    }
}
