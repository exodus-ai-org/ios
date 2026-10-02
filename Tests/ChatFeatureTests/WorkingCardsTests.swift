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

/// Text, a terminal, text, then a read, an edit, a write, the weather and a picture, then the answer: every card the
/// preference can hide, and two it never does.
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

private func defaults(_ shown: [WorkingCard: Bool]) -> UserDefaults {
    let name = "WorkingCardsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    for (card, value) in shown { defaults.set(value, forKey: card.defaultsKey) }
    return defaults
}

@Suite("Working cards: the process cards the user can hide")
struct WorkingCardsTests {
    @Test("by default every card shows")
    func defaultsShowEverything() throws {
        let turn = try workingTurn()
        #expect(WorkingCard.hiddenTools(in: defaults([:])).isEmpty)
        #expect(TranscriptRules.blocks(turn, isStreaming: false, hiding: []) == turn.blocks)
        #expect(
            shape(turn.blocks) == [
                "T(Checking.)", "C(terminal)", "T(Now the files.)", "C(read_file)", "C(edit_file)", "C(write_file)",
                "C(weather)", "C(image_generation)", "T(Done.)",
            ])
    }

    @Test("a switch turned off hides its tools; one turned on, or never touched, does not")
    func storedSwitches() {
        #expect(WorkingCard.hiddenTools(in: defaults([.terminal: false])) == ["terminal"])
        #expect(WorkingCard.hiddenTools(in: defaults([.fileReads: false, .terminal: true])) == ["read_file"])
        #expect(WorkingCard.hiddenTools(in: defaults([.fileEdits: false])) == ["write_file", "edit_file"])
    }

    @Test(
        "each combination hides exactly its cards, and the text a hidden card stood between is one block",
        arguments: 0..<8)
    func everyCombination(mask: Int) throws {
        let turn = try workingTurn()
        let off = WorkingCard.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
        let hidden = WorkingCard.hiddenTools(in: defaults(Dictionary(uniqueKeysWithValues: off.map { ($0, false) })))
        let blocks = TranscriptRules.blocks(turn, isStreaming: false, hiding: hidden)

        let expectedCards = ["terminal", "read_file", "edit_file", "write_file", "weather", "image_generation"]
            .filter { !hidden.contains($0) }
        #expect(TranscriptRules.toolCards(turn, isStreaming: false, hiding: hidden).map(\.toolName) == expectedCards)
        #expect(shape(blocks).contains("C(weather)") && shape(blocks).contains("C(image_generation)"))
        // Two texts never stand next to each other: no empty place is left where a card was.
        let kinds = shape(blocks).map(\.first)
        #expect(!zip(kinds, kinds.dropFirst()).contains { $0 == "T" && $1 == "T" })
        if off.contains(.terminal) {
            #expect(shape(blocks).first == "T(Checking.\n\nNow the files.)")
        }
    }

    @Test("a hidden card's step stays in the thinking timeline")
    func timelineKeepsHiddenSteps() throws {
        let turn = try workingTurn()
        let everything = Set(WorkingCard.allCases.flatMap(\.toolNames))
        #expect(TranscriptRules.toolCards(turn, isStreaming: false, hiding: everything).map(\.toolName) == [
            "weather", "image_generation",
        ])
        let calls = turn.steps.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }
        let terminal = try #require(calls.first { $0.name == "terminal" })
        #expect(terminal.codeArgument == #"node -e "1""#)
        #expect(TranscriptRules.showsTimeline(turn, isStreaming: false))
        for (name, path) in [("read_file", "/w/README.md"), ("edit_file", "/w/a.swift"), ("write_file", "/w/plan.md")] {
            let step = try #require(calls.first { $0.name == name })
            #expect(ToolPresentation.callText(step).contains(path))
        }
    }

    @Test("a turn whose every card is hidden and that wrote no text draws nothing under its timeline")
    func onlyHiddenCards() throws {
        var cache = RunGrouper.Cache()
        let messages = [
            user,
            assistant("a1", call("k1", "terminal", #"{"command":"ls"}"#)),
            result("t1", "k1", "terminal", details: #"{"command":"ls","cwd":"/tmp","exitCode":0,"stdout":"a","stderr":""}"#),
        ]
        guard case .assistantTurn(let turn)? = RunGrouper.group(messages, cache: &cache).last else { throw TurnMissing() }
        #expect(TranscriptRules.blocks(turn, isStreaming: true, hiding: ["terminal"]).isEmpty)
        #expect(TranscriptRules.showsTimeline(turn, isStreaming: false))
    }
}
