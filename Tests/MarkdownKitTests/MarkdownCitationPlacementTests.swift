import Foundation
import Testing

@testable import MarkdownKit

/// A marker is a chip wherever it stands in running text — inside bold, emphasis, a struck run, a heading, a
/// link's text, a table cell, a quote — and stays as typed only in code. The desktop's `remarkCitations` cases.
@Suite("Citation markers: a chip wherever the marker stands")
struct MarkdownCitationPlacementTests {
    private let citations: [Int: MarkdownCitation] = [
        1: MarkdownCitation(number: 1, title: "Swift", host: "www.swift.org"),
        2: MarkdownCitation(number: 2, title: "Docs", host: "Apple Developer"),
    ]

    private static let marker = "\u{3010}1-source\u{3011}"

    private func styled(_ content: AttributedString, spec: MarkdownFontSpec = .body) -> MarkdownInlineStyler.Output {
        MarkdownInlineStyler.style(content, spec: spec, citations: citations)
    }

    /// The text as it reads: a chip as `⟦label⟧`.
    private func shape(_ output: MarkdownInlineStyler.Output) -> String {
        output.segments.map { segment in
            switch segment {
            case .text(let text): String(text.characters)
            case .chip(let chip): "\u{27E6}\(chip.title)\u{27E7}"
            }
        }.joined()
    }

    private func inline(_ text: String) -> AttributedString? {
        switch MarkdownParser.parse(text).first?.kind {
        case .paragraph(let content), .heading(_, let content): content
        default: nil
        }
    }

    @Test(
        "in bold, emphasis and a struck run the marker is a chip, and the words keep their style",
        arguments: [
            ("**Revenue rose 12%\(marker)** this year.", "Revenue rose 12%\u{2009}\u{27E6}swift.org\u{27E7}\u{2009}this year."),
            ("*Revenue rose 12% \(marker)* this year.", "Revenue rose 12%\u{2009}\u{27E6}swift.org\u{27E7}\u{2009}this year."),
            ("~~Revenue fell\(marker)~~ it rose.", "Revenue fell\u{2009}\u{27E6}swift.org\u{27E7}\u{2009}it rose."),
            ("***Both\(marker)*** end.", "Both\u{2009}\u{27E6}swift.org\u{27E7}\u{2009}end."),
        ]
    )
    func insideEmphasis(text: String, reads: String) throws {
        let output = styled(try #require(inline(text)))
        #expect(output.chips == [1])
        #expect(shape(output) == reads)
        #expect(!shape(output).contains("source"))
    }

    @Test("in a heading the marker is a chip")
    func insideHeading() throws {
        let blocks = MarkdownParser.parse("## What the page says \(Self.marker)\n\nBody.")
        guard case .heading(let level, let content) = blocks.first?.kind else {
            Issue.record("expected a heading")
            return
        }
        let output = styled(content, spec: MarkdownLayoutRules.headingFont(level: level))
        #expect(level == 2)
        #expect(output.chips == [1])
        #expect(shape(output) == "What the page says\u{2009}\u{27E6}swift.org\u{27E7}")
    }

    @Test("in a link's text the marker is a chip and the link is still a link, with its words")
    func insideLinkText() throws {
        let content = try #require(inline("See [the release notes\(Self.marker)](https://www.swift.org/blog) for more."))
        let output = styled(content)
        #expect(output.chips == [1])
        #expect(!shape(output).contains("source"))
        #expect(!shape(output).contains("]("))
        #expect(!shape(output).contains("["))
        #expect(shape(output).contains("the release notes"))
        #expect(shape(output).contains("\u{27E6}swift.org\u{27E7}"))

        var linked: [String] = []
        for case .text(let text) in output.segments {
            for run in text.runs where run.link == URL(string: "https://www.swift.org/blog") {
                linked.append(String(text[run.range].characters))
            }
        }
        #expect(linked.joined().contains("the release notes"))
    }

    @Test("two markers in one link's text, and a marker in each of two links")
    func severalInLinks() throws {
        let content = try #require(
            inline("[one\(Self.marker) two\u{3010}2-source\u{3011}](https://a.example) and [three\(Self.marker)](https://b.example)."))
        let output = styled(content)
        #expect(output.chips == [1, 2])
        #expect(!shape(output).contains("]("))
        #expect(shape(output).contains("one"))
        #expect(shape(output).contains("two"))
        #expect(shape(output).contains("three"))
    }

    @Test(
        "a link cannot hold a link: a marker written in a link's text follows the link, and only there",
        arguments: [
            ("See [notes\(marker)](https://x.com) now", "See [notes](https://x.com)[1](exodus-cite://1) now"),
            ("[a\(marker) b\u{3010}2-source\u{3011}](https://x.com)", "[a b](https://x.com)[1](exodus-cite://1)[2](exodus-cite://2)"),
            (
                "[a\(marker)](https://x.com/a_(b) \"title\").",
                "[a](https://x.com/a_(b) \"title\")[1](exodus-cite://1)."
            ),
            ("[a\(marker)](<https://x.com/a b>) end", "[a](<https://x.com/a b>)[1](exodus-cite://1) end"),
            ("**[a\(marker)](https://x.com)**", "**[a](https://x.com)[1](exodus-cite://1)**"),
            ("[a [b] \(marker)](https://x.com)", "[a [b] ](https://x.com)[1](exodus-cite://1)"),
            // Not a link's text: brackets nothing closes as a link, an image's description, another paragraph.
            ("[note \(marker)] then", "[note [1](exodus-cite://1)] then"),
            ("![alt \(marker)](https://x.com/a.png)", "![alt [1](exodus-cite://1)](https://x.com/a.png)"),
            ("[open\n\nnext \(marker)](https://x.com)", "[open\n\nnext [1](exodus-cite://1)](https://x.com)"),
            ("\\[a \(marker)](https://x.com)", "\\[a [1](exodus-cite://1)](https://x.com)"),
            ("[a](https://x.com) \(marker)", "[a](https://x.com) [1](exodus-cite://1)"),
            ("[a\(marker)](https://x.com", "[a[1](exodus-cite://1)](https://x.com"),
        ]
    )
    func markerInLinkText(input: String, expected: String) {
        #expect(MarkdownPreprocessor.rewriteCitations(input).text == expected)
    }

    @Test("in a table cell and in a quote the marker is a chip")
    func insideCellAndQuote() throws {
        let table = MarkdownParser.parse("| Item | Source |\n| --- | --- |\n| **GDP\(Self.marker)** | up |")
        guard case .table(let parsed) = table.first?.kind, let cell = parsed.rows.first?.first else {
            Issue.record("expected a table")
            return
        }
        #expect(styled(cell).chips == [1])
        #expect(!shape(styled(cell)).contains("source"))

        let quote = MarkdownParser.parse("> Quoted *claim\(Self.marker)* here.")
        guard case .blockquote(let blocks) = quote.first?.kind, case .paragraph(let content) = blocks.first?.kind else {
            Issue.record("expected a quote with a paragraph")
            return
        }
        #expect(styled(content).chips == [1])
        #expect(shape(styled(content)) == "Quoted claim\u{2009}\u{27E6}swift.org\u{27E7}\u{2009}here.")
    }

    @Test("in inline code and in a code block the marker stays as typed")
    func literalInCode() throws {
        let output = styled(try #require(inline("Write `\(Self.marker)` to cite.")))
        #expect(output.chips.isEmpty)
        #expect(shape(output) == "Write \(Self.marker) to cite.")

        let blocks = MarkdownParser.parse("```\n\(Self.marker)\n```")
        guard case .codeBlock(_, let code) = blocks.first?.kind else {
            Issue.record("expected a code block")
            return
        }
        #expect(code.contains(Self.marker))
    }

    @Test("an image's description is not a link's text: a marker beside an image is still a chip")
    func besideAnImage() throws {
        let output = styled(try #require(inline("A chart, described \(Self.marker).")))
        #expect(output.chips == [1])
    }
}
