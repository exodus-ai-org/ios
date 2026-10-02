import Foundation
import Models
import Testing

@testable import NetworkingKit

/// The composer's choices on the wire: `advancedTools` and `reasoningEffort` (desktop `postRequestBodySchema`).
@Suite("Chat request options")
struct ChatRequestOptionsTests {
    private func body(_ options: TurnOptions, _ suite: String = #function) throws -> [String: Any] {
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: suite)!)
        let question = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)
        let request = try #require(
            ChatStreamManager.makeRequest(chatId: "c1", messages: [question], serverConfig: config, options: options))
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("no choices: no tools, and no reasoningEffort key at all")
    func noChoices() throws {
        let body = try body(TurnOptions())
        #expect((body["advancedTools"] as? [String]) == [])
        #expect(!body.keys.contains("reasoningEffort"))
    }

    @Test("Deep Research goes in advancedTools as \"Deep Research\"")
    func deepResearch() throws {
        let body = try body(TurnOptions(deepResearch: true))
        #expect((body["advancedTools"] as? [String]) == ["Deep Research"])
        #expect(!body.keys.contains("reasoningEffort"))
    }

    @Test("a level other than off is sent by its name")
    func level() throws {
        let body = try body(TurnOptions(reasoningEffort: .high))
        #expect(body["reasoningEffort"] as? String == "high")
        #expect((body["advancedTools"] as? [String]) == [])
    }

    @Test("off is left out, as no reasoning option")
    func off() throws {
        #expect(!(try body(TurnOptions(reasoningEffort: .off))).keys.contains("reasoningEffort"))
    }
}
