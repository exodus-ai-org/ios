import Foundation
import Models
import Testing

@testable import ChatFeature

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private let user = decode(#"{"id":"u1","runId":"u1","role":"user","content":"q","timestamp":1}"#)

private func assistant(_ id: String, _ blocks: String, stopReason: String = "toolUse") -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"u1","role":"assistant","content":[\#(blocks)],"stopReason":"\#(stopReason)","timestamp":2}"#)
}

private func say(_ value: String) -> String { #"{"type":"text","text":"\#(value)"}"# }

private func call(_ id: String, _ name: String, _ arguments: String) -> String {
    #"{"type":"toolCall","id":"\#(id)","name":"\#(name)","arguments":\#(arguments)}"#
}

private func result(_ id: String, _ callId: String, _ name: String, details: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"u1","role":"toolResult","toolCallId":"\#(callId)","toolName":"\#(name)","content":[{"type":"text","text":"ok"}],"details":\#(details),"isError":false,"timestamp":3}"#
    )
}

/// Text, a terminal, text, then a read, an edit, a write, the weather and a picture, then the answer: every card that
/// folds into its step, and two that stay in the answer.
private func workingTurn() throws -> AssistantTurn {
    var cache = RunGrouper.Cache()
    let messages = [
        user,
        assistant("a1", say("Checking.") + "," + call("k1", "terminal", #"{"command":"node -e \"1\""}"#)),
        result("t1", "k1", "terminal", details: #"{"command":"node -e \"1\"","cwd":"/tmp","exitCode":0,"stdout":"1","stderr":""}"#),
        assistant(
            "a2",
            say("Now the files.") + "," + call("k2", "read_file", #"{"path":"/w/README.md"}"#) + ","
                + call("k3", "edit_file", #"{"path":"/w/a.swift","old_string":"a","new_string":"b"}"#) + ","
                + call("k4", "write_file", #"{"path":"/w/plan.md","content":"x"}"#) + ","
                + call("k5", "weather", #"{"location":"Kyoto"}"#) + ","
                + call("k6", "image_generation", #"{"prompt":"a cat"}"#)),
        result("t2", "k2", "read_file", details: #"{"path":"/w/README.md","size":1,"content":"x"}"#),
        result("t3", "k3", "edit_file", details: #"{"path":"/w/a.swift","replacements":1,"linesBefore":1,"linesAfter":1}"#),
        result("t4", "k4", "write_file", details: #"{"path":"/w/plan.md","bytes":1,"appended":false}"#),
        result("t5", "k5", "weather", details: #"{"location":"Kyoto","current":{"tempC":"22","weatherCode":"2"},"forecast":[]}"#),
        result("t6", "k6", "image_generation", details: #"{"images":[{"mediaId":"a.png","chatId":"c1","mimeType":"image/png"}]}"#),
        assistant("a3", say("Done."), stopReason: "stop"),
    ]
    guard case .assistantTurn(let turn)? = RunGrouper.group(messages, cache: &cache).last else { throw TurnMissing() }
    return turn
}

private struct TurnMissing: Error {}

private func shape(_ blocks: [AssistantTurn.Block]) -> [String] {
    blocks.map {
        switch $0 {
        case .text(let text): "T(\(text.text))"
        case .card(let card): "C(\(card.toolName))"
        }
    }
}

private func calls(_ turn: AssistantTurn) -> [AssistantTurn.ToolCallStep] {
    turn.steps.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }
}

@Suite("Folded cards: a command's and a file's card open from their timeline step")
struct FoldedCardsTests {
    @Test("the answer leaves out the terminal and file cards, keeps every other card, and joins the text they split")
    func answerLeavesThemOut() throws {
        let turn = try workingTurn()
        #expect(
            shape(turn.blocks) == [
                "T(Checking.)", "C(terminal)", "T(Now the files.)", "C(read_file)", "C(edit_file)", "C(write_file)",
                "C(weather)", "C(image_generation)", "T(Done.)",
            ])
        #expect(
            shape(TranscriptRules.blocks(turn, isStreaming: false)) == [
                "T(Checking.\n\nNow the files.)", "C(weather)", "C(image_generation)", "T(Done.)",
            ])
        #expect(TranscriptRules.toolCards(turn, isStreaming: true).map(\.toolName) == ["weather", "image_generation"])
    }

    @Test("a finished step of a folded tool carries its card; another tool's step carries none")
    func stepCarriesItsCard() throws {
        let turn = try workingTurn()
        let steps = calls(turn)
        let terminal = try #require(steps.first { $0.name == "terminal" })
        let card = try #require(TranscriptRules.foldedCard(for: terminal, in: turn))
        #expect(card.toolCallId == "k1")
        #expect(card.content.terminal?.command == #"node -e "1""#)
        #expect(card.content.terminal?.stdout == "1")
        for (name, id) in [("read_file", "k2"), ("edit_file", "k3"), ("write_file", "k4")] {
            let step = try #require(steps.first { $0.name == name })
            #expect(TranscriptRules.foldedCard(for: step, in: turn)?.toolCallId == id)
            #expect(TranscriptRules.foldedCard(for: step, in: turn).map(ToolCardRegistry.canDraw) == true)
        }
        let weather = try #require(steps.first { $0.name == "weather" })
        #expect(TranscriptRules.foldedCard(for: weather, in: turn) == nil)
    }

    @Test("a command still running has nothing to open, and a turn of only commands draws no answer")
    func runningCommand() throws {
        var cache = RunGrouper.Cache()
        let running = [user, assistant("a1", call("k1", "terminal", #"{"command":"ls"}"#))]
        guard case .assistantTurn(let turn)? = RunGrouper.group(running, cache: &cache).last else { throw TurnMissing() }
        let step = try #require(calls(turn).first)
        #expect(step.isPending)
        #expect(TranscriptRules.foldedCard(for: step, in: turn) == nil)

        let settled = running + [
            result("t1", "k1", "terminal", details: #"{"command":"ls","cwd":"/tmp","exitCode":0,"stdout":"a","stderr":""}"#)
        ]
        guard case .assistantTurn(let done)? = RunGrouper.group(settled, cache: &cache).last else { throw TurnMissing() }
        #expect(TranscriptRules.blocks(done, isStreaming: true).isEmpty)
        #expect(TranscriptRules.showsTimeline(done, isStreaming: false))
        let doneStep = try #require(calls(done).first)
        #expect(TranscriptRules.foldedCard(for: doneStep, in: done)?.content.terminal?.stdout == "a")
    }
}
