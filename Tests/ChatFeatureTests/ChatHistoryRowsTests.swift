import Foundation
import Models
import Testing

@testable import ChatFeature

@Suite("ChatHistoryRows")
struct ChatHistoryRowsTests {
    private func rows(_ json: String) throws -> [ChatMessage] {
        try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    }

    @Test("a user row becomes the plain UI shape: id, role, content, timestamp — no row bookkeeping")
    func userRow() throws {
        let converted = ChatHistoryRows.uiMessages(
            from: try rows(
                #"""
                [{"id":"u1","chatId":"c1","role":"user","content":"hi","searchText":"hi","createdAt":"2026-09-18T12:00:00.000Z","usage":null,"toolCallId":null,"details":null}]
                """#))
        let message = try #require(converted.first)
        #expect(Set(message.raw.keys) == ["id", "role", "content", "timestamp"])
        #expect(message.role == "user")
        #expect(message.displayText == "hi")
        #expect(message.timestampMs == 1_789_732_800_000)
    }

    @Test("an assistant row keeps usage/api/provider/model/stopReason/durationMs and drops the row bookkeeping")
    func assistantRow() throws {
        let converted = ChatHistoryRows.uiMessages(
            from: try rows(
                #"""
                [{"id":"a1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"hello"}],"usage":{"input":3},"api":"anthropic-messages","provider":"anthropic","model":"claude-x","stopReason":"stop","errorMessage":null,"durationMs":1200,"createdAt":"2026-09-18T12:00:05Z","searchText":"hello"}]
                """#))
        let message = try #require(converted.first)
        #expect(
            Set(message.raw.keys)
                == ["id", "role", "content", "timestamp", "usage", "api", "provider", "model", "stopReason", "durationMs"])
        #expect(message.displayText == "hello")
        #expect(message.raw["usage"] == .object(["input": .number(3)]))
        #expect(message.raw["provider"] == .string("anthropic"))
        #expect(message.raw["durationMs"] == .number(1200))
        #expect(message.timestampMs == 1_789_732_805_000)  // no fractional seconds in the source
    }

    @Test("null assistant columns get the desktop's defaults, and a set errorMessage is kept")
    func assistantRowDefaults() throws {
        let converted = ChatHistoryRows.uiMessages(
            from: try rows(
                #"""
                [{"id":"a2","chatId":"c1","role":"assistant","content":[],"usage":null,"api":null,"provider":null,"model":null,"stopReason":null,"errorMessage":"boom","durationMs":null,"createdAt":"2026-09-18T12:00:05.000Z"}]
                """#))
        let message = try #require(converted.first)
        #expect(message.raw["usage"] == .null)
        #expect(message.raw["api"] == .string(""))
        #expect(message.raw["provider"] == .string(""))
        #expect(message.raw["model"] == .string(""))
        #expect(message.raw["stopReason"] == .string("stop"))
        #expect(message.raw["errorMessage"] == .string("boom"))
        #expect(message.raw.keys.contains("durationMs") == false)
    }

    @Test("a toolResult row keeps toolCallId/toolName/details/isError; any non-user, non-assistant role is a toolResult")
    func toolResultRow() throws {
        let converted = ChatHistoryRows.uiMessages(
            from: try rows(
                #"""
                [{"id":"t1","chatId":"c1","role":"toolResult","content":[{"type":"text","text":"ok"}],"toolCallId":"call_1","toolName":"web_search","details":{"k":1},"isError":false,"createdAt":"2026-09-18T12:00:06.500Z"},
                 {"id":"t2","chatId":"c1","role":"tool","content":[],"toolCallId":null,"toolName":null,"details":null,"isError":null,"createdAt":"2026-09-18T12:00:07.000Z"}]
                """#))
        let first = try #require(converted.first)
        #expect(Set(first.raw.keys) == ["id", "role", "content", "timestamp", "toolCallId", "toolName", "details", "isError"])
        #expect(first.raw["toolCallId"] == .string("call_1"))
        #expect(first.toolName == "web_search")
        #expect(first.raw["details"] == .object(["k": .number(1)]))
        #expect(first.isError == false)
        #expect(first.timestampMs == 1_789_732_806_500)

        let second = try #require(converted.last)
        #expect(second.role == "toolResult")
        #expect(second.raw["toolCallId"] == .string(""))
        #expect(second.raw["toolName"] == .string(""))
        #expect(second.raw["details"] == .null)
        #expect(second.raw["isError"] == .bool(false))
    }

    @Test("an unparseable createdAt keeps an existing timestamp, and otherwise leaves the timestamp out")
    func timestampFallbacks() throws {
        let converted = ChatHistoryRows.uiMessages(
            from: try rows(
                #"""
                [{"id":"u1","role":"user","content":"a","createdAt":"not a date","timestamp":42},
                 {"id":"u2","role":"user","content":"b","createdAt":"not a date"}]
                """#))
        try #require(converted.count == 2)  // `#require`, not `#expect`: the indexing below must not crash the run
        #expect(converted[0].timestampMs == 42)
        #expect(converted[1].raw.keys.contains("timestamp") == false)
    }

    @Test("converted messages encode without any of the database bookkeeping columns")
    func encodedShapeHasNoRowBookkeeping() throws {
        let converted = ChatHistoryRows.uiMessages(
            from: try rows(
                #"""
                [{"id":"u1","chatId":"c1","role":"user","content":"hi","searchText":"hi","createdAt":"2026-09-18T12:00:00.000Z"}]
                """#))
        let data = try JSONEncoder().encode(converted)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let keys = Set(try #require(object.first).keys)
        #expect(keys.isDisjoint(with: ["chatId", "searchText", "createdAt"]))
    }
}
