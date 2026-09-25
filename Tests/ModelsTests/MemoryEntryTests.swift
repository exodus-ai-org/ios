import Foundation
import Models
import Testing

@Suite("Memory entries")
struct MemoryEntryTests {
    @Test("a desktop row decodes; null details and isActive read as the desktop reads them")
    func decodesDesktopRow() throws {
        let json = #"""
            [{"id":"a","userId":"u","section":"person","key":"Ada","summary":"Sister","details":["Lisbon"],
              "confidence":null,"source":"explicit","createdAt":null,"updatedAt":"2026-09-23T10:00:00.000Z",
              "lastUsedAt":null,"isActive":false},
             {"id":"b","section":"topic","key":"Music","summary":"Bach","details":null,"isActive":null}]
            """#
        let entries = try JSONDecoder().decode([MemoryEntry].self, from: Data(json.utf8))
        #expect(
            entries[0]
                == MemoryEntry(
                    id: "a", section: "person", key: "Ada", summary: "Sister", details: ["Lisbon"], isActive: false,
                    updatedAt: "2026-09-23T10:00:00.000Z"))
        #expect(entries[1].details == [])
        #expect(entries[1].isActive)
    }

    @Test("a row without an id does not decode")
    func idIsRequired() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MemoryEntry.self, from: Data(#"{"key":"x"}"#.utf8))
        }
    }

    @Test("the create body is exactly the desktop's, with source explicit")
    func createBody() throws {
        let data = try JSONEncoder().encode(MemoryCreateBody(section: "topic", key: "K", summary: "", details: []))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(object == ["section": "topic", "key": "K", "summary": "", "details": [String](), "source": "explicit"])
    }

    @Test("a patch body carries only the fields set")
    func patchBody() throws {
        let data = try JSONEncoder().encode(MemoryPatchBody(summary: "S", isActive: true))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(object == ["summary": "S", "isActive": true])
        #expect(MemoryPatchBody().isEmpty)
        #expect(!MemoryPatchBody(details: []).isEmpty)
    }
}
