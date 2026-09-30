import Foundation
import Testing

@testable import MarkdownKit

@Suite("MarkdownParser")
struct MarkdownParserTests {
    private func only(_ text: String) -> MarkdownBlock.Kind? {
        let blocks = MarkdownParser.parse(text)
        #expect(blocks.count == 1, "\(text.debugDescription) gave \(blocks.count) blocks")
        return blocks.first?.kind
    }

    private func paragraph(_ text: String) -> AttributedString? {
        guard case .paragraph(let content) = only(text) else { return nil }
        return content
    }

    @Test("paragraph and heading levels", arguments: 1...6)
    func headings(level: Int) {
        let blocks = MarkdownParser.parse("\(String(repeating: "#", count: level)) Title\n\nBody text")
        #expect(blocks.map(\.id) == [.init(source: 0, index: 0), .init(source: 0, index: 1)])
        guard case .heading(let parsedLevel, let content) = blocks[0].kind,
            case .paragraph(let body) = blocks[1].kind
        else {
            Issue.record("expected a heading then a paragraph")
            return
        }
        #expect(parsedLevel == level)
        #expect(MarkdownFixtures.plain(content) == "Title")
        #expect(MarkdownFixtures.plain(body) == "Body text")
    }

    @Test("setext headings")
    func setextHeading() {
        guard case .heading(let level, let content) = only("Heading two\n-----------") else {
            Issue.record("expected a heading")
            return
        }
        #expect(level == 2)
        #expect(MarkdownFixtures.plain(content) == "Heading two")
    }

    @Test(
        "inline styles become presentation intents",
        arguments: [
            ("**bold**", InlinePresentationIntent.stronglyEmphasized.rawValue),
            ("__bold__", InlinePresentationIntent.stronglyEmphasized.rawValue),
            ("*em*", InlinePresentationIntent.emphasized.rawValue),
            ("_em_", InlinePresentationIntent.emphasized.rawValue),
            ("~~gone~~", InlinePresentationIntent.strikethrough.rawValue),
            ("`code`", InlinePresentationIntent.code.rawValue),
            ("***both***", InlinePresentationIntent([.emphasized, .stronglyEmphasized]).rawValue),
        ]
    )
    func inlineIntents(markup: String, rawIntent: UInt) throws {
        let intent = InlinePresentationIntent(rawValue: rawIntent)
        let content = try #require(paragraph("a \(markup) b"))
        let styled = MarkdownFixtures.runs(content).filter { !$0.intent.isEmpty }
        #expect(styled.count == 1)
        #expect(styled.first?.intent == intent)
        #expect(!MarkdownFixtures.plain(content).contains("*"))
    }

    @Test("nested emphasis keeps both intents on the inner run")
    func nestedEmphasis() throws {
        let content = try #require(paragraph("**bold *both* bold**"))
        let runs = MarkdownFixtures.runs(content)
        #expect(runs.map(\.text) == ["bold ", "both", " bold"])
        #expect(runs[1].intent == [.stronglyEmphasized, .emphasized])
    }

    @Test("soft break is a space, hard break a newline")
    func breaks() throws {
        let soft = try #require(paragraph("one\ntwo"))
        #expect(MarkdownFixtures.plain(soft) == "one two")
        let hard = try #require(paragraph("one  \ntwo\\\nthree"))
        #expect(MarkdownFixtures.plain(hard) == "one\ntwo\nthree")
    }

    @Test("links, autolinks and bare URLs carry the link attribute")
    func links() throws {
        let content = try #require(
            paragraph("see [docs](https://a.com/x), <https://b.com> and https://c.com/p?q=1. Also www.d.com!")
        )
        let links = MarkdownFixtures.runs(content).compactMap { run in run.link.map { (run.text, $0.absoluteString) } }
        #expect(links.map(\.0) == ["docs", "https://b.com", "https://c.com/p?q=1", "www.d.com"])
        #expect(links.map(\.1) == ["https://a.com/x", "https://b.com", "https://c.com/p?q=1", "http://www.d.com"])
    }

    @Test("a URL inside code is not linked and trailing punctuation stays outside a bare link")
    func bareLinkEdges() throws {
        let content = try #require(paragraph("`https://x.com` and (https://y.com/a_(b)) done."))
        let links = MarkdownFixtures.runs(content).compactMap(\.link).map(\.absoluteString)
        #expect(links == ["https://y.com/a_(b)"])
    }

    @Test("money is not math: $200 - $300 stays plain text")
    func dollars() throws {
        let content = try #require(paragraph("The daily salary ranges from $200 - $300."))
        #expect(MarkdownFixtures.plain(content) == "The daily salary ranges from $200 - $300.")
        #expect(MarkdownFixtures.runs(content).count == 1)
    }

    // cmark still applies escapes, soft breaks and emphasis inside $$…$$; the math phase must cut $$ blocks out before cmark.
    @Test("$$…$$ reaches the AST as ordinary paragraph text (no math node, no special casing)")
    func displayMathText() {
        let blocks = MarkdownParser.parse("$$\na^2 + b^2\n$$")
        #expect(MarkdownFixtures.paragraphText(blocks) == ["$$ a^2 + b^2 $$"])
    }

    @Test("smart punctuation is off: quotes and dashes are what the model wrote")
    func noSmartPunctuation() throws {
        let content = try #require(paragraph("\"quoted\" -- 'single' ..."))
        #expect(MarkdownFixtures.plain(content) == "\"quoted\" -- 'single' ...")
    }

    @Test("unordered, ordered with a start index, and nested lists")
    func lists() {
        let text = """
            - one
            - two
              1. inner a
              2. inner b
            - three

            7. seven
            8. eight
            """
        let blocks = MarkdownParser.parse(text)
        #expect(blocks.count == 2)
        guard case .list(let bullets) = blocks[0].kind, case .list(let numbers) = blocks[1].kind else {
            Issue.record("expected two lists")
            return
        }
        #expect(!bullets.isOrdered)
        #expect(bullets.items.map(\.id) == [0, 1, 2])
        #expect(bullets.items.count == 3)
        #expect(numbers.isOrdered)
        #expect(numbers.startIndex == 7)
        #expect(numbers.items.count == 2)
        let second = bullets.items[1].blocks
        #expect(second.count == 2)
        guard case .list(let inner) = second[1].kind else {
            Issue.record("expected a nested list")
            return
        }
        #expect(inner.isOrdered)
        #expect(inner.startIndex == 1)
        #expect(inner.items.flatMap { MarkdownFixtures.paragraphText($0.blocks) } == ["inner a", "inner b"])
    }

    @Test("task list items carry their checkbox state")
    func taskList() {
        guard case .list(let list) = only("- [x] done\n- [ ] todo\n- plain") else {
            Issue.record("expected a list")
            return
        }
        #expect(list.items.map(\.checkbox) == [.checked, .unchecked, nil])
        #expect(list.items.flatMap { MarkdownFixtures.paragraphText($0.blocks) } == ["done", "todo", "plain"])
    }

    @Test("fenced code with and without a language, and indented code")
    func codeBlocks() {
        #expect(only("```swift\nlet x = 1\n```") == .codeBlock(language: "swift", code: "let x = 1"))
        #expect(only("```\nplain\n\n**not bold**\n```") == .codeBlock(language: nil, code: "plain\n\n**not bold**"))
        #expect(only("~~~py\nprint(1)\n~~~") == .codeBlock(language: "py", code: "print(1)"))
        #expect(only("    indented\n    code") == .codeBlock(language: nil, code: "indented\ncode"))
    }

    @Test("an unclosed fence while streaming is a code block to the end, healed or not")
    func unclosedFence() {
        let raw = "```swift\nlet x = **1"
        #expect(only(raw) == .codeBlock(language: "swift", code: "let x = **1"))
        #expect(only(MarkdownPreprocessor.healTail(raw)) == .codeBlock(language: "swift", code: "let x = **1"))
    }

    @Test("blockquotes nest")
    func blockquotes() {
        guard case .blockquote(let outer) = only("> outer\n>\n> > inner") else {
            Issue.record("expected a blockquote")
            return
        }
        #expect(outer.count == 2)
        #expect(MarkdownFixtures.paragraphText([outer[0]]) == ["outer"])
        guard case .blockquote(let inner) = outer[1].kind else {
            Issue.record("expected a nested blockquote")
            return
        }
        #expect(MarkdownFixtures.paragraphText(inner) == ["inner"])
    }

    @Test("GFM table with column alignments and inline cells")
    func table() throws {
        guard case .table(let table) = only("| L | C | R | N |\n|:--|:-:|--:|---|\n| 1 | **2** | 3 | 4 |\n| a | b | c | d |")
        else {
            Issue.record("expected a table")
            return
        }
        #expect(table.alignments == [.leading, .center, .trailing, nil])
        #expect(table.header.map(MarkdownFixtures.plain) == ["L", "C", "R", "N"])
        #expect(table.rows.map { $0.map(MarkdownFixtures.plain) } == [["1", "2", "3", "4"], ["a", "b", "c", "d"]])
        #expect(table.rows[0][1].runs.first?.inlinePresentationIntent == .stronglyEmphasized)
    }

    @Test("an unfinished table while streaming: a short row is padded, a partial delimiter is text")
    func unfinishedTable() {
        guard case .table(let table) = only("| a | b |\n|---|---|\n| 1 |") else {
            Issue.record("expected a table")
            return
        }
        #expect(table.rows.map { $0.map(MarkdownFixtures.plain) } == [["1", ""]])
        guard case .paragraph = only(MarkdownPreprocessor.healTail("| a | b |\n|--")) else {
            Issue.record("a header without a full delimiter row is still a paragraph")
            return
        }
    }

    @Test("thematic break, block image, inline image and html as text")
    func otherBlocks() {
        #expect(only("---") == .thematicBreak)
        #expect(
            only("![A cat](https://x.com/cat.png \"Cat\")")
                == .image(MarkdownImage(alt: "A cat", source: "https://x.com/cat.png", title: "Cat"))
        )
        #expect(only("<div>\nhi\n</div>") == .html("<div>\nhi\n</div>"))
        guard case .paragraph(let content) = only("an ![icon](https://x.com/i.png) inline <span>x</span>") else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(MarkdownFixtures.plain(content) == "an icon inline <span>x</span>")
        #expect(MarkdownFixtures.runs(content).first { $0.text == "icon" }?.link?.absoluteString == "https://x.com/i.png")
    }

    @Test("an HTML line break is a line break, in any spelling; in code it is the text it was")
    func htmlBreaks() throws {
        for tag in ["<br>", "<br/>", "<br />", "<BR>", "<Br  />"] {
            let content = try #require(paragraph("one\(tag)two"))
            #expect(MarkdownFixtures.plain(content) == "one\ntwo", "\(tag)")
        }
        let span = try #require(paragraph("a `<br>` b"))
        #expect(MarkdownFixtures.plain(span) == "a <br> b")
        #expect(only("```\n<br>\n```") == .codeBlock(language: nil, code: "<br>"))
        let other = try #require(paragraph("x <span>y</span><br>z"))
        #expect(MarkdownFixtures.plain(other) == "x <span>y</span>\nz")
    }

    @Test("a break at the start or the end of a paragraph leaves no empty line")
    func edgeBreaks() throws {
        let content = try #require(paragraph("<br>one<br>two<br/>"))
        #expect(MarkdownFixtures.plain(content) == "one\ntwo")
    }

    @Test("a paragraph or an HTML block that is nothing but line breaks is dropped")
    func onlyBreaks() {
        #expect(MarkdownParser.parse("<br>").isEmpty)
        #expect(MarkdownParser.parse("<BR/>").isEmpty)
        #expect(MarkdownParser.parse("<br> <br />").isEmpty)
        #expect(MarkdownParser.parse("<br>\n<br>").isEmpty)
        let around = MarkdownParser.parse("before\n\n<br>\n\nafter")
        #expect(around.map(\.id.index) == [0, 1])
        #expect(around.count == 2)
        // An HTML block that says something keeps it, as text, with its breaks as line breaks.
        #expect(only("<div>a<br>b</div>") == .html("<div>a\nb</div>"))
    }

    @Test("a half link shows as literal text before healing and as plain text after")
    func halfLink() throws {
        let raw = try #require(paragraph("see [text](https://exa"))
        #expect(raw.runs.allSatisfy { $0.link == nil })
        let healed = try #require(paragraph(MarkdownPreprocessor.healTail("see [text](https://exa")))
        #expect(MarkdownFixtures.plain(healed) == "see text")
    }

    @Test("** opened inside a list item heals into bold while streaming")
    func boldInListItem() {
        guard case .list(let list) = only(MarkdownPreprocessor.healTail("- first\n- **second is bo")) else {
            Issue.record("expected a list")
            return
        }
        guard case .paragraph(let content) = list.items.last?.blocks.first?.kind else {
            Issue.record("expected a paragraph item")
            return
        }
        #expect(MarkdownFixtures.plain(content) == "second is bo")
        #expect(content.runs.first?.inlinePresentationIntent == .stronglyEmphasized)
    }

    @Test("an empty or blank document has no blocks")
    func empty() {
        #expect(MarkdownParser.parse("").isEmpty)
        #expect(MarkdownParser.parse("\n\n  \n").isEmpty)
    }

    @Test("parse timings for 1 KB and 9 KB documents")
    func timings() {
        for size in [1_000, 9_000] {
            let text = MarkdownFixtures.longDocument(minimumLength: size)
            _ = MarkdownParser.parse(text)
            let clock = ContinuousClock()
            let runs = 20
            let elapsed = clock.measure {
                for _ in 0..<runs { _ = MarkdownParser.parse(text) }
            }
            let document = clock.measure {
                for _ in 0..<runs { _ = MarkdownPreprocessor.parseDocument(text) }
            }
            print("MarkdownKit timing: \(text.utf8.count) bytes, full pipeline \(elapsed / runs), swift-markdown only \(document / runs)")
        }
    }
}
