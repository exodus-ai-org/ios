import Foundation
import Testing

@testable import MarkdownKit

@Suite("MarkdownPreprocessor.splitBlocks")
struct MarkdownSplitTests {
    @Test("returns contiguous slices that join back to the source", arguments: MarkdownFixtures.samples.map(\.name))
    func joinsBackToSource(name: String) {
        let text = MarkdownFixtures.sample(name)
        #expect(MarkdownPreprocessor.splitBlocks(text).joined() == text)
    }

    @Test("an empty document has no blocks")
    func emptyDocument() {
        #expect(MarkdownPreprocessor.splitBlocks("").isEmpty)
    }

    @Test("keeps a fence, a loose list and a display-math block in one piece each")
    func keepsConstructsWhole() {
        let fence = MarkdownPreprocessor.splitBlocks(
            MarkdownFixtures.sample("a fenced code block with blank lines and markdown-looking content")
        )
        #expect(fence.count == 3)
        #expect(fence[1].contains("// # not a heading"))
        #expect(fence[1].contains("\"- not a list\""))

        let list = MarkdownPreprocessor.splitBlocks(
            MarkdownFixtures.sample("a loose list with nested items and a continuation paragraph")
        )
        #expect(list.count == 3)
        #expect(list[1].contains("1. First item"))
        #expect(list[1].contains("3. Third"))

        let math = MarkdownPreprocessor.splitBlocks(MarkdownFixtures.sample("display math containing blank lines"))
        #expect(math.contains { $0.contains("a^2 + b^2") && $0.contains("= c^2") })
    }

    @Test("keeps the indent that makes an indented code block one")
    func keepsIndent() {
        let blocks = MarkdownPreprocessor.splitBlocks(MarkdownFixtures.sample("an indented code block after a paragraph"))
        #expect(blocks[1].hasPrefix("    indented code"))
    }

    @Test("renders a document with definitions whole (they are looked up across blocks)")
    func definitionsKeepDocumentWhole() {
        let text = """
            See [the docs][d] and a note[^1].

            More text.

            [d]: https://example.com
            [^1]: The footnote.
            """
        #expect(MarkdownPreprocessor.splitBlocks(text) == [Substring(text)])
        let whole = MarkdownParser.parse(text)
        let link = whole.first.flatMap { block -> URL? in
            guard case .paragraph(let content) = block.kind else { return nil }
            return content.runs.compactMap(\.link).first
        }
        #expect(link == URL(string: "https://example.com"))
    }

    @Test(
        "parses the same block by block as whole, at every streamed prefix",
        arguments: MarkdownFixtures.samples.map(\.name)
    )
    func blockByBlockMatchesWhole(name: String) {
        for prefix in MarkdownFixtures.prefixes(of: MarkdownFixtures.sample(name)) {
            let split = MarkdownPreprocessor.splitBlocks(prefix).flatMap { MarkdownParser.parse(String($0)) }
            #expect(
                MarkdownFixtures.kinds(split) == MarkdownFixtures.kinds(MarkdownParser.parse(prefix)),
                "prefix \(prefix.debugDescription)"
            )
        }
    }

    @Test("splits incrementally exactly as it does from scratch", arguments: MarkdownFixtures.samples.map(\.name))
    func incrementalMatchesScratch(name: String) {
        let text = MarkdownFixtures.sample(name)
        var cache = MarkdownBlockCache()
        for prefix in MarkdownFixtures.prefixes(of: text) {
            #expect(
                MarkdownPreprocessor.splitBlocks(prefix, cache: &cache) == MarkdownPreprocessor.splitBlocks(prefix),
                "prefix \(prefix.debugDescription)"
            )
        }
        #expect(MarkdownPreprocessor.splitBlocks(text, cache: &cache) == MarkdownPreprocessor.splitBlocks(text))
    }

    @Test(
        "leaves every block but the last two untouched as text is appended",
        arguments: MarkdownFixtures.samples.map(\.name)
    )
    func settledBlocksStayPut(name: String) {
        var cache = MarkdownBlockCache()
        var previous: [Substring] = []
        for prefix in MarkdownFixtures.prefixes(of: MarkdownFixtures.sample(name)) {
            let blocks = MarkdownPreprocessor.splitBlocks(prefix, cache: &cache)
            let closed = previous.dropLast(2)
            #expect(Array(blocks.prefix(closed.count)) == Array(closed), "prefix \(prefix.debugDescription)")
            previous = blocks
        }
    }

    @Test("starts over when the text is replaced rather than appended to")
    func replacedTextStartsOver() {
        var cache = MarkdownBlockCache()
        _ = MarkdownPreprocessor.splitBlocks("# One\n\nfirst", cache: &cache)
        #expect(
            MarkdownPreprocessor.splitBlocks("Totally different\n\ntext", cache: &cache)
                == MarkdownPreprocessor.splitBlocks("Totally different\n\ntext")
        )
    }

    @Test("a streamed \"2\" folds back into the list above once its \".\" arrives")
    func listItemFoldsIntoList() {
        var cache = MarkdownBlockCache()
        #expect(MarkdownPreprocessor.splitBlocks("1. one\n\n2", cache: &cache).count == 2)
        #expect(MarkdownPreprocessor.splitBlocks("1. one\n\n2. two", cache: &cache) == ["1. one\n\n2. two"])
    }
}
