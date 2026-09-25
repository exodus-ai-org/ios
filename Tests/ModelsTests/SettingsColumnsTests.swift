import Foundation
import Testing

@testable import Models

@Suite("Settings columns")
struct SettingsColumnsTests {
    private static let fullRowJSON = #"""
        {
          "id": "global",
          "providerConfig": {"provider": "Anthropic Claude", "model": "claude-sonnet-5"},
          "providers": {"anthropicApiKey": "sk-ant-1", "ollamaBaseUrl": "http://mac.local:11434"},
          "personality": {
            "nickname": "Yancey", "occupation": "Engineer", "aboutYou": "Likes Bach",
            "baseStyle": "candid", "warm": "more", "enthusiastic": "less", "headersAndLists": "default",
            "emoji": "less", "customInstructions": "Be brief."
          },
          "memory": {"autoCapture": false, "useInChat": true, "lcmEnabled": false,
                     "contextWindowPercent": 80, "freshTailSize": 6},
          "tools": {"disabledTools": ["web_search", "terminal"]},
          "lastBackupAt": "2026-09-18T12:00:00.000Z",
          "voice": {"textToSpeechVoice": "alloy"},
          "colorTone": "violet",
          "createdAt": "2026-01-01T00:00:00.000Z"
        }
        """#

    private func decode(_ json: String) throws -> SettingsSnapshot {
        try JSONDecoder().decode(SettingsSnapshot.self, from: Data(json.utf8))
    }

    private func jsonObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("a fully populated row decodes every column the phone reads, and ignores the others")
    func decodesFullRow() throws {
        let row = try decode(Self.fullRowJSON)
        #expect(row.id == "global")
        #expect(row.providerConfig?.model == "claude-sonnet-5")
        #expect(row.providers?.ollamaBaseUrl == "http://mac.local:11434")
        #expect(
            row.personality
                == PersonalitySettings(
                    nickname: "Yancey", occupation: "Engineer", aboutYou: "Likes Bach", baseStyle: "candid",
                    warm: "more", enthusiastic: "less", headersAndLists: "default", emoji: "less",
                    customInstructions: "Be brief."))
        #expect(
            row.memory
                == MemorySettings(
                    autoCapture: false, useInChat: true, lcmEnabled: false, contextWindowPercent: 80, freshTailSize: 6))
        #expect(row.tools?.disabledTools == ["web_search", "terminal"])
        #expect(row.lastBackupAt == "2026-09-18T12:00:00.000Z")
    }

    @Test(
        "a row missing any one optional column still decodes, with that column nil",
        arguments: ["providerConfig", "providers", "personality", "memory", "tools", "lastBackupAt"])
    func decodesRowMissingAColumn(column: String) throws {
        var object = try #require(try JSONSerialization.jsonObject(with: Data(Self.fullRowJSON.utf8)) as? [String: Any])
        object.removeValue(forKey: column)
        let row = try JSONDecoder().decode(SettingsSnapshot.self, from: try JSONSerialization.data(withJSONObject: object))
        let values: [String: Any?] = [
            "providerConfig": row.providerConfig, "providers": row.providers, "personality": row.personality,
            "memory": row.memory, "tools": row.tools, "lastBackupAt": row.lastBackupAt,
        ]
        for (name, value) in values {
            #expect((value == nil) == (name == column), "\(name)")
        }
    }

    @Test("a column stored in another shape reads as nil instead of failing the row")
    func wrongShapedColumnIsNil() throws {
        let row = try decode(#"{"id":"global","memory":"on","tools":[1,2],"personality":null,"lastBackupAt":42}"#)
        #expect(row.memory == nil)
        #expect(row.tools == nil)
        #expect(row.personality == nil)
        #expect(row.lastBackupAt == nil)
        #expect(row.unreadableColumns == ["memory", "tools"])
    }

    @Test("a providers column with one odd-typed field is unreadable, not empty; absent and null columns are neither")
    func unreadableColumnsAreRecorded() throws {
        let row = try decode(
            #"{"id":"global","providers":{"anthropicApiKey":"sk-ant-1","openaiApiKey":5},"providerConfig":null}"#)
        #expect(row.providers == nil)
        #expect(row.unreadableColumns == ["providers"])
        #expect(try decode(Self.fullRowJSON).unreadableColumns.isEmpty)
    }

    @Test("empty sub-objects decode to the desktop schema's defaults")
    func emptyColumnsDecodeToDefaults() throws {
        let row = try decode(#"{"id":"global","personality":{},"memory":{},"tools":{}}"#)
        #expect(row.personality == PersonalitySettings())
        #expect(row.personality?.baseStyle == "default")
        #expect(row.memory == MemorySettings())
        #expect(row.memory?.autoCapture == true)
        #expect(row.memory?.useInChat == true)
        #expect(row.memory?.lcmEnabled == true)
        #expect(row.memory?.contextWindowPercent == nil)
        #expect(row.tools == ToolsSettings())
    }

    @Test("a wrong-typed field falls back to its default and leaves its neighbours alone")
    func wrongTypedFieldFallsBack() throws {
        let row = try decode(#"{"id":"global","memory":{"autoCapture":"yes","useInChat":false,"freshTailSize":"6"}}"#)
        #expect(row.memory?.autoCapture == true)
        #expect(row.memory?.useInChat == false)
        #expect(row.memory?.freshTailSize == nil)
    }

    @Test("keys the phone does not model are written back as read, since a column is replaced whole")
    func unmodelledKeysRoundTrip() throws {
        let json = #"""
            {"id":"global",
             "personality":{"baseStyle":"quirky","pronouns":"they","extra":{"a":[1,"b",true,null]}},
             "memory":{"autoCapture":true,"futureLimit":1},
             "tools":{"disabledTools":["weather"],"allowList":["x"]}}
            """#
        let row = try decode(json)
        let personality = try jsonObject(try #require(row.personality))
        #expect(personality["baseStyle"] as? String == "quirky")
        #expect(personality["pronouns"] as? String == "they")
        let extra = try #require(personality["extra"] as? [String: Any])
        let list = try #require(extra["a"] as? [Any])
        #expect(list.count == 4)
        #expect((list[0] as? NSNumber)?.doubleValue == 1)
        #expect(list[1] as? String == "b")
        #expect(list[3] is NSNull)

        let memory = try jsonObject(try #require(row.memory))
        let limit = try #require(memory["futureLimit"] as? NSNumber)
        #expect(CFGetTypeID(limit) != CFBooleanGetTypeID(), "a number must stay a number, not become true")
        #expect(limit.doubleValue == 1)

        let tools = try jsonObject(try #require(row.tools))
        #expect(tools["allowList"] as? [String] == ["x"])
        #expect(tools["disabledTools"] as? [String] == ["weather"])
    }

    @Test("a column encodes every modelled field, with unset optionals left out")
    func columnsEncodeTheirFields() throws {
        let personality = try jsonObject(PersonalitySettings())
        #expect(Set(personality.keys) == ["baseStyle", "warm", "enthusiastic", "headersAndLists", "emoji"])
        let memory = try jsonObject(MemorySettings(contextWindowPercent: 75))
        #expect(Set(memory.keys) == ["autoCapture", "useInChat", "lcmEnabled", "contextWindowPercent"])
        #expect(memory["contextWindowPercent"] as? Double == 75)
        let tools = try jsonObject(ToolsSettings())
        #expect(tools["disabledTools"] as? [String] == [])
    }

    @Test("the write body is exactly id, lastBackupAt and the columns, with a null lastBackupAt sent as null")
    func writeBodyShape() throws {
        let body = SettingsWriteBody(
            id: "global", lastBackupAt: nil, columns: [("tools", ToolsSettings(disabledTools: ["grep"]))])
        let object = try jsonObject(body)
        #expect(Set(object.keys) == ["id", "lastBackupAt", "tools"])
        #expect(object["lastBackupAt"] is NSNull)
        #expect((object["tools"] as? [String: Any])?["disabledTools"] as? [String] == ["grep"])

        let dated = try jsonObject(
            SettingsWriteBody(id: "global", lastBackupAt: "2026-09-18T12:00:00.000Z", columns: []))
        #expect(Set(dated.keys) == ["id", "lastBackupAt"])
        #expect(dated["lastBackupAt"] as? String == "2026-09-18T12:00:00.000Z")
    }

    @Test("each column's name is the settings row's key for it")
    func columnNames() {
        #expect(SettingsColumn<ProviderConfig>.providerConfig.name == "providerConfig")
        #expect(SettingsColumn<ProvidersConfig>.providers.name == "providers")
        #expect(SettingsColumn<PersonalitySettings>.personality.name == "personality")
        #expect(SettingsColumn<MemorySettings>.memory.name == "memory")
        #expect(SettingsColumn<ToolsSettings>.tools.name == "tools")
    }
}
