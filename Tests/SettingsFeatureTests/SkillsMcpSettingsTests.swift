import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

private let failureBody = #"{"type":"error","error":{"code":"INTERNAL","message":"computer said no"}}"#

@MainActor
@Suite("Installed skills")
struct SkillsSettingsViewModelTests {
    private static let installed = #"""
        [{"slug":"pdf","displayName":"PDF","version":"1.4.0","isActive":true,"installPath":"/x","installedAt":1756000000000,
          "registryId":"anthropics/skills/pdf","source":"skills.sh"},
         {"slug":"weekly","displayName":"Weekly","version":"0.1.0","isActive":false,"installPath":"/y","installedAt":1745000000000}]
        """#
    private static let afterToggle = #"""
        [{"slug":"pdf","displayName":"PDF","version":"1.4.0","isActive":false,"installPath":"/x","source":"skills.sh"},
         {"slug":"weekly","displayName":"Weekly","version":"0.1.0","isActive":false,"installPath":"/y"}]
        """#

    private func loaded(_ server: SettingsPageTestServer) async -> SkillsSettingsViewModel {
        let vm = SkillsSettingsViewModel(apiClient: server.makeClient().0)
        await vm.load()
        return vm
    }

    @Test("load() lists the installed skills as the desktop's Installed tab does")
    func loadLists() async {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/skills/installed", [(200, Self.installed)])
        let vm = await loaded(server)
        #expect(vm.listState == .loaded)
        #expect(vm.skills.map(\.slug) == ["pdf", "weekly"])
        #expect(vm.skills.map(\.isActive) == [true, false])
        #expect(vm.skills.map(\.isLegacy) == [false, true])
        #expect(vm.skills[0].installedDate == Date(timeIntervalSince1970: 1_756_000_000))
    }

    @Test("a switch sends PATCH /skills/:slug/toggle with exactly {isActive}, then re-reads the list")
    func toggleWritesThenRereads() async throws {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/skills/installed", [(200, Self.installed), (200, Self.afterToggle)])
        server.route("PATCH", "/api/v1/skills/pdf/toggle", [(200, #"{"success":true}"#)])
        let vm = await loaded(server)
        let task = try #require(vm.setActive("pdf", false))
        #expect(vm.skills[0].isActive == false)
        #expect(vm.pending == ["pdf"])
        await task.value
        #expect(
            server.requests(under: "/api/v1/skills")
                == ["GET /api/v1/skills/installed", "PATCH /api/v1/skills/pdf/toggle", "GET /api/v1/skills/installed"])
        let body = try #require(server.lastBody("PATCH", "/api/v1/skills/pdf/toggle"))
        #expect(body as NSDictionary == ["isActive": false])
        #expect(vm.skills.map(\.isActive) == [false, false])
        #expect(vm.pending.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test("a failed switch goes back, shows the error, and the list is still re-read")
    func failedToggleReverts() async throws {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/skills/installed", [(200, Self.installed)])
        server.route("PATCH", "/api/v1/skills/weekly/toggle", [(500, failureBody)])
        let vm = await loaded(server)
        await vm.setActive("weekly", true)?.value
        #expect(vm.skills.first { $0.slug == "weekly" }?.isActive == false)
        #expect(vm.errorMessage == "computer said no")
        #expect(server.requests(under: "/api/v1/skills").last == "GET /api/v1/skills/installed")
        #expect(server.requests(under: "/api/v1/skills").count == 3)
    }

    @Test("an unchanged switch, an unknown skill, or a second flip while one is in flight sends nothing")
    func noOpToggles() async throws {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/skills/installed", [(200, Self.installed)])
        server.route("PATCH", "/api/v1/skills/pdf/toggle", [(200, #"{"success":true}"#)])
        let vm = await loaded(server)
        #expect(vm.setActive("pdf", true) == nil)
        #expect(vm.setActive("nope", false) == nil)
        let first = try #require(vm.setActive("pdf", false))
        #expect(vm.setActive("pdf", true) == nil)
        await first.value
        #expect(server.requests(under: "/api/v1/skills").filter { $0.hasPrefix("PATCH") }.count == 1)
    }

    @Test("the computer gone: the switch fails and so does the re-read, and it still goes back")
    func toggleAndRereadBothFail() async {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/skills/installed", [(200, Self.installed), (500, failureBody)])
        server.route("PATCH", "/api/v1/skills/pdf/toggle", [(500, failureBody)])
        let vm = await loaded(server)
        await vm.setActive("pdf", false)?.value
        #expect(vm.skills.first { $0.slug == "pdf" }?.isActive == true)
        #expect(vm.errorMessage == "computer said no")
    }

    @Test("a failed reload is a refresh error, not a failed switch; the next good load clears it")
    func refreshErrorIsSeparate() async {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route(
            "GET", "/api/v1/skills/installed", [(200, Self.installed), (500, failureBody), (200, Self.installed)])
        let vm = await loaded(server)
        await vm.load()
        #expect(vm.refreshError == "computer said no")
        #expect(vm.errorMessage == nil)
        #expect(vm.skills.count == 2)
        await vm.load()
        #expect(vm.refreshError == nil)
    }

    @Test("a failed first load is an error state; Retry recovers")
    func loadFailure() async {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/skills/installed", [(500, failureBody), (200, "[]")])
        let vm = await loaded(server)
        #expect(vm.listState == .failed("computer said no"))
        await vm.load()
        #expect(vm.listState == .loaded)
        #expect(vm.skills.isEmpty)
    }
}

@MainActor
@Suite("MCP servers")
struct McpSettingsViewModelTests {
    /// Rows as the desktop sends them, secrets included; the phone must not need them.
    private static let servers = #"""
        [{"id":"s1","name":"github","description":"Issues","transportType":"stdio","command":"npx","args":["-y"],
          "env":{"GITHUB_TOKEN":"secret"},"url":null,"headers":null,"extraConfig":null,"isActive":true,
          "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"},
         {"id":"s2","name":"linear","description":null,"transportType":"streamable-http","command":"",
          "url":"https://mcp.linear.app/mcp?key=secret","headers":{"Authorization":"Bearer secret"},"isActive":null}]
        """#
    private static let tools = #"""
        {"tools":[{"mcpServerName":"github","tools":[{"name":"search","description":"Find"},{"name":"open","description":""}]}]}
        """#
    private static let afterToggle = #"""
        [{"id":"s1","name":"github","transportType":"stdio","isActive":true},
         {"id":"s2","name":"linear","transportType":"streamable-http","isActive":true}]
        """#
    private static let toolsAfterToggle = #"""
        {"tools":[{"mcpServerName":"github","tools":[{"name":"search"},{"name":"open"}]},
                  {"mcpServerName":"linear","tools":[{"name":"list_issues"}]}]}
        """#

    private func loaded(_ server: SettingsPageTestServer) async -> McpSettingsViewModel {
        let vm = McpSettingsViewModel(apiClient: server.makeClient().0)
        await vm.load()
        return vm
    }

    @Test("load() lists the servers with their active state and the tools of each connected one")
    func loadLists() async {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/mcp", [(200, Self.servers)])
        server.route("GET", "/api/v1/mcp/tools", [(200, Self.tools)])
        let vm = await loaded(server)
        #expect(vm.listState == .loaded)
        #expect(vm.servers.map(\.name) == ["github", "linear"])
        #expect(vm.servers.map(\.isActive) == [true, false])
        #expect(vm.servers.map(\.isRemote) == [false, true])
        #expect(vm.tools(for: vm.servers[0]).map(\.name) == ["search", "open"])
        #expect(vm.tools(for: vm.servers[1]).isEmpty)
    }

    @Test("the switch sends PUT /mcp/:id with only {isActive} — no secrets resent — then re-reads servers and tools")
    func toggleSendsOnlyTheFlag() async throws {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/mcp", [(200, Self.servers), (200, Self.afterToggle)])
        server.route("GET", "/api/v1/mcp/tools", [(200, Self.tools), (200, Self.toolsAfterToggle)])
        server.route("PUT", "/api/v1/mcp/s2", [(200, "{}")])
        let vm = await loaded(server)
        let task = try #require(vm.setActive("s2", true))
        #expect(vm.servers[1].isActive)
        await task.value
        let body = try #require(server.lastBody("PUT", "/api/v1/mcp/s2"))
        #expect(body as NSDictionary == ["isActive": true])
        let requests = server.requests(under: "/api/v1/mcp")
        #expect(requests.count == 5)
        #expect(requests[2] == "PUT /api/v1/mcp/s2")
        #expect(Set(requests[3...]) == ["GET /api/v1/mcp", "GET /api/v1/mcp/tools"])
        #expect(vm.tools(for: vm.servers[1]).map(\.name) == ["list_issues"])
        #expect(vm.errorMessage == nil)
    }

    @Test("a failed switch goes back, shows the error, and servers are still re-read")
    func failedToggleReverts() async {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/mcp", [(200, Self.servers)])
        server.route("GET", "/api/v1/mcp/tools", [(200, Self.tools)])
        server.route("PUT", "/api/v1/mcp/s1", [(500, failureBody)])
        let vm = await loaded(server)
        await vm.setActive("s1", false)?.value
        #expect(vm.servers[0].isActive)
        #expect(vm.errorMessage == "computer said no")
        #expect(server.requests(under: "/api/v1/mcp").filter { $0 == "GET /api/v1/mcp" }.count == 2)
    }

    @Test("the computer gone: the switch fails and so does the re-read, and it still goes back")
    func toggleAndRereadBothFail() async {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/mcp", [(200, Self.servers), (500, failureBody)])
        server.route("GET", "/api/v1/mcp/tools", [(200, Self.tools), (500, failureBody)])
        server.route("PUT", "/api/v1/mcp/s1", [(500, failureBody)])
        let vm = await loaded(server)
        await vm.setActive("s1", false)?.value
        #expect(vm.servers[0].isActive)
        #expect(vm.errorMessage == "computer said no")
    }

    @Test("a failed reload is a refresh error, not a failed switch; the next good load clears it")
    func refreshErrorIsSeparate() async {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/mcp", [(200, Self.servers), (500, failureBody), (200, Self.servers)])
        server.route("GET", "/api/v1/mcp/tools", [(200, Self.tools)])
        let vm = await loaded(server)
        await vm.load()
        #expect(vm.refreshError == "computer said no")
        #expect(vm.errorMessage == nil)
        #expect(vm.servers.count == 2)
        await vm.load()
        #expect(vm.refreshError == nil)
    }

    @Test("tools that cannot be read only hide the counts; servers that cannot be read are an error state")
    func loadFailures() async {
        let toolsDown = SettingsPageTestServer(rows: ["{}"])
        toolsDown.route("GET", "/api/v1/mcp", [(200, Self.servers)])
        toolsDown.route("GET", "/api/v1/mcp/tools", [(500, failureBody)])
        let first = await loaded(toolsDown)
        #expect(first.listState == .loaded)
        #expect(first.toolsByServer.isEmpty)

        let serversDown = SettingsPageTestServer(rows: ["{}"])
        serversDown.route("GET", "/api/v1/mcp", [(500, failureBody)])
        serversDown.route("GET", "/api/v1/mcp/tools", [(200, Self.tools)])
        let second = await loaded(serversDown)
        #expect(second.listState == .failed("computer said no"))
    }
}
