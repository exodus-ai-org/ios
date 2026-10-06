import SwiftUI
import Testing

@testable import MarkdownKit

@MainActor
@Suite("MarkdownFencedBlocks: a host draws the fenced blocks it names")
struct MarkdownFencedBlocksTests {
    @Test("a reserved fence parses as a code block whose language is its whole name")
    func parses() {
        let blocks = MarkdownParser.parse("Before\n\n```exodus-ask\n{\"title\":\"T\"}\n```")
        guard case .codeBlock(let language, let code)? = blocks.last?.kind else {
            Issue.record("expected a code block")
            return
        }
        #expect(language == "exodus-ask")
        #expect(code == "{\"title\":\"T\"}")
    }

    @Test("only a named language reaches the host, and the host's nil draws the code")
    func asksOnlyForItsLanguages() {
        let fenced = MarkdownFencedBlocks(languages: ["exodus-ask"]) { _, code in
            code == "mine" ? AnyView(Text(verbatim: "drawn")) : nil
        }
        #expect(fenced.view(language: "exodus-ask", code: "mine") != nil)
        #expect(fenced.view(language: "exodus-ask", code: "another") == nil)
        #expect(fenced.view(language: "swift", code: "mine") == nil)
        #expect(fenced.view(language: nil, code: "mine") == nil)
    }
}
