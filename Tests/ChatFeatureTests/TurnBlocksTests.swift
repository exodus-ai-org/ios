import Foundation
import Models
import Testing

@testable import ChatFeature

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private let user = decode(#"{"id":"u1","runId":"u1","role":"user","content":"q","timestamp":1}"#)

private func assistant(_ id: String, _ blocks: String, stopReason: String = "stop") -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"u1","role":"assistant","content":[\#(blocks)],"stopReason":"\#(stopReason)","timestamp":2}"#)
}

private func say(_ value: String) -> String { #"{"type":"text","text":"\#(value)"}"# }

private func call(_ id: String, _ name: String, _ arguments: String = "{}") -> String {
    #"{"type":"toolCall","id":"\#(id)","name":"\#(name)","arguments":\#(arguments)}"#
}

private func result(_ id: String, _ callId: String, _ name: String, details: String, isError: Bool = false) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"u1","role":"toolResult","toolCallId":"\#(callId)","toolName":"\#(name)","content":[{"type":"text","text":"ok"}],"details":\#(details),"isError":\#(isError),"timestamp":3}"#
    )
}

private let terminalDetails = #"{"command":"ls","cwd":"/tmp","exitCode":0,"stdout":"a","stderr":""}"#
private let weatherDetails = #"{"location":"Shanghai","current":{"tempC":"22","weatherCode":"2"},"forecast":[]}"#
private let imageDetails = #"{"images":[{"mediaId":"a.png","chatId":"c1","mimeType":"image/png"}]}"#

private func turn(_ messages: [ChatMessage]) throws -> AssistantTurn {
    var cache = RunGrouper.Cache()
    let segments = RunGrouper.group([user] + messages, cache: &cache)
    guard case .assistantTurn(let turn)? = segments.last else { throw TurnMissing() }
    return turn
}

private struct TurnMissing: Error {}

/// A turn's blocks as one line: `T(text)` and `C(render key)`.
private func shape(_ blocks: [AssistantTurn.Block]) -> [String] {
    blocks.map {
        switch $0 {
        case .text(let text): "T(\(text.text))"
        case .card(let card): "C(\(card.renderKey))"
        }
    }
}

@Suite("A turn's blocks: the answer in the order the model produced it")
struct TurnBlocksTests {
    @Test("text, a card, text: the card stands where its call was made")
    func textCardText() throws {
        let built = try turn([
            assistant("a1", say("Let me look.") + "," + call("k1", "terminal", #"{"command":"ls"}"#), stopReason: "toolUse"),
            result("t1", "k1", "terminal", details: terminalDetails),
            assistant("a2", say("One file.")),
        ])
        #expect(shape(built.blocks) == ["T(Let me look.)", "C(call:k1)", "T(One file.)"])
        #expect(built.blocks.map(\.id) == ["text:0", "call:k1", "text:1"])
    }

    @Test("text with no card between stays one block: a tool that draws no card does not split the answer")
    func noCardNoSplit() throws {
        let built = try turn([
            assistant("a1", say("Searching.") + "," + call("k1", "grep"), stopReason: "toolUse"),
            result("t1", "k1", "grep", details: "null"),
            assistant("a2", say("Found it.")),
        ])
        #expect(shape(built.blocks) == ["T(Searching.\n\nFound it.)"])
        #expect(built.toolCards.isEmpty)
    }

    @Test("a card takes the place of its call, not of its result: results that land out of order do not reorder it")
    func callOrder() throws {
        let built = try turn([
            assistant(
                "a1",
                say("Both.") + "," + call("k1", "weather", #"{"location":"Shanghai"}"#) + ","
                    + call("k2", "terminal", #"{"command":"ls"}"#), stopReason: "toolUse"),
            result("t2", "k2", "terminal", details: terminalDetails),
            result("t1", "k1", "weather", details: weatherDetails),
            assistant("a2", say("Done.")),
        ])
        #expect(shape(built.blocks) == ["T(Both.)", "C(call:k1)", "C(call:k2)", "T(Done.)"])
        #expect(built.toolCards.map(\.toolName) == ["weather", "terminal"])
    }

    @Test("a running card becomes its result in place: the same key, the same position")
    func pendingInPlace() throws {
        let first = assistant(
            "a1", say("Drawing.") + "," + call("k1", "image_generation", #"{"prompt":"a cat"}"#), stopReason: "toolUse")
        let running = try turn([first])
        #expect(shape(running.blocks) == ["T(Drawing.)", "C(call:k1)"])
        #expect(running.toolCards.first?.isPending == true)
        let settled = try turn([first, result("t1", "k1", "image_generation", details: imageDetails), assistant("a2", say("Here."))])
        #expect(shape(settled.blocks) == ["T(Drawing.)", "C(call:k1)", "T(Here.)"])
        #expect(settled.toolCards.first?.isPending == false)
    }

    @Test("a result whose call is not among the rows stands where it arrived")
    func orphanResult() throws {
        let built = try turn([
            assistant("a1", say("Before.")),
            result("t1", "k9", "terminal", details: terminalDetails),
            assistant("a2", say("After.")),
        ])
        #expect(shape(built.blocks) == ["T(Before.)", "C(call:k9)", "T(After.)"])
    }

    @Test("body is every text block joined, and the cards are the blocks' cards: the two cannot disagree")
    func bodyAndCards() throws {
        let built = try turn([
            assistant("a1", say("Let me look.") + "," + call("k1", "terminal", #"{"command":"ls"}"#), stopReason: "toolUse"),
            result("t1", "k1", "terminal", details: terminalDetails),
            assistant("a2", say("One file.")),
        ])
        #expect(built.body == "Let me look.\n\nOne file.")
        let texts = built.blocks.compactMap { if case .text(let text) = $0 { text.text } else { nil } }
        #expect(built.body == texts.joined(separator: "\n\n"))
        let cards = built.blocks.compactMap { if case .card(let card) = $0 { card } else { nil } }
        #expect(built.toolCards == cards)
    }

    @Test("a turn built by hand from a body and cards lays the cards out first, then the text")
    func handBuilt() {
        let card = ToolCard(id: "t", toolCallId: "k", toolName: "terminal", kind: .terminal, payload: .object([:]))
        let built = AssistantTurn(runId: "r", body: "Answer", toolCards: [card])
        #expect(shape(built.blocks) == ["C(call:k)", "T(Answer)"])
        #expect(built.body == "Answer")
        #expect(built.toolCards == [card])
        #expect(AssistantTurn(runId: "r", body: "").blocks.isEmpty)
    }
}

@Suite("Transcript rules: what a turn draws, in order")
struct TranscriptBlocksTests {
    private let first = assistant(
        "a1", say("Drawing.") + "," + call("k1", "image_generation", #"{"prompt":"a cat"}"#), stopReason: "toolUse")

    @Test("a stopped run drops the image that never came, and the text around it is one block again")
    func stoppedImage() throws {
        let stopped = try turn([first, assistant("a2", say("Stopped."), stopReason: "aborted")])
        #expect(shape(TranscriptRules.blocks(stopped, isStreaming: true)) == ["T(Drawing.)", "C(call:k1)", "T(Stopped.)"])
        #expect(shape(TranscriptRules.blocks(stopped, isStreaming: false)) == ["T(Drawing.\n\nStopped.)"])
        #expect(TranscriptRules.toolCards(stopped, isStreaming: false).isEmpty)
    }

    @Test("only the last block streams, and only when it is text")
    func streamingBlock() throws {
        let answering = try turn([
            assistant("a1", say("Let me look.") + "," + call("k1", "terminal", #"{"command":"ls"}"#), stopReason: "toolUse"),
            result("t1", "k1", "terminal", details: terminalDetails),
            assistant("a2", say("One fi")),
        ])
        #expect(TranscriptRules.streamingBlockId(answering.blocks, isStreaming: true) == "text:1")
        #expect(TranscriptRules.streamingBlockId(answering.blocks, isStreaming: false) == nil)
        let drawing = try turn([first])
        #expect(TranscriptRules.streamingBlockId(drawing.blocks, isStreaming: true) == nil)
    }
}
