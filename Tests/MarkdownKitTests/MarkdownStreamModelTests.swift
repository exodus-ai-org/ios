import Foundation
import Testing

@testable import MarkdownKit

@MainActor
@Suite("MarkdownStreamModel")
struct MarkdownStreamModelTests {
    @Test("history (never streamed) is parsed whole, once")
    func historyParsedWhole() {
        let text = MarkdownFixtures.sample("paragraphs and headings")
        let model = MarkdownStreamModel()
        model.update(text: text, isStreaming: false)
        #expect(model.lastUpdateParseCount == 1)
        #expect(model.blocks == MarkdownParser.parse(text))
        model.update(text: text, isStreaming: false)
        #expect(model.lastUpdateParseCount == 0)
    }

    @Test("identical text twice parses nothing the second time")
    func identicalTextIsFree() {
        let model = MarkdownStreamModel()
        model.update(text: "# Hi\n\nfirst **para", isStreaming: true)
        #expect(model.lastUpdateParseCount == 2)
        let blocks = model.blocks
        model.update(text: "# Hi\n\nfirst **para", isStreaming: true)
        #expect(model.lastUpdateParseCount == 0)
        #expect(model.blocks == blocks)
    }

    @Test("a 5 000-character document fed as 60 growing snapshots re-parses only the tail")
    func reparsesOnlyTheTail() {
        let text = MarkdownFixtures.longDocument(minimumLength: 5_000)
        let chars = Array(text)
        let model = MarkdownStreamModel()
        var previousPieces = 0
        var totalParses = 0
        for step in 1...60 {
            let prefix = String(chars[..<(chars.count * step / 60)])
            model.update(text: prefix, isStreaming: true)
            let pieces = MarkdownPreprocessor.splitBlocks(prefix).count
            if step > 1 {
                #expect(
                    model.lastUpdateParseCount <= max(pieces - previousPieces, 0) + 2,
                    "step \(step): \(model.lastUpdateParseCount) parses for \(pieces - previousPieces) new blocks"
                )
            }
            totalParses += model.lastUpdateParseCount
            previousPieces = pieces
        }
        #expect(totalParses < previousPieces + 2 * 60)
        model.update(text: text, isStreaming: false)
        #expect(model.lastUpdateParseCount <= 1)
        #expect(MarkdownFixtures.kinds(model.blocks) == MarkdownFixtures.kinds(MarkdownParser.parse(text)))
    }

    @Test("settled blocks keep their identity and value while the tail grows")
    func settledBlocksAreReused() {
        let model = MarkdownStreamModel()
        model.update(text: "# Title\n\nFirst paragraph.\n\nSecond **grow", isStreaming: true)
        let first = Array(model.blocks.prefix(2))
        model.update(text: "# Title\n\nFirst paragraph.\n\nSecond **growing**", isStreaming: true)
        #expect(model.lastUpdateParseCount == 1)
        #expect(Array(model.blocks.prefix(2)) == first)
        #expect(model.blocks.map(\.id) == [.init(source: 0, index: 0), .init(source: 1, index: 0), .init(source: 2, index: 0)])
    }

    @Test("only the last block is healed while streaming, and not once finished")
    func healsOnlyTheLastBlock() {
        let model = MarkdownStreamModel()
        model.update(text: "Open **bold\n\nNow *em", isStreaming: true)
        #expect(MarkdownFixtures.paragraphText(model.blocks) == ["Open **bold", "Now em"])
        model.update(text: "Open **bold\n\nNow *em", isStreaming: false)
        #expect(MarkdownFixtures.paragraphText(model.blocks) == ["Open **bold", "Now *em"])
        #expect(model.lastUpdateParseCount == 1)
    }

    @Test("an unclosed fence while streaming renders as code, markers inside untouched")
    func unclosedFenceWhileStreaming() {
        let model = MarkdownStreamModel()
        model.update(text: "Intro\n\n```js\nconst a = **b", isStreaming: true)
        #expect(model.blocks.last?.kind == .codeBlock(language: "js", code: "const a = **b"))
    }

    @Test("text that shrinks (a regenerate) resets to a fresh parse")
    func shrinkingTextResets() {
        let model = MarkdownStreamModel()
        model.update(text: "# Old answer\n\nwith text\n\nand more", isStreaming: true)
        model.update(text: "# Ne", isStreaming: true)
        #expect(MarkdownFixtures.kinds(model.blocks) == MarkdownFixtures.kinds(MarkdownParser.parse("# Ne")))
        model.update(text: "# New answer\n\nfresh", isStreaming: true)
        #expect(
            MarkdownFixtures.kinds(model.blocks)
                == MarkdownFixtures.kinds(MarkdownParser.parse("# New answer\n\nfresh"))
        )
        model.update(text: "", isStreaming: true)
        #expect(model.blocks.isEmpty)
    }

    @Test("citations are collected across blocks in order")
    func citations() {
        let model = MarkdownStreamModel()
        model.update(text: "A 【2-source】.\n\nB 【1,3-source】 and 【4-so", isStreaming: true)
        #expect(model.citations == [2, 1, 3])
    }

    @Test("streaming a sample character by character matches the finished parse", arguments: MarkdownFixtures.samples.map(\.name))
    func streamedSampleEndsLikeWhole(name: String) {
        let text = MarkdownFixtures.sample(name)
        let model = MarkdownStreamModel()
        for prefix in MarkdownFixtures.prefixes(of: text) {
            model.update(text: prefix, isStreaming: true)
        }
        model.update(text: text, isStreaming: false)
        #expect(MarkdownFixtures.kinds(model.blocks) == MarkdownFixtures.kinds(MarkdownParser.parse(text)))
    }
}
