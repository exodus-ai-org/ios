import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

@MainActor
@Suite("Built-in Tools")
struct ToolsSettingsViewModelTests {
    /// Off on the computer: terminal, web search under its pre-rename name, a tool the desktop does not switch here
    /// (deep_research) and one this app has never heard of.
    private static let row = #"""
        {"id":"global","lastBackupAt":"2026-09-18T12:00:00.000Z",
         "tools":{"disabledTools":["terminal","webSearch","deep_research","future_tool"],"extra":true}}
        """#

    private func loaded(_ server: SettingsPageTestServer, suite: String = #function) async -> ToolsSettingsViewModel {
        let vm = ToolsSettingsViewModel(store: server.makeStore(suite))
        await vm.load()
        return vm
    }

    @Test("load() reads the switches, a pre-rename name as its tool, and reports names this app does not know")
    func loadReadsSwitches() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loaded(server)
        #expect(vm.hasLoaded)
        #expect(vm.isEnabled("terminal") == false)
        #expect(vm.isEnabled("web_search") == false)
        #expect(vm.isEnabled("grep"))
        #expect(vm.unknownDisabledNames == ["future_tool"])
    }

    @Test("pull to refresh waits for a switch still being written, then reads the column: the switch is not undone")
    func refreshWaitsForWrites() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loaded(server)
        let write = try #require(vm.setEnabled("grep", false))
        server.serve(rows: [#"{"id":"global","tools":{"disabledTools":["grep","image_generation"]}}"#])
        await vm.refresh()
        await write.value
        #expect(vm.isEnabled("grep") == false)
        #expect(vm.isEnabled("image_generation") == false)
        #expect(vm.isEnabled("terminal"))
        #expect(server.methods == ["GET", "GET", "POST", "GET"])
    }

    @Test("switching a tool off appends its wire name and leaves every other entry, and other keys, untouched")
    func switchOffAppends() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loaded(server)
        await vm.setEnabled("grep", false)?.value
        let body = try server.onlyPostBody()
        #expect(Set(body.keys) == ["id", "lastBackupAt", "tools"])
        let tools = try #require(body["tools"] as? [String: Any])
        #expect(tools["disabledTools"] as? [String] == ["terminal", "webSearch", "deep_research", "future_tool", "grep"])
        #expect(tools["extra"] as? Bool == true)
        #expect(vm.isEnabled("grep") == false)
    }

    @Test("switching a tool on removes it under either spelling and nothing else")
    func switchOnRemovesBothSpellings() async throws {
        let server = SettingsPageTestServer(rows: [
            #"{"id":"global","tools":{"disabledTools":["webSearch","terminal","web_search","future_tool"]}}"#
        ])
        let vm = await loaded(server)
        await vm.setEnabled("web_search", true)?.value
        let tools = try #require(try server.onlyPostBody()["tools"] as? [String: Any])
        #expect(tools["disabledTools"] as? [String] == ["terminal", "future_tool"])
        #expect(vm.isEnabled("web_search"))
    }

    @Test("a toggle is written over the column as the server holds it now")
    func toggleIsReadModifyWrite() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = await loaded(server)
        server.serve(rows: [#"{"id":"global","lastBackupAt":null,"tools":{"disabledTools":["weather"]}}"#])
        await vm.setEnabled("grep", false)?.value
        #expect(server.methods == ["GET", "GET", "POST"])
        let body = try server.onlyPostBody()
        #expect(body["lastBackupAt"] is NSNull)
        #expect((body["tools"] as? [String: Any])?["disabledTools"] as? [String] == ["weather", "grep"])
        #expect(vm.isEnabled("weather") == false)
        #expect(vm.isEnabled("terminal"))
        #expect(vm.unknownDisabledNames.isEmpty)
    }

    @Test("toggles made in a row are written one after another, and both land")
    func togglesAreSerialized() async throws {
        let server = SettingsPageTestServer(rows: [#"{"id":"global","tools":{"disabledTools":[]}}"#])
        let vm = await loaded(server)
        let first = vm.setEnabled("grep", false)
        // The server now holds what the first write posted, as the real one would.
        server.serve(rows: [#"{"id":"global","tools":{"disabledTools":["grep"]}}"#])
        let second = vm.setEnabled("weather", false)
        #expect(vm.isEnabled("grep") == false && vm.isEnabled("weather") == false)
        await first?.value
        await second?.value
        #expect(server.methods == ["GET", "GET", "POST", "GET", "POST"])
        let last = try #require(server.postBodies.last?["tools"] as? [String: Any])
        #expect(last["disabledTools"] as? [String] == ["grep", "weather"])
        #expect(vm.pendingWrites == 0)
    }

    @Test("a failed write puts the switch back and reports the error")
    func failedWriteReverts() async throws {
        let server = SettingsPageTestServer(rows: [Self.row], postStatus: 500)
        let vm = await loaded(server)
        await vm.setEnabled("terminal", true)?.value
        #expect(vm.isEnabled("terminal") == false)
        #expect(vm.errorMessage != nil)
        #expect(vm.pendingWrites == 0)
    }

    @Test("nothing is written before a load, or for a switch already in that position")
    func noopWrites() async throws {
        let server = SettingsPageTestServer(rows: [Self.row])
        let vm = ToolsSettingsViewModel(store: server.makeStore())
        #expect(vm.setEnabled("grep", false) == nil)
        await vm.load()
        #expect(vm.setEnabled("grep", true) == nil)
        #expect(server.methods == ["GET"])
    }

    @Test("a failed load reports the error and leaves every switch inert")
    func failedLoad() async throws {
        let server = SettingsPageTestServer(
            rows: [#"{"type":"error","error":{"code":"INTERNAL","message":"down"}}"#], getStatus: 500)
        let vm = await loaded(server)
        #expect(vm.hasLoaded == false)
        #expect(vm.errorMessage != nil)
    }
}

/// The phone's copy of the desktop's tool lists, pinned. `Fixtures/desktop-tools.json` is a checked-in copy of
/// `TOOL_NAMES`, `LEGACY_TOOL_NAMES`, `TOOL_REGISTRY`, `TOOL_GROUPS` and `TOOL_CONFIG`'s keys; when the desktop
/// checkout sits beside this repo, the last test re-reads those sources and fails on any drift.
@Suite("Built-in Tools table")
struct BuiltinToolsTableTests {
    struct DesktopTools: Decodable, Equatable {
        struct Entry: Decodable, Equatable {
            let name: String
            let labelKey: String
            let descriptionKey: String
            let group: String
        }

        let toolNames: [String]
        let legacyNames: [String: String]
        let groups: [String]
        let registry: [Entry]
        let configured: [String]
    }

    private static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    private static let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
    private static let desktopConstants = repoRoot.deletingLastPathComponent()
        .appending(path: "exodus/packages/shared/src/constants")
    private static let desktopToolConfig = repoRoot.deletingLastPathComponent()
        .appending(path: "exodus/src/renderer/components/settings/settings-form/tool-config.tsx")

    private static func fixture() throws -> DesktopTools {
        let data = try Data(contentsOf: testsDirectory.appending(path: "Fixtures/desktop-tools.json"))
        return try JSONDecoder().decode(DesktopTools.self, from: data)
    }

    @Test("the switchable table is TOOL_REGISTRY: same tools, order, groups and catalog keys")
    func tableMatchesRegistry() throws {
        let desktop = try Self.fixture()
        let table = BuiltinTools.switchable.map {
            DesktopTools.Entry(name: $0.name, labelKey: $0.title.key, descriptionKey: $0.summary.key, group: $0.group.rawValue)
        }
        #expect(table == desktop.registry)
        #expect(BuiltinTools.Group.allCases.map(\.rawValue) == desktop.groups)
        #expect(Set(BuiltinTools.switchable.filter(\.configuredOnComputer).map(\.name)) == Set(desktop.configured))
    }

    @Test("every TOOL_NAMES value is known, and the legacy spellings are LEGACY_TOOL_NAMES")
    func namesMatchToolNames() throws {
        let desktop = try Self.fixture()
        #expect(BuiltinTools.allNames == Set(desktop.toolNames))
        #expect(Set(BuiltinTools.switchable.map(\.name)).isSubset(of: BuiltinTools.allNames))
        #expect(BuiltinTools.legacyNames == desktop.legacyNames)
    }

    @Test("a name the server holds that the table does not know is reported, once, in order")
    func unknownNamesAreReported() {
        #expect(BuiltinTools.unknownNames(in: ["grep", "brand_new", "webSearch", "call_mcp_tool", "brand_new", "x"])
            == ["brand_new", "x"])
    }

    @Test("every title and description key is in the app's catalog")
    func keysAreInCatalog() throws {
        let catalogURL = Self.repoRoot.appending(path: "Resources/App/Localizable.xcstrings")
        let catalog = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        let keys = BuiltinTools.switchable.flatMap { [$0.title.key, $0.summary.key] }
            + BuiltinTools.Group.allCases.map(\.title.key)
        for key in keys { #expect(strings[key] != nil, "\(key)") }
    }

    @Test(
        "the checked-in copy still matches the desktop's sources",
        .enabled(if: FileManager.default.fileExists(atPath: desktopConstants.appending(path: "tools.ts").path)))
    func fixtureMatchesDesktopSources() throws {
        let names = try String(contentsOf: Self.desktopConstants.appending(path: "tool-names.ts"), encoding: .utf8)
        let tools = try String(contentsOf: Self.desktopConstants.appending(path: "tools.ts"), encoding: .utf8)
        let config = try String(contentsOf: Self.desktopToolConfig, encoding: .utf8)

        let toolNamesBlock = try #require(names.firstRange(of: "export const TOOL_NAMES = {").map {
            names[$0.upperBound...].prefix { $0 != "}" }
        })
        var byKey: [String: String] = [:]
        for match in toolNamesBlock.matches(of: /(\w+): '([a-z_]+)'/) { byKey[String(match.1)] = String(match.2) }

        let legacyBlock = try #require(names.firstRange(of: "LEGACY_TOOL_NAMES").map { names[$0.upperBound...] })
        let legacyList = try #require(legacyBlock.firstRange(of: "] as const").map { legacyBlock[..<$0.lowerBound] })
        let legacy = Dictionary(
            uniqueKeysWithValues: legacyList.matches(of: /'(\w+)'/).map { (String($0.1), byKey[String($0.1)] ?? "?") })

        let registry = tools.matches(
            of: /key: TOOL_NAMES\.(\w+),\s*labelKey: '([^']+)',\s*descriptionKey: '([^']+)',\s*group: '([^']+)'/
        ).map {
            DesktopTools.Entry(
                name: byKey[String($0.1)] ?? "?", labelKey: "settings:\($0.2)", descriptionKey: "settings:\($0.3)",
                group: String($0.4))
        }
        let groupsStart = try #require(tools.firstRange(of: "export const TOOL_GROUPS"))
        let groupsList = try #require(tools[groupsStart.upperBound...].firstRange(of: "= ["))
        let groupsBlock = tools[groupsList.upperBound...].prefix { $0 != "]" }
        let configured = config.matches(of: /\[TOOL_NAMES\.(\w+)\]/).map { byKey[String($0.1)] ?? "?" }

        let live = DesktopTools(
            toolNames: byKey.values.sorted(), legacyNames: legacy,
            groups: groupsBlock.matches(of: /'([^']+)'/).map { String($0.1) }, registry: registry,
            configured: configured.sorted())
        #expect(!live.toolNames.isEmpty && !live.registry.isEmpty)
        #expect(live == (try Self.fixture()), "the desktop's tool lists changed: update Fixtures/desktop-tools.json and BuiltinTools")
    }
}
