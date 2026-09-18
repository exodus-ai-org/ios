import Foundation
import Testing

@testable import Models

@Suite("ChatSseEvent")
struct ChatSseEventTests {
    @Test("decodes tool_call_start")
    func decodesToolCallStart() throws {
        let json = """
            {"type":"tool_call_start","toolCallId":"tc1","toolName":"web_search"}
            """.data(using: .utf8)!
        let event = try JSONDecoder().decode(ChatSseEvent.self, from: json)
        guard case .toolCallStart(let toolCallId, let toolName) = event else {
            Issue.record("expected .toolCallStart, got \(event)")
            return
        }
        #expect(toolCallId == "tc1")
        #expect(toolName == "web_search")
    }

    @Test("decodes done with a message array")
    func decodesDone() throws {
        let json = """
            {"type":"done","messages":[{"id":"a","role":"assistant","content":"hi"}]}
            """.data(using: .utf8)!
        let event = try JSONDecoder().decode(ChatSseEvent.self, from: json)
        guard case .done(let messages) = event else {
            Issue.record("expected .done, got \(event)")
            return
        }
        #expect(messages.count == 1)
        #expect(messages[0].displayText == "hi")
    }

    @Test("an unrecognized type decodes to .unknown instead of throwing")
    func unrecognizedTypeIsUnknown() throws {
        let json = """
            {"type":"some_future_event","foo":"bar"}
            """.data(using: .utf8)!
        let event = try JSONDecoder().decode(ChatSseEvent.self, from: json)
        guard case .unknown(let type) = event else {
            Issue.record("expected .unknown, got \(event)")
            return
        }
        #expect(type == "some_future_event")
    }
}
