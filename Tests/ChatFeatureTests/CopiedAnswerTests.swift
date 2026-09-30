import Foundation
import Testing

@testable import ChatFeature

/// What leaves the app when an answer is copied: its markdown with `[n]` where it cited, and the sources under it —
/// the desktop's rule, string for string (its PDF export of a deep research report does the same).
@Suite("Copying an answer: citations become references")
struct CopiedAnswerTests {
    static let sources: [Int: CitationSource] = [
        1: CitationSource(rank: 1, link: "https://finance.yahoo.com/a", title: "Microsoft jumps"),
        2: CitationSource(rank: 2, link: "https://www.cnbc.com/b", title: "Software ETF falls"),
        3: CitationSource(rank: 3, link: "https://finance.yahoo.com/a", title: "Microsoft jumps (dup)"),
    ]

    static let yahoo = "- [1] Microsoft jumps (finance.yahoo.com) https://finance.yahoo.com/a"

    private func copied(_ markdown: String, sources: [Int: CitationSource] = CopiedAnswerTests.sources) -> String {
        CopiedAnswer.text(markdown: markdown, heading: "References") { sources[$0] }
    }

    private func references(_ lines: String...) -> String {
        "\n\n---\n\n## References\n\n" + lines.joined(separator: "\n")
    }

    @Test("a marker becomes [n], and the sources are listed under the text")
    func markersBecomeReferences() {
        #expect(
            copied("Up 3.66%【1-source】. Sector fell【2-source】.")
                == "Up 3.66%[1]. Sector fell[2]."
                + references(Self.yahoo, "- [2] Software ETF falls (www.cnbc.com) https://www.cnbc.com/b"))
    }

    @Test("n is the source's place in order of first appearance, and a source cited again keeps its number")
    func numberedByFirstAppearance() {
        #expect(
            copied("A【2,1-source】 B【1-source】")
                == "A[1][2] B[2]"
                + references(
                    "- [1] Software ETF falls (www.cnbc.com) https://www.cnbc.com/b",
                    "- [2] Microsoft jumps (finance.yahoo.com) https://finance.yahoo.com/a"))
    }

    @Test("a source is its link: two ranks with one link are one reference, under the first one's title")
    func sameLinkIsOneSource() {
        #expect(copied("A【1-source】 B【3-source】") == "A[1] B[1]" + references(Self.yahoo))
        // Named twice in one marker, it is written once there.
        #expect(copied("A【1,3-source】") == "A[1]" + references(Self.yahoo))
        #expect(copied("A【1, 1-source】") == "A[1]" + references(Self.yahoo))
    }

    @Test("a number no source answers to is dropped; a marker left with none leaves nothing, and no section")
    func unresolved() {
        #expect(copied("A【9-source】 B") == "A B")
        #expect(copied("A【1,9-source】") == "A[1]" + references(Self.yahoo))
        #expect(copied("A【-source】") == "A【-source】")
    }

    @Test("text that cites nothing is copied as it is")
    func noCitations() {
        #expect(copied("No citations.") == "No citations.")
        #expect(copied("Trailing space kept. \n") == "Trailing space kept. \n")
        #expect(copied("") == "")
    }

    @Test("nothing is added or taken away around a marker")
    func spacingIsLeftAlone() {
        #expect(copied("rose 【1-source】 , then") == "rose [1] , then" + references(Self.yahoo))
        #expect(copied("涨幅【1-source】。") == "涨幅[1]。" + references(Self.yahoo))
    }

    @Test("the text's trailing white space goes before the references are appended")
    func trailingSpaceIsTrimmed() {
        #expect(copied("Up【1-source】.  \n\n") == "Up[1]." + references(Self.yahoo))
    }

    @Test("markdown around the markers is untouched: code, tables, headings")
    func markdownIsKept() {
        let markdown = "## Title\n\n| a | b |\n| - | - |\n| 1 | 2【2-source】 |\n\n```swift\nlet a = 1\n```"
        #expect(
            copied(markdown)
                == "## Title\n\n| a | b |\n| - | - |\n| 1 | 2[1] |\n\n```swift\nlet a = 1\n```"
                + references("- [1] Software ETF falls (www.cnbc.com) https://www.cnbc.com/b"))
    }

    @Test("a reference is named by its title, else its site, else its host, else its link")
    func referenceTitle() {
        func line(_ source: CitationSource) -> String {
            String(copied("x【1-source】", sources: [1: source]).split(separator: "\n").last ?? "")
        }
        #expect(
            line(CitationSource(rank: 1, link: "https://a.example/p", title: "", siteName: "A Site"))
                == "- [1] A Site (a.example) https://a.example/p")
        // The title is the host: it is not said twice.
        #expect(line(CitationSource(rank: 1, link: "https://a.example/p")) == "- [1] a.example https://a.example/p")
        #expect(
            line(CitationSource(rank: 1, link: "https://a.example/p", title: "a.example"))
                == "- [1] a.example https://a.example/p")
        // No host to be had: the link stands for itself.
        #expect(line(CitationSource(rank: 1, link: "not a link")) == "- [1] not a link not a link")
        #expect(line(CitationSource(rank: 1, link: "not a link", title: "Notes")) == "- [1] Notes not a link")
        #expect(
            line(CitationSource(rank: 1, link: "https://WWW.Example.com/p", title: "Upper"))
                == "- [1] Upper (www.example.com) https://WWW.Example.com/p")
    }

    @Test("the heading is the one given: the app's word for References")
    func heading() {
        let text = CopiedAnswer.text(markdown: "x【1-source】", heading: "参考资料") { Self.sources[$0] }
        #expect(text == "x[1]\n\n---\n\n## 参考资料\n\n" + Self.yahoo)
    }

    @Test("an answer is copied with the sources of its turn, the last source of a rank standing for it")
    func ofATurn() {
        let turn = AssistantTurn(
            runId: "r", body: "Up【1-source】.",
            sources: [
                CitationSource(rank: 1, link: "https://old.example/x", title: "Old"),
                CitationSource(rank: 1, link: "https://finance.yahoo.com/a", title: "Microsoft jumps"),
            ])
        #expect(CopiedAnswer.text(of: turn, heading: "References") == "Up[1]." + references(Self.yahoo))
    }
}
