import Foundation
import Models
import Testing

@Suite("Usage, skills, MCP and backup rows")
struct UsageSkillsBackupTests {
    @Test("the usage summary decodes the desktop's shape, and missing or null figures read as zero")
    func usageDecodes() throws {
        let json = #"""
            {"totalCost":1.25,"totalTokens":3000,"totalRequests":4,
             "daily":[{"date":"2026-09-24","cost":1.25,"tokens":3000},{"date":"2026-09-23","tokens":null}],
             "models":[{"model":"gpt","provider":"openai","cost":1.25,"inputTokens":2000,"outputTokens":1000,
               "cacheReadTokens":10,"requests":4},{"provider":"x"}]}
            """#
        let usage = try JSONDecoder().decode(UsageSummary.self, from: Data(json.utf8))
        #expect(usage.totalRequests == 4)
        #expect(usage.daily == [.init(date: "2026-09-24", cost: 1.25, tokens: 3000), .init(date: "2026-09-23", tokens: 0)])
        #expect(usage.models[0].tokens == 3000)
        #expect(usage.models[1].model == "unknown")
        #expect(!usage.isEmpty)
        #expect(try JSONDecoder().decode(UsageSummary.self, from: Data("{}".utf8)).isEmpty)
    }

    @Test("an installed skill decodes; one without a source is legacy")
    func skillDecodes() throws {
        let json = #"""
            [{"slug":"pdf","displayName":"PDF","version":"1.0","isActive":true,"installPath":"/p","installedAt":1000,
              "registryId":"a/b/pdf","source":"skills.sh"},{"slug":"old"}]
            """#
        let skills = try JSONDecoder().decode([InstalledSkill].self, from: Data(json.utf8))
        #expect(skills[0].installedDate == Date(timeIntervalSince1970: 1))
        #expect(!skills[0].isLegacy)
        #expect(skills[1].displayName == "old")
        #expect(skills[1].isLegacy)
        #expect(!skills[1].isActive)
    }

    @Test("an MCP row decodes without its command, URL, env or headers; null isActive is off")
    func mcpDecodes() throws {
        let json = #"""
            {"id":"s","name":"gh","description":null,"transportType":"sse","command":"x","env":{"T":"secret"},
             "url":"https://h/?k=secret","headers":{"A":"secret"},"isActive":null}
            """#
        let server = try JSONDecoder().decode(McpServer.self, from: Data(json.utf8))
        #expect(server == McpServer(id: "s", name: "gh", description: "", transportType: "sse", isActive: false))
        #expect(server.isRemote)
        let tools = try JSONDecoder().decode(
            McpToolsResponse.self,
            from: Data(#"{"tools":[{"mcpServerName":"gh","tools":[{"name":"a"}]},{"mcpServerName":"gh","tools":[{"name":"b"}]}]}"#.utf8))
        #expect(tools.byServer["gh"]?.map(\.name) == ["a", "b"])
    }

    @Test("the flag body is exactly {isActive}")
    func flagBody() throws {
        let data = try JSONEncoder().encode(ActiveFlagBody(isActive: false))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
        #expect(object == ["isActive": false])
    }

    @Test("backup status and files decode; the date reads with or without fractional seconds")
    func backupDecodes() throws {
        let status = try JSONDecoder().decode(
            BackupStatus.self, from: Data(#"{"autoBackup":false,"lastBackupAt":"2026-09-24T03:00:02.123Z"}"#.utf8))
        #expect(!status.autoBackup)
        #expect(abs(try #require(status.lastBackupDate).timeIntervalSince1970 - 1_790_218_802.123) < 0.001)
        #expect(BackupInfo.date(from: "2026-09-24T03:00:02Z") == Date(timeIntervalSince1970: 1_790_218_802))
        #expect(try JSONDecoder().decode(BackupStatus.self, from: Data(#"{"lastBackupAt":null}"#.utf8)).autoBackup)
        let files = try JSONDecoder().decode(
            [BackupInfo].self, from: Data(#"[{"name":"a.tar.gz","size":12,"createdAt":"2026-09-24T03:00:02.123Z"}]"#.utf8))
        #expect(files == [BackupInfo(name: "a.tar.gz", size: 12, createdAt: "2026-09-24T03:00:02.123Z")])
    }
}
