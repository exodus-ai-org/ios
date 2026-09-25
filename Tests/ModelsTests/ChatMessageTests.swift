import Foundation
import Testing

@testable import Models

@Suite("ChatMessage")
struct ChatMessageTests {
    @Test("decodes a plain string user message")
    func decodesUserMessage() throws {
        let json = """
            {"id":"11111111-1111-4111-8111-111111111111","role":"user","content":"hi there","timestamp":1700000000000}
            """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(message.id == "11111111-1111-4111-8111-111111111111")
        #expect(message.role == "user")
        #expect(message.displayText == "hi there")
        #expect(message.timestampMs == 1_700_000_000_000)
    }

    @Test("extracts text from an assistant content block array, ignoring unknown block types")
    func decodesAssistantMessage() throws {
        let json = """
            {"id":"a","role":"assistant","content":[{"type":"text","text":"hello"},{"type":"toolCall","id":"t1","name":"web_search"}],"usage":{"input":1},"stopReason":"stop"}
            """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(message.displayText == "hello")
    }

    @Test("round-trips fields this struct never modeled, unmodified")
    func roundTripsUnknownFields() throws {
        let json = """
            {"id":"a","role":"assistant","content":"x","usage":{"input":1},"stopReason":"stop"}
            """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        let reEncoded = try JSONEncoder().encode(message)
        let reDecoded = try JSONDecoder().decode(ChatMessage.self, from: reEncoded)
        #expect(reDecoded.raw["usage"] != nil)
        #expect(reDecoded.raw["stopReason"]?.stringValue == "stop")
    }

    @Test("toolResult message exposes isError and toolName")
    func decodesToolResultMessage() throws {
        let json = """
            {"id":"tr1","role":"toolResult","toolCallId":"tc1","toolName":"web_search","content":[{"type":"text","text":"3 results"}],"details":{"count":3},"isError":false,"timestamp":1700000000000}
            """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        #expect(message.role == "toolResult")
        #expect(message.toolName == "web_search")
        #expect(message.isError == false)
    }

    @Test("userMessage(id:text:timestampMs:) builds a message the server will accept")
    func buildsOutgoingUserMessage() throws {
        let message = ChatMessage.userMessage(id: "u1", text: "hello", timestampMs: 1_700_000_000_000)
        #expect(message.role == "user")
        #expect(message.displayText == "hello")
        let data = try JSONEncoder().encode(message)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["id"] as? String == "u1")
        #expect(obj?["content"] as? String == "hello")
    }
}

/// Shapes copied from the desktop's wire types (`packages/shared/src/types/chat.ts`) and what the
/// chat kernel emits (`toAssistant` / `toToolResult` in `src/main/lib/ai/kernel/run.ts`).
@Suite("ChatMessage typed accessors")
struct ChatMessageTypedTests {
    private static let runId = "11111111-1111-4111-8111-111111111111"

    private func decode(_ json: String) throws -> ChatMessage {
        try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    }

    @Test("a user message with string content is one text block and carries its run")
    func userStringContent() throws {
        let message = try decode(
            #"""
            {"id":"11111111-1111-4111-8111-111111111111","runId":"11111111-1111-4111-8111-111111111111","role":"user","content":"hi there","timestamp":1700000000000}
            """#)
        #expect(message.contentBlocks == [.text("hi there")])
        #expect(message.runId == Self.runId)
        #expect(message.toolCallId == nil)
        #expect(message.details == nil)
        #expect(message.durationMs == nil)
        #expect(message.stopReason == nil)
        #expect(message.errorMessage == nil)
    }

    @Test("a user message with a block array keeps text and image blocks in order")
    func userArrayContentWithImage() throws {
        let message = try decode(
            #"""
            {"id":"u2","runId":"u2","role":"user","content":[
              {"type":"text","text":"what is this?"},
              {"type":"image","data":"data:image/png;base64,iVBORw0KGgo=","mimeType":"image/png"}
            ],"timestamp":1700000000000}
            """#)
        #expect(
            message.contentBlocks == [
                .text("what is this?"),
                .image(mimeType: "image/png", dataURL: "data:image/png;base64,iVBORw0KGgo="),
            ])
    }

    @Test("an image whose data is bare base64 becomes a data URL; one that already is a data URL is kept as is")
    func imageDataURLNormalisation() throws {
        let message = try decode(
            #"""
            {"id":"u3","role":"user","content":[{"type":"image","data":"iVBORw0KGgo=","mimeType":"image/jpeg"}]}
            """#)
        #expect(message.contentBlocks == [.image(mimeType: "image/jpeg", dataURL: "data:image/jpeg;base64,iVBORw0KGgo=")])
    }

    @Test("an assistant step keeps text, thinking and toolCall blocks in order, and its own fields")
    func assistantTextThinkingToolCall() throws {
        let message = try decode(
            #"""
            {"id":"a1","runId":"11111111-1111-4111-8111-111111111111","role":"assistant","content":[
              {"type":"thinking","thinking":"**Plan** the search","thinkingSignature":"sig"},
              {"type":"text","text":"Let me look that up."},
              {"type":"toolCall","id":"call_1","name":"web_search","arguments":{"query":"weather in Paris","count":3},"thoughtSignature":"ts"}
            ],"usage":{"input":10,"output":5,"cacheRead":0,"cacheWrite":0,"totalTokens":15,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},
            "cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0},
            "api":"anthropic-messages","provider":"anthropic","model":"claude-x","stopReason":"toolUse","timestamp":1700000001000}
            """#)
        #expect(
            message.contentBlocks == [
                .thinking("**Plan** the search"),
                .text("Let me look that up."),
                .toolCall(
                    id: "call_1", name: "web_search",
                    arguments: ["query": .string("weather in Paris"), "count": .number(3)]),
            ])
        #expect(message.runId == Self.runId)
        #expect(message.stopReason == "toolUse")
        #expect(message.errorMessage == nil)
        #expect(message.durationMs == nil)
    }

    @Test("the last assistant step of a run carries durationMs")
    func assistantDuration() throws {
        let message = try decode(
            #"""
            {"id":"a2","runId":"r","role":"assistant","content":[{"type":"text","text":"It is sunny."}],"stopReason":"stop","durationMs":12345,"timestamp":1700000005000}
            """#)
        #expect(message.durationMs == 12_345)
        #expect(message.stopReason == "stop")
    }

    @Test("a toolResult exposes toolCallId, toolName, details and isError, and its content blocks")
    func toolResultWithDetails() throws {
        let message = try decode(
            #"""
            {"id":"t1","runId":"11111111-1111-4111-8111-111111111111","role":"toolResult","toolCallId":"call_1","toolName":"web_search","content":[{"type":"text","text":"3 results"}],"details":{"query":"weather in Paris","results":[{"title":"Meteo","url":"https://example.com"}]},"isError":true,"timestamp":1700000002000}
            """#)
        #expect(message.toolCallId == "call_1")
        #expect(message.toolName == "web_search")
        #expect(message.isError)
        #expect(message.runId == Self.runId)
        #expect(message.contentBlocks == [.text("3 results")])
        #expect(
            message.details
                == .object([
                    "query": .string("weather in Paris"),
                    "results": .array([.object(["title": .string("Meteo"), "url": .string("https://example.com")])]),
                ]))
    }

    @Test("a null or missing details is nil, not a wrapped .null")
    func nullDetailsIsNil() throws {
        let withNull = try decode(
            #"{"id":"t2","role":"toolResult","toolCallId":"c","toolName":"n","content":[],"details":null,"isError":false}"#)
        #expect(withNull.details == nil)
        let without = try decode(#"{"id":"t3","role":"toolResult","toolCallId":"c","toolName":"n","content":[],"isError":false}"#)
        #expect(without.details == nil)
        #expect(without.contentBlocks == [])
    }

    @Test("an errored assistant exposes stopReason and errorMessage; empty content is no blocks")
    func erroredAssistant() throws {
        let message = try decode(
            #"""
            {"id":"a3","runId":"r","role":"assistant","content":[],"api":"anthropic-messages","provider":"anthropic","model":"claude-x","stopReason":"error","errorMessage":"429 rate limit exceeded","timestamp":1700000006000}
            """#)
        #expect(message.stopReason == "error")
        #expect(message.errorMessage == "429 rate limit exceeded")
        #expect(message.contentBlocks == [])
    }

    @Test("a null errorMessage is nil")
    func nullErrorMessageIsNil() throws {
        let message = try decode(#"{"id":"a4","role":"assistant","content":[],"stopReason":"stop","errorMessage":null}"#)
        #expect(message.errorMessage == nil)
    }

    @Test("a block of a type this client does not know, or one missing its fields, is kept as .unknown, never dropped")
    func unknownBlocksAreKept() throws {
        let message = try decode(
            #"""
            {"id":"a5","role":"assistant","content":[
              {"type":"text","text":"before"},
              {"type":"audio","url":"https://example.com/a.mp3"},
              {"type":"text"},
              {"type":"toolCall","id":"c1"},
              {"type":"image","data":"x"},
              "not an object",
              {"type":"text","text":"after"}
            ]}
            """#)
        #expect(
            message.contentBlocks == [
                .text("before"),
                .unknown(.object(["type": .string("audio"), "url": .string("https://example.com/a.mp3")])),
                .unknown(.object(["type": .string("text")])),
                .unknown(.object(["type": .string("toolCall"), "id": .string("c1")])),
                .unknown(.object(["type": .string("image"), "data": .string("x")])),
                .unknown(.string("not an object")),
                .text("after"),
            ])
    }

    @Test("a toolCall without arguments has empty arguments")
    func toolCallWithoutArguments() throws {
        let message = try decode(
            #"{"id":"a6","role":"assistant","content":[{"type":"toolCall","id":"c1","name":"weather"}]}"#)
        #expect(message.contentBlocks == [.toolCall(id: "c1", name: "weather", arguments: [:])])
    }

    @Test("content of a shape the wire never sends is one .unknown block; null or missing content is none")
    func oddContentShapes() throws {
        let number = try decode(#"{"id":"m1","role":"assistant","content":7}"#)
        #expect(number.contentBlocks == [.unknown(.number(7))])
        let null = try decode(#"{"id":"m2","role":"assistant","content":null}"#)
        #expect(null.contentBlocks == [])
        let missing = try decode(#"{"id":"m3","role":"assistant"}"#)
        #expect(missing.contentBlocks == [])
    }

    @Test("a message from before runId existed has none, and everything else still reads")
    func runIdAbsentOnOldRows() throws {
        let message = try decode(
            #"{"id":"a7","role":"assistant","content":[{"type":"text","text":"old"}],"stopReason":"stop","timestamp":1}"#)
        #expect(message.runId == nil)
        #expect(message.contentBlocks == [.text("old")])
        let null = try decode(#"{"id":"a8","runId":null,"role":"assistant","content":"x"}"#)
        #expect(null.runId == nil)
    }

    @Test("typed accessors read raw, so fields nobody modelled survive an encode/decode round trip untouched")
    func unknownFieldsSurviveTheRoundTrip() throws {
        let json = #"""
            {"id":"a9","runId":"r","role":"assistant","content":[
              {"type":"thinking","thinking":"hm","thinkingSignature":"sig","redacted":false},
              {"type":"toolCall","id":"c1","name":"weather","arguments":{"city":"Paris"},"thoughtSignature":"ts","namespace":"ns"},
              {"type":"audio","url":"https://example.com/a.mp3"}
            ],"usage":{"input":1,"output":2},"cost":{"total":0.5},"responseId":"resp_1","providerThinkingLevel":"high","futureField":{"a":[1,2,{"b":null}]},
            "stopReason":"stop","durationMs":900,"timestamp":1700000000000}
            """#
        let original = try decode(json)
        let reDecoded = try JSONDecoder().decode(ChatMessage.self, from: try JSONEncoder().encode(original))
        #expect(reDecoded == original)
        #expect(reDecoded.raw == original.raw)
        #expect(reDecoded.raw["futureField"] == .object(["a": .array([.number(1), .number(2), .object(["b": .null])])]))
        // Unknown fields nested inside a content block survive too, though the typed block doesn't model them.
        guard case .array(let blocks)? = reDecoded.raw["content"], case .object(let toolCall) = blocks[1] else {
            Issue.record("content did not survive")
            return
        }
        #expect(toolCall["thoughtSignature"] == .string("ts"))
        #expect(toolCall["namespace"] == .string("ns"))
    }

    @Test("userMessage(id:text:timestampMs:) stamps the run with its own id, as the desktop client does")
    func outgoingUserMessageOpensItsRun() throws {
        let message = ChatMessage.userMessage(id: "u1", text: "hello", timestampMs: 1_700_000_000_000)
        #expect(message.runId == "u1")
        #expect(message.contentBlocks == [.text("hello")])
        let data = try JSONEncoder().encode(message)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["runId"] as? String == "u1")
    }

    @Test("userMessage(id:content:timestampMs:) keeps block content verbatim and still opens its own run")
    func userMessageWithBlockContentKeepsTheBlocks() throws {
        let content: JSONValue = .array([
            .object(["type": .string("text"), "text": .string("what is this?")]),
            .object(["type": .string("image"), "data": .string("data:image/png;base64,AAAA"), "mimeType": .string("image/png")])
        ])
        let message = ChatMessage.userMessage(id: "u9", content: content, timestampMs: 5)
        #expect(message.role == "user")
        #expect(message.runId == "u9")
        #expect(message.content == content)
        #expect(message.timestampMs == 5)
        #expect(message.contentBlocks.count == 2)
    }
}
