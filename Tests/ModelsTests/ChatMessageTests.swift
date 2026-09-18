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
