import Foundation
import Markdown
import Synchronization
import Testing

@testable import MarkdownKit

@MainActor
@Suite("Markdown render diagnostics")
struct MarkdownDiagnosticsTests {
    @Test("markup with no view of its own is collected by type, and still shown as text")
    func unhandledMarkupCollected() {
        let document = Document(BlockDirective(name: "note", children: [Paragraph(Text("hidden words"))]))
        var unhandled: [String] = []
        let blocks = MarkdownParser.blocks(document.children, source: 0, unhandled: &unhandled)
        #expect(unhandled == ["BlockDirective"])
        #expect(blocks.count == 1)
    }

    @Test("ordinary markdown reports nothing")
    func ordinaryMarkdownIsQuiet() {
        let result = MarkdownParser.parse("# Title\n\n- a\n- b\n\n> quote\n\n| a | b |\n|---|---|\n| 1 | 2 |\n", source: 0)
        #expect(result.unhandledKinds.isEmpty)
    }

    @Test("the model reports each fallback kind once, with no text")
    func modelReportsOncePerKind() {
        let calls = Mutex<[(String, String, [String: String])]>([])
        let model = MarkdownStreamModel()
        model.diagnostics = RenderDiagnostics { scope, message, attributes in
            calls.withLock { $0.append((scope, message, attributes)) }
        }
        model.noteUnhandled(["BlockDirective"])
        model.noteUnhandled(["BlockDirective", "CustomBlock"])
        model.noteUnhandled(["BlockDirective"])
        let recorded = calls.withLock { $0 }
        #expect(recorded.map(\.2) == [["markup": "BlockDirective"], ["markup": "CustomBlock"]])
        #expect(recorded.allSatisfy { $0.0 == "markdown" })
    }
}
