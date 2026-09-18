import Foundation
import Testing

@testable import Models

@Suite("ChatSummary")
struct ChatSummaryTests {
    @Test("decodes a chat row from GET /api/history")
    func decodesChatSummary() throws {
        let json = """
            {"id":"c1","createdAt":"2026-09-18T12:34:56.789Z","title":"Trip planning","favorite":false,"projectId":null,"useProjectInstructions":true}
            """.data(using: .utf8)!
        let chat = try JSONDecoder().decode(ChatSummary.self, from: json)
        #expect(chat.id == "c1")
        #expect(chat.title == "Trip planning")
        #expect(chat.createdAt == "2026-09-18T12:34:56.789Z")
        #expect(chat.favorite == false)
        #expect(chat.projectId == nil)
    }
}
