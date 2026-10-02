import Foundation
import Models
import Testing

@testable import ChatFeature

private let run = "33333333-3333-4333-8333-333333333333"

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func turn(_ assistantContent: String) throws -> AssistantTurn {
    var cache = RunGrouper.Cache()
    let segments = RunGrouper.group(
        [
            decode(#"{"id":"\#(run)","runId":"\#(run)","role":"user","content":"q","timestamp":1}"#),
            decode(
                #"{"id":"a1","runId":"\#(run)","role":"assistant","content":\#(assistantContent),"stopReason":"stop","timestamp":2}"#
            ),
        ], cache: &cache)
    return try #require(segments.compactMap { if case .assistantTurn(let t) = $0 { t } else { nil } }.first)
}

private func thinkingTexts(_ turn: AssistantTurn) -> [String] {
    turn.steps.compactMap { if case .thinking(let step) = $0, !step.isNarration { step.text } else { nil } }
}

// A reply saved before the desktop split `<thinking>` spans out holds one in its text: the transcript shows it in
// the timeline, not the answer.
@Suite("Transcript: a stored <thinking> span")
struct ThinkingTagsTranscriptTests {
    @Test("goes into the timeline as thinking, out of the answer")
    func intoTimeline() throws {
        let turn = try turn(
            #"[{"type":"text","text":"<thinking>国庆假期，北京。用 map_itinerary 展示。</thinking>\n\n好的，行程如下。"}]"#)
        #expect(turn.body == "好的，行程如下。")
        #expect(thinkingTexts(turn) == ["国庆假期，北京。用 map_itinerary 展示。"])
    }

    @Test("a plain-string content splits too")
    func stringContent() throws {
        let turn = try turn(#""<think>p</think>\nAnswer.""#)
        #expect(turn.body == "Answer.")
        #expect(thinkingTexts(turn) == ["p"])
    }

    @Test("a span inside a code fence stays in the answer")
    func fenced() throws {
        let turn = try turn(#"[{"type":"text","text":"```xml\n<think>x</think>\n```"}]"#)
        #expect(turn.body == "```xml\n<think>x</think>\n```")
        #expect(thinkingTexts(turn).isEmpty)
    }
}
