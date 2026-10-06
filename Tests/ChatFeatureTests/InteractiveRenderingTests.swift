import Foundation
import MarkdownKit
import Models
import Testing

@testable import ChatFeature

private let confirmSource = #"{"title":"Send the report?","details":"To **Ann**."}"#
private let fenceText = "```exodus-confirm\n\(confirmSource)\n```"
private let reply = "Here is the plan.\n\n\(fenceText)"
private let noSend: @MainActor @Sendable (String) -> Void = { _ in }
private let answer =
    #"```exodus-answer\#n{"block":"confirm","decision":"approve","ref":"u1","title":"Send the report?"}\#n```\#n\#n"#
    + "**Send the report?** Approved"

/// How many of the texts' code blocks — at any depth, as MarkdownKit parses them — the host draws as its control.
@MainActor
private func drawnCount(_ texts: [String]) -> Int {
    guard let placed = InteractiveRendering.placed(in: texts) else { return 0 }
    let blocks = InteractiveRendering.fencedBlocks(
        fence: placed.fence, runId: "u1", answered: nil, canAnswer: true, sendAnswer: noSend)
    var count = 0
    func walk(_ list: [MarkdownBlock]) {
        for block in list {
            switch block.kind {
            case .codeBlock(let language, let code):
                if blocks?.view(language: language, code: code) != nil { count += 1 }
            case .blockquote(let inner):
                walk(inner)
            case .list(let list):
                for item in list.items { walk(item.blocks) }
            default:
                break
            }
        }
    }
    for (index, text) in texts.enumerated() {
        walk(MarkdownParser.parse(index == placed.index ? placed.text : text))
    }
    return count
}

@MainActor
@Suite("Interactive blocks in an answer")
struct InteractiveRenderingTests {
    @Test("answers are read off the transcript's user messages, by the run each names")
    func answers() {
        let segments: [Segment] = [
            .user(.userMessage(id: "u1", text: "Send it", timestampMs: 1)),
            .assistantTurn(AssistantTurn(runId: "u1", body: reply)),
            .user(.userMessage(id: "u2", text: answer, timestampMs: 2)),
        ]
        let answers = InteractiveRendering.answers(in: segments)
        #expect(Array(answers.keys) == ["u1"])
        #expect(answers["u1"]?.head.decision == .approve)
        #expect(answers["u1"]?.body == "**Send the report?** Approved")
    }

    @Test("only a later message answers a turn: one before it names no reply yet")
    func answerBeforeItsTurn() {
        let segments: [Segment] = [
            .user(.userMessage(id: "u0", text: answer, timestampMs: 0)),
            .user(.userMessage(id: "u1", text: "Send it", timestampMs: 1)),
            .assistantTurn(AssistantTurn(runId: "u1", body: reply)),
        ]
        #expect(InteractiveRendering.answers(in: segments).isEmpty)
    }

    @Test("a turn's Markdown is offered its own block only")
    func fencedBlocks() throws {
        #expect(
            InteractiveRendering.fencedBlocks(
                fence: nil, runId: "u1", answered: nil, canAnswer: true, sendAnswer: noSend) == nil)
        let fence = try #require(InteractiveFence.first(in: reply))
        let blocks = try #require(
            InteractiveRendering.fencedBlocks(
                fence: fence, runId: "u1", answered: nil, canAnswer: true, sendAnswer: noSend))
        let drawn = InteractiveRendering.drawnLanguage(.confirm)
        #expect(blocks.languages == [drawn])
        #expect(blocks.view(language: drawn, code: confirmSource) != nil)
        #expect(blocks.view(language: drawn, code: #"{"title":"Another"}"#) == nil)
        // The fence's own name is not enough: only the place the host marked is its block.
        #expect(blocks.view(language: "exodus-confirm", code: confirmSource) == nil)
        #expect(blocks.view(language: "exodus-ask", code: confirmSource) == nil)
    }

    @Test("a settled turn redraws when its block is answered, and on a turn starting only when it asks")
    func equality() {
        let asking = AssistantTurn(runId: "u1", body: reply)
        let plain = AssistantTurn(runId: "u9", body: "Just text.")
        func view(_ turn: AssistantTurn, answered: InteractiveAnswered? = nil, canAnswer: Bool) -> AssistantTurnView {
            AssistantTurnView(turn: turn, isStreaming: false, error: nil, answered: answered, canAnswer: canAnswer)
        }
        let head = InteractiveAnswer.Head(block: .confirm, decision: .approve, ref: "u1", title: "Send the report?")
        let answered = InteractiveAnswered(head: head, body: "**Send the report?** Approved")
        #expect(view(plain, canAnswer: true) == view(plain, canAnswer: false))
        #expect(view(asking, canAnswer: true) != view(asking, canAnswer: false))
        #expect(view(asking, canAnswer: true) != view(asking, answered: answered, canAnswer: true))
        #expect(
            view(asking, answered: answered, canAnswer: true) == view(asking, answered: answered, canAnswer: false))
    }

    @Test("an answer shown as a compared column is never answerable")
    func comparing() {
        var compared = AssistantTurn(runId: "u1", body: reply)
        compared.attempt = .comparing(position: 1)
        var chosen = AssistantTurn(runId: "u1", body: reply)
        chosen.attempt = .chosen(otherVersions: ["u0"], canSwap: true)
        let plain = AssistantTurn(runId: "u1", body: reply)
        #expect(!InteractiveRendering.isAnswerable(compared))
        #expect(!InteractiveRendering.canAnswer(compared, canAnswer: true))
        #expect(InteractiveRendering.canAnswer(chosen, canAnswer: true))
        #expect(InteractiveRendering.canAnswer(plain, canAnswer: true))
        #expect(!InteractiveRendering.canAnswer(plain, canAnswer: false))
    }

    @Test("only the reply's first top-level closed block is drawn, as the desktop finds it")
    func identification() {
        let tilde = "~~~exodus-confirm\n\(confirmSource)\n~~~"
        let quoted = "> ```exodus-confirm\n> \(confirmSource)\n> ```"
        let listed = "- Item\n\n  ```exodus-confirm\n  \(confirmSource)\n  ```"
        #expect(drawnCount([reply]) == 1)
        // A second identical block, after it, is code.
        #expect(drawnCount([reply + "\n\nAgain:\n\n" + fenceText]) == 1)
        // …and so is one in a later text block of the same turn.
        #expect(drawnCount(["Intro.", reply, fenceText]) == 1)
        #expect(InteractiveRendering.placed(in: ["Intro.", reply, fenceText])?.index == 1)
        // Look-alikes before it are code, and the real one is still drawn.
        #expect(drawnCount([tilde + "\n\n" + fenceText]) == 1)
        #expect(drawnCount([quoted + "\n\n" + fenceText]) == 1)
        #expect(drawnCount([listed + "\n\nThen:\n\n" + fenceText]) == 1)
        // Look-alikes alone are not blocks.
        #expect(drawnCount([tilde]) == 0)
        #expect(drawnCount([quoted]) == 0)
        #expect(drawnCount([listed]) == 0)
        #expect(drawnCount(["```exodus-confirm x\n\(confirmSource)\n```"]) == 0)
        #expect(drawnCount(["   ```exodus-confirm\n\(confirmSource)\n```"]) == 0)
        // A fence still open (a reply being written) is code.
        #expect(drawnCount(["Here.\n\n```exodus-confirm\n\(confirmSource)"]) == 0)
    }

    @Test("CRLF line ends are read as the desktop reads them")
    func crlf() throws {
        let text = "Here is the plan.\r\n\r\n```exodus-confirm\r\n\(confirmSource)\r\n```\r\n"
        #expect(drawnCount([text]) == 1)
        let fence = try #require(InteractiveFence.first(in: reply))
        #expect(fence.matches(language: "exodus-confirm", code: confirmSource + "\r\n"))
        #expect(fence.matches(code: confirmSource + "\n\n"))
    }

    @Test("a block's text is matched by its UTF-16 units, not by canonical equivalence")
    func utf16() throws {
        let composed = #"{"title":"Caf\#u{E9}?"}"#
        let decomposed = #"{"title":"Cafe\#u{301}?"}"#
        let fence = try #require(InteractiveFence.first(in: "```exodus-confirm\n\(composed)\n```"))
        #expect(fence.matches(code: composed))
        #expect(!fence.matches(code: decomposed))
    }
}
