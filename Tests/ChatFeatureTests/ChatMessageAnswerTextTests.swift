import Foundation
import Models
import Testing

@testable import ChatFeature

@Suite("ChatMessage.answerText")
struct ChatMessageAnswerTextTests {
    private func message(_ json: String) throws -> ChatMessage {
        try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    }

    @Test("a string content is returned as is")
    func stringContent() throws {
        let message = try message(#"{"id":"u1","role":"user","content":"hello **world**"}"#)
        #expect(message.answerText == "hello **world**")
    }

    @Test("with text, thinking and toolCall blocks, only the text block is returned")
    func onlyTheTextBlockOfAMixedMessage() throws {
        let message = try message(
            #"""
            {"id":"a1","role":"assistant","content":[
              {"type":"thinking","thinking":"plan the answer"},
              {"type":"text","text":"The answer."},
              {"type":"toolCall","id":"call_1","name":"web_search","arguments":{"q":"x"}}
            ]}
            """#)
        #expect(message.answerText == "The answer.")
        // The fixture is a real leak: `displayText` would put the chain-of-thought in the bubble.
        #expect(message.displayText.contains("plan the answer"))
    }

    @Test("a message with only thinking (or only tool calls) has no answer text")
    func thinkingOnlyIsEmpty() throws {
        let thinkingOnly = try message(
            #"{"id":"a1","role":"assistant","content":[{"type":"thinking","thinking":"hmm"}]}"#)
        #expect(thinkingOnly.answerText == "")

        let toolCallsOnly = try message(
            #"{"id":"a2","role":"assistant","content":[{"type":"toolCall","id":"c","name":"n","arguments":{}}]}"#)
        #expect(toolCallsOnly.answerText == "")
    }

    @Test("two text blocks are joined with a newline, exactly like displayText joins them")
    func textBlocksAreJoinedLikeDisplayText() throws {
        let message = try message(
            #"{"id":"a1","role":"assistant","content":[{"type":"text","text":"one"},{"type":"text","text":"two"}]}"#)
        #expect(message.answerText == "one\ntwo")
        #expect(message.answerText == message.displayText)
    }

    @Test("a thinking block between two text blocks is dropped without leaving a gap")
    func thinkingBetweenTextBlocksLeavesNoGap() throws {
        let message = try message(
            #"""
            {"id":"a1","role":"assistant","content":[
              {"type":"text","text":"one"},
              {"type":"thinking","thinking":"hmm"},
              {"type":"text","text":"two"}
            ]}
            """#)
        #expect(message.answerText == "one\ntwo")
    }

    @Test("answerText equals displayText for a plain text message, string or block form")
    func equalsDisplayTextForPlainText() throws {
        let asString = try message(#"{"id":"a1","role":"assistant","content":"plain"}"#)
        #expect(asString.answerText == asString.displayText)
        #expect(asString.answerText == "plain")

        let asBlocks = try message(
            #"{"id":"a2","role":"assistant","content":[{"type":"text","text":"plain"}]}"#)
        #expect(asBlocks.answerText == asBlocks.displayText)
        #expect(asBlocks.answerText == "plain")
    }

    @Test("unknown block types, blocks without a type, and content that is not a string or array are ignored")
    func unknownShapesAreIgnored() throws {
        let unknownBlocks = try message(
            #"""
            {"id":"a1","role":"assistant","content":[
              {"type":"image","data":"…"},
              {"text":"no type"},
              "not an object",
              {"type":"text","text":"kept"}
            ]}
            """#)
        #expect(unknownBlocks.answerText == "kept")

        #expect(try message(#"{"id":"a2","role":"assistant"}"#).answerText == "")
        #expect(try message(#"{"id":"a3","role":"assistant","content":null}"#).answerText == "")
        #expect(try message(#"{"id":"a4","role":"assistant","content":{"type":"text","text":"x"}}"#).answerText == "")
    }
}
