import Foundation
import Testing

@testable import MarkdownKit

@Suite("Review fix round 1")
struct MarkdownReviewFixTests {
    private func onlyParagraph(_ text: String) -> AttributedString? {
        let blocks = MarkdownParser.parse(text)
        guard blocks.count == 1, case .paragraph(let content) = blocks[0].kind else {
            Issue.record("\(text.debugDescription) did not parse to one paragraph: \(blocks.map(\.kind))")
            return nil
        }
        return content
    }

    private func codeBlock(in blocks: [MarkdownBlock]) -> MarkdownBlock.Kind? {
        for block in blocks {
            switch block.kind {
            case .codeBlock:
                return block.kind
            case .list(let list):
                for item in list.items { if let found = codeBlock(in: item.blocks) { return found } }
            case .blockquote(let inner):
                if let found = codeBlock(in: inner) { return found }
            default:
                continue
            }
        }
        return nil
    }

    // 1. A "!" before a citation marker must not turn the link into an image.
    @Test(
        "a ! before a citation stays text and the citation stays a link",
        arguments: [
            ("Huge!【1-source】 yes", "Huge!1 yes"),
            ("!【1-source】", "!1"),
            ("!!【1-source】", "!!1"),
            ("\\!【1-source】", "!1"),
            ("【1-source】 opens the line", "1 opens the line"),
            ("Wow!【1,2-source】", "Wow!12"),
        ]
    )
    func bangBeforeCitation(input: String, plain: String) throws {
        let content = try #require(onlyParagraph(input))
        #expect(MarkdownFixtures.plain(content) == plain)
        let links = MarkdownFixtures.runs(content).compactMap(\.link).map(\.absoluteString)
        #expect(!links.isEmpty)
        #expect(links.allSatisfy { $0.hasPrefix("exodus-cite://") })
    }

    @Test(
        "rewriteCitations escapes an unescaped ! before the link, and only that",
        arguments: [
            ("Huge!【1-source】", "Huge\\![1](exodus-cite://1)"),
            ("!!【1-source】", "!\\![1](exodus-cite://1)"),
            ("\\!【1-source】", "\\![1](exodus-cite://1)"),
            ("\\\\!【1-source】", "\\\\\\![1](exodus-cite://1)"),
            ("【1-source】", "[1](exodus-cite://1)"),
        ]
    )
    func bangEscape(input: String, expected: String) {
        #expect(MarkdownPreprocessor.rewriteCitations(input).text == expected)
    }

    // 2. One unmatched backtick must not shift inline-code pairing into the next block.
    static let driftInput = "# Use ` here\nThen `a~b` and ~~old~~"

    @Test("an unmatched backtick in a heading leaves the next paragraph's code and strike intact")
    func codeMaskDriftFinished() throws {
        let blocks = MarkdownParser.parse(Self.driftInput)
        #expect(blocks.count == 2)
        guard blocks.count == 2, case .paragraph(let content) = blocks[1].kind else {
            Issue.record("expected a heading and a paragraph")
            return
        }
        let runs = MarkdownFixtures.runs(content)
        #expect(runs.contains { $0.text == "a~b" && $0.intent.contains(.code) })
        #expect(!MarkdownFixtures.plain(content).contains("\\"))
        #expect(runs.contains { $0.text == "old" && $0.intent.contains(.strikethrough) })
    }

    @Test("while streaming, the healer does not take its scope from the heading line")
    func codeMaskDriftStreaming() {
        #expect(MarkdownPreprocessor.healTail(Self.driftInput) == Self.driftInput)
        #expect(MarkdownPreprocessor.healTail("# Title with ` tick\nbody **bold") == "# Title with ` tick\nbody **bold**")
    }

    @Test("a citation marker inside a real code span stays literal after an unmatched backtick")
    func citationInCodeAfterDrift() throws {
        let result = MarkdownParser.parse("# a ` b\nx `c【1-source】` y 【2-source】", source: 0)
        #expect(result.citations == [2])
        guard result.blocks.count == 2, case .paragraph(let content) = result.blocks[1].kind else {
            Issue.record("expected a heading and a paragraph")
            return
        }
        #expect(MarkdownFixtures.runs(content).contains { $0.text == "c【1-source】" && $0.intent.contains(.code) })
    }

    @Test("an unmatched backtick in a list item does not pair with one in the next item")
    func listItemsRestartPairing() throws {
        let text = "- one ` tick\n- two `a~b` and ~x~ ~~y~~"
        guard case .list(let list) = MarkdownParser.parse(text).first?.kind,
            case .paragraph(let content) = list.items.last?.blocks.first?.kind
        else {
            Issue.record("expected a list")
            return
        }
        #expect(MarkdownFixtures.plain(content) == "two a~b and ~x~ y")
        #expect(MarkdownFixtures.runs(content).contains { $0.text == "a~b" && $0.intent.contains(.code) })
    }

    // 3. A fence opened on a list-marker line is a fence, not an inline code run.
    @Test(
        "a fence opened after a list marker renders its code unchanged while streaming",
        arguments: [
            ("- ```python\n  print(1)", "- ```python\n  print(1)\n  ```", "python"),
            ("1. ```js\n   let a = 1", "1. ```js\n   let a = 1\n   ```", "js"),
            ("- outer\n  - ```sh\n    echo hi", "- outer\n  - ```sh\n    echo hi\n    ```", "sh"),
            ("- > ```rb\n  > puts 1", "- > ```rb\n  > puts 1\n  > ```", "rb"),
        ]
    )
    func fenceAfterListMarker(input: String, healed: String, language: String) {
        #expect(MarkdownPreprocessor.healTail(input) == healed)
        let code = codeBlock(in: MarkdownParser.parse(MarkdownPreprocessor.healTail(input)))
        guard case .codeBlock(let parsedLanguage, let text) = code else {
            Issue.record("no code block in \(input.debugDescription)")
            return
        }
        #expect(parsedLanguage == language)
        #expect(!text.contains("`"))
    }

    @Test("a closed list-item fence is left alone and stays code")
    func closedListFence() {
        let text = "- ```python\n  print(1)\n  ```\n- next *item"
        #expect(MarkdownPreprocessor.healTail(text) == "- ```python\n  print(1)\n  ```\n- next *item*")
        #expect(codeBlock(in: MarkdownParser.parse(text)) == .codeBlock(language: "python", code: "print(1)"))
    }

    @Test("an open inline run of three or more backticks is never closed by appending")
    func longBacktickRunNotClosed() {
        #expect(MarkdownPreprocessor.healTail("text ```inline") == "text ```inline")
        #expect(MarkdownPreprocessor.healTail("**a ```b") == "**a ```b**")
        #expect(MarkdownPreprocessor.healTail("run ``npm i") == "run ``npm i``")
    }
}

@Suite("Review fix round 2: a delimiter row still being typed")
struct MarkdownDelimiterRowTests {
    static let header = "| Step | Time |"

    @Test(
        "a half-typed delimiter row under a header is dropped while streaming",
        arguments: ["|---|-", "| --", "|:--|", "|", "|---|---", "  |:-", "| - | "]
    )
    func dropsHalfDelimiter(row: String) {
        let text = "\(Self.header)\n\(row)"
        #expect(MarkdownPreprocessor.healTail(text) == Self.header)
        #expect(MarkdownFixtures.paragraphText(MarkdownParser.parse(MarkdownPreprocessor.healTail(text))) == [Self.header])
    }

    @Test(
        "a complete delimiter row is left alone and the table snaps in",
        arguments: ["| Step | Time |\n|---|---|", "| Step | Time |\n|:--|--:|", "Step | Time\n--- | ---", "| a |\n|:-:|"]
    )
    func keepsCompleteDelimiter(text: String) {
        #expect(MarkdownPreprocessor.healTail(text) == text)
        guard case .table = MarkdownParser.parse(MarkdownPreprocessor.healTail(text)).first?.kind else {
            Issue.record("expected a table for \(text.debugDescription)")
            return
        }
    }

    @Test("a row of pipes after a line with no pipe is not a delimiter row")
    func pipesAfterPlainLine() {
        #expect(MarkdownPreprocessor.healTail("Some text\n||") == "Some text\n||")
        #expect(MarkdownPreprocessor.healTail("Some text\n| --") == "Some text\n| --")
    }

    @Test("a trailing newline after a complete table is untouched")
    func trailingNewline() {
        #expect(MarkdownPreprocessor.healTail("| a | b |\n|---|---|\n") == "| a | b |\n|---|---|\n")
    }

    @Test("finished (non-streaming) text keeps a half delimiter row as written")
    @MainActor
    func finishedTextUntouched() {
        let text = "\(Self.header)\n| --"
        let model = MarkdownStreamModel()
        model.update(text: text, isStreaming: false)
        #expect(MarkdownFixtures.paragraphText(model.blocks) == ["| Step | Time | | --"])
        let streaming = MarkdownStreamModel()
        streaming.update(text: text, isStreaming: true)
        #expect(MarkdownFixtures.paragraphText(streaming.blocks) == [Self.header])
    }
}
