import Foundation
import Testing

@testable import MarkdownKit

@Suite("MarkdownPreprocessor.healTail")
struct MarkdownHealTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let input: String
        let expected: String
        var testDescription: String { input.debugDescription }
    }

    // The desktop's own healStreamingTail cases (remend + the partial-citation rule).
    static let desktopCases: [Case] = [
        Case(input: "This is **important and", expected: "This is **important and**"),
        Case(input: "and *maybe", expected: "and *maybe*"),
        Case(input: "~~old", expected: "~~old~~"),
        Case(input: "run `npm i", expected: "run `npm i`"),
        Case(input: "so $$E = mc", expected: "so $$E = mc$$"),
        Case(input: "costs $200 - $300 today", expected: "costs $200 - $300 today"),
        Case(input: "**done** and `done`", expected: "**done** and `done`"),
        Case(input: "as reported 【1-sou", expected: "as reported"),
        Case(input: "as reported 【1", expected: "as reported"),
        Case(input: "as reported 【1-source】.", expected: "as reported 【1-source】."),
    ]

    static let closingCases: [Case] = [
        Case(input: "_under", expected: "_under_"),
        Case(input: "__strong", expected: "__strong__"),
        Case(input: "***both", expected: "***both***"),
        Case(input: "**a *b", expected: "**a *b***"),
        Case(input: "a ~~b", expected: "a ~~b~~"),
        Case(input: "**bold\n", expected: "**bold**\n"),
        Case(input: "`code **x", expected: "`code **x`"),
        Case(input: "**x $$E", expected: "**x $$E$$**"),
        Case(input: "$$\na^2\n\nb", expected: "$$\na^2\n\nb\n$$"),
        Case(input: "under_score and _em", expected: "under_score and _em_"),
    ]

    static let containerCases: [Case] = [
        Case(input: "- **bold item", expected: "- **bold item**"),
        Case(input: "* item one\n* item **two", expected: "* item one\n* item **two**"),
        Case(input: "1. first\n2. sec *ond", expected: "1. first\n2. sec *ond*"),
        Case(input: "> quote **x", expected: "> quote **x**"),
        Case(input: "- [ ] task **x", expected: "- [ ] task **x**"),
        Case(input: "## Title *part", expected: "## Title *part*"),
        Case(input: "| a | b |\n|---|---|\n| 1 | **x", expected: "| a | b |\n|---|---|\n| 1 | **x**"),
        Case(input: "- *a*\n- **b", expected: "- *a*\n- **b**"),
    ]

    static let literalCases: [Case] = [
        Case(input: "2 * 3 * 4", expected: "2 * 3 * 4"),
        Case(input: "2 * 3", expected: "2 * 3"),
        Case(input: "snake_case_words here", expected: "snake_case_words here"),
        Case(input: "* item", expected: "* item"),
        Case(input: "- item\n* other", expected: "- item\n* other"),
        Case(input: "x **", expected: "x **"),
        Case(input: "**", expected: "**"),
        Case(input: "word*", expected: "word*"),
        Case(input: "f(x) = *y*", expected: "f(x) = *y*"),
        Case(input: "costs $200", expected: "costs $200"),
        Case(input: "19~32°C to 5~10°C", expected: "19~32°C to 5~10°C"),
        Case(input: "**a *", expected: "**a** *"),
        Case(input: "escaped \\*star", expected: "escaped \\*star"),
        Case(input: "**done**\n\nnext", expected: "**done**\n\nnext"),
        Case(input: "**open\n\nnew paragraph", expected: "**open\n\nnew paragraph"),
    ]

    static let linkCases: [Case] = [
        Case(input: "see [the docs](https://exa", expected: "see the docs"),
        Case(input: "see [the do", expected: "see the do"),
        Case(input: "[x](y) and [z](w", expected: "[x](y) and z"),
        Case(input: "![alt](http://x", expected: ""),
        Case(input: "look ![al", expected: "look"),
        Case(input: "text <https://exa", expected: "text"),
        Case(input: "a [**bold link](htt", expected: "a **bold link**"),
        Case(input: "done [x](https://x.com)", expected: "done [x](https://x.com)"),
        Case(input: "code `[x](` here", expected: "code `[x](` here"),
    ]

    static let fenceCases: [Case] = [
        Case(input: "```py\nlet x = **1\n", expected: "```py\nlet x = **1\n```"),
        Case(input: "```py\nlet x = **1", expected: "```py\nlet x = **1\n```"),
        Case(input: "```\nx\n``", expected: "```\nx\n```"),
        Case(input: "~~~\nx", expected: "~~~\nx\n~~~"),
        Case(input: "1. step\n\n   ```sh\n   echo *a", expected: "1. step\n\n   ```sh\n   echo *a\n   ```"),
        Case(input: "```\ncode **x\n```\nafter **y", expected: "```\ncode **x\n```\nafter **y**"),
        Case(input: "```\n【1-sou 2 * x\n```", expected: "```\n【1-sou 2 * x\n```"),
        Case(input: "```\ncode ", expected: "```\ncode \n```"),
    ]

    static let blockCases: [Case] = [
        Case(input: "Heading\n-", expected: "Heading"),
        Case(input: "Heading\n==", expected: "Heading"),
        Case(input: "Heading\n---", expected: "Heading\n---"),
        Case(input: "trailing space ", expected: "trailing space"),
        Case(input: "hard break  ", expected: "hard break  "),
    ]

    @Test("ported desktop cases", arguments: desktopCases)
    func desktop(_ testCase: Case) { check(testCase) }

    @Test("closes what is open at the end", arguments: closingCases)
    func closing(_ testCase: Case) { check(testCase) }

    @Test("heals inside list items, quotes, headings and table rows", arguments: containerCases)
    func containers(_ testCase: Case) { check(testCase) }

    @Test("leaves literal markers alone", arguments: literalCases)
    func literals(_ testCase: Case) { check(testCase) }

    @Test("neutralises half-typed links and images", arguments: linkCases)
    func links(_ testCase: Case) { check(testCase) }

    @Test("closes an open fence and never touches a closed one", arguments: fenceCases)
    func fences(_ testCase: Case) { check(testCase) }

    @Test("block-level partials", arguments: blockCases)
    func blocks(_ testCase: Case) { check(testCase) }

    @Test("healing is idempotent on its own output", arguments: desktopCases + closingCases + containerCases + linkCases)
    func idempotent(_ testCase: Case) {
        let once = MarkdownPreprocessor.healTail(testCase.input)
        #expect(MarkdownPreprocessor.healTail(once) == once)
    }

    @Test("a healed half link parses to plain text with no link run")
    func healedLinkParsesAsText() {
        let blocks = MarkdownParser.parse(MarkdownPreprocessor.healTail("see [the docs](https://exa"))
        guard case .paragraph(let content) = blocks.first?.kind else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(MarkdownFixtures.plain(content) == "see the docs")
        #expect(content.runs.allSatisfy { $0.link == nil })
    }

    @Test("healed emphasis parses to styled runs, not literal asterisks")
    func healedEmphasisParses() {
        let blocks = MarkdownParser.parse(MarkdownPreprocessor.healTail("- **bold item"))
        guard case .list(let list) = blocks.first?.kind, case .paragraph(let content) = list.items.first?.blocks.first?.kind
        else {
            Issue.record("expected a list with a paragraph")
            return
        }
        #expect(MarkdownFixtures.plain(content) == "bold item")
        #expect(content.runs.first?.inlinePresentationIntent == .stronglyEmphasized)
    }

    private func check(_ testCase: Case) {
        #expect(MarkdownPreprocessor.healTail(testCase.input) == testCase.expected)
    }
}
