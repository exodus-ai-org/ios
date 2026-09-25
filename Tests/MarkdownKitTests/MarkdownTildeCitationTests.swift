import Foundation
import Testing

@testable import MarkdownKit

@Suite("MarkdownPreprocessor lone tilde and citations")
struct MarkdownTildeCitationTests {
    private func strikes(_ text: String) -> [String] {
        MarkdownParser.parse(text).flatMap { block -> [String] in
            guard case .paragraph(let content) = block.kind else { return [] }
            return MarkdownFixtures.runs(content).filter { $0.intent.contains(.strikethrough) }.map(\.text)
        }
    }

    @Test("a single tilde is how people write a range, so only ~~ strikes through")
    func rangesStayLiteral() {
        let ranges = "全天温度区间19~32°C，午后（12点~15点）最热能到30~32°C，降雨概率1~10%。"
        #expect(strikes(ranges).isEmpty)
        #expect(MarkdownFixtures.paragraphText(MarkdownParser.parse(ranges)) == [ranges])
        #expect(strikes("~~old~~ new") == ["old"])
    }

    @Test("19~32°C to 5~10°C renders literally; ~~gone~~ still strikes")
    func mixedTildes() {
        let text = "19~32°C to 5~10°C and ~~gone~~ now"
        #expect(strikes(text) == ["gone"])
        #expect(MarkdownFixtures.paragraphText(MarkdownParser.parse(text)) == ["19~32°C to 5~10°C and gone now"])
    }

    @Test(
        "escapeLoneTilde escapes only a lone tilde outside code",
        arguments: [
            ("19~32°C to 5~10°C", "19\\~32°C to 5\\~10°C"),
            ("~~x~~", "~~x~~"),
            ("a ~b~ `c~d`", "a \\~b\\~ `c~d`"),
            ("a ~b~\n\n```\nx~y\n```", "a \\~b\\~\n\n```\nx~y\n```"),
            ("a ~b~\n\n    indented~code", "a \\~b\\~\n\n    indented~code"),
            ("a ~b~ <https://x.com/~u>", "a \\~b\\~ <https://x.com/~u>"),
            ("a ~b~ $$x~y$$", "a \\~b\\~ $$x~y$$"),
            ("a ~b~ and \\~c", "a \\~b\\~ and \\~c"),
            ("no strike at all 1~2", "no strike at all 1~2"),
        ]
    )
    func escapeLoneTilde(input: String, expected: String) {
        #expect(MarkdownPreprocessor.escapeLoneTilde(input) == expected)
    }

    @Test("a tilde inside inline code stays in the code run")
    func tildeInCode() {
        let blocks = MarkdownParser.parse("run `a~b` and x~y~z")
        guard case .paragraph(let content) = blocks.first?.kind else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(MarkdownFixtures.plain(content) == "run a~b and x~y~z")
        #expect(MarkdownFixtures.runs(content).contains { $0.text == "a~b" && $0.intent.contains(.code) })
    }

    @Test(
        "rewriteCitations turns each marker into exodus-cite links",
        arguments: [
            ("It rained 【1-source】 and cleared 【2-source】.", "It rained [1](exodus-cite://1) and cleared [2](exodus-cite://2).", [1, 2]),
            ("both 【1,2-source】", "both [1](exodus-cite://1)[2](exodus-cite://2)", [1, 2]),
            ("spaced 【3, 4-source】", "spaced [3](exodus-cite://3)[4](exodus-cite://4)", [3, 4]),
            ("half 【1-so", "half 【1-so", []),
            ("not a citation 【note】", "not a citation 【note】", []),
            ("code `【1-source】` stays", "code `【1-source】` stays", []),
            ("```\n【1-source】\n```", "```\n【1-source】\n```", []),
        ]
    )
    func rewriteCitations(input: String, expected: String, numbers: [Int]) {
        let result = MarkdownPreprocessor.rewriteCitations(input)
        #expect(result.text == expected)
        #expect(result.citations == numbers)
    }

    @Test("a parsed citation is a link run whose number round-trips")
    func citationRuns() throws {
        let result = MarkdownParser.parse("PPI rose 0.4% 【1-source】.", source: 0)
        #expect(result.citations == [1])
        guard case .paragraph(let content) = result.blocks.first?.kind else {
            Issue.record("expected a paragraph")
            return
        }
        let link = try #require(MarkdownFixtures.runs(content).first { $0.link != nil })
        #expect(link.text == "1")
        #expect(link.link?.absoluteString == "exodus-cite://1")
        #expect(MarkdownPreprocessor.citationNumber(from: try #require(link.link)) == 1)
        #expect(MarkdownPreprocessor.citationNumber(from: try #require(URL(string: "https://1"))) == nil)
    }

    @Test("a half citation marker streaming in is dropped, then shown once whole")
    @MainActor
    func halfCitationWhileStreaming() {
        let model = MarkdownStreamModelProbe()
        #expect(model.paragraphs("as reported 【1-so", streaming: true) == ["as reported"])
        #expect(model.paragraphs("as reported 【1-source】.", streaming: true) == ["as reported 1."])
    }
}

@MainActor
private struct MarkdownStreamModelProbe {
    let model = MarkdownStreamModel()

    func paragraphs(_ text: String, streaming: Bool) -> [String] {
        model.update(text: text, isStreaming: streaming)
        return MarkdownFixtures.paragraphText(model.blocks)
    }
}
