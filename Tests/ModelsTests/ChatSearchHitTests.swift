import Foundation
import Testing

@testable import Models

@Suite("ChatSearchHit")
struct ChatSearchHitTests {
    @Test("decodes a real search row and ignores the other message columns")
    func decodesARealRow() throws {
        let json = #"""
            [{"id":"m1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"hello"}],
              "searchText":"hello world","title":"Greeting","createdAt":"2026-09-09T00:26:27.327Z",
              "usage":{"input":3},"toolCallId":null,"details":null,"durationMs":12}]
            """#
        let hits = try JSONDecoder().decode([ChatSearchHit].self, from: Data(json.utf8))
        #expect(
            hits == [
                ChatSearchHit(
                    id: "m1", chatId: "c1", role: "assistant", searchText: "hello world", title: "Greeting",
                    createdAt: "2026-09-09T00:26:27.327Z")
            ])
    }

    @Test("a null or missing searchText, role and createdAt decode as nil")
    func optionalFieldsMayBeMissing() throws {
        let json = #"{"id":"m1","chatId":"c1","title":"T","searchText":null}"#
        let hit = try JSONDecoder().decode(ChatSearchHit.self, from: Data(json.utf8))
        #expect(hit.searchText == nil)
        #expect(hit.role == nil)
        #expect(hit.createdAt == nil)
    }

    @Test("a row without a title is rejected")
    func titleIsRequired() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChatSearchHit.self, from: Data(#"{"id":"m1","chatId":"c1"}"#.utf8))
        }
    }
}
