import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

@MainActor
@Suite("Memory")
struct MemorySettingsViewModelTests {
    /// Capture on, use in chats off, a threshold of 80 and a fresh tail saved when it counted messages (32).
    private static let row = #"""
        {"id":"global","lastBackupAt":"2026-09-18T12:00:00.000Z",
         "memory":{"autoCapture":true,"useInChat":false,"lcmEnabled":true,"contextWindowPercent":80,
           "freshTailSize":32,"futureKnob":"kept"}}
        """#

    /// Newest first, as the server orders them; one disabled, one with `isActive: null` (active on the desktop).
    private static let list = #"""
        [{"id":"t1","section":"topic","key":"Music","summary":"Bach","details":["Goldberg"],"isActive":true,
          "userId":"u","confidence":0.8,"source":"implicit","updatedAt":"2026-09-23T10:00:00.000Z"},
         {"id":"p1","section":"profile","key":"Setup","summary":"Mac","details":[],"isActive":null},
         {"id":"x1","section":"topic","key":"Running","summary":"","details":[],"isActive":false},
         {"id":"h1","section":"person","key":"Ada","summary":"Sister","details":null,"isActive":true}]
        """#

    private func loaded(
        _ server: SettingsPageTestServer, suite: String = #function
    ) async -> MemorySettingsViewModel {
        let client = server.makeClient(suite).0
        let vm = MemorySettingsViewModel(store: SettingsStore(apiClient: client), apiClient: client)
        await vm.load()
        return vm
    }

    private func server(row: String = row, list: String = list) -> SettingsPageTestServer {
        let server = SettingsPageTestServer(rows: [row])
        server.serve(memoryLists: [list])
        return server
    }

    // MARK: Settings

    @Test("pull to refresh re-reads the switches and the entries")
    func refreshRereadsBoth() async throws {
        let server = server()
        let vm = await loaded(server)
        server.serve(rows: [#"{"id":"global","memory":{"autoCapture":false,"useInChat":true}}"#])
        server.serve(memoryLists: ["[]"])
        await vm.refresh()
        #expect(vm.autoCapture == false)
        #expect(vm.useInChat)
        #expect(vm.entries.isEmpty)
        #expect(server.memoryRequests == ["GET /api/v1/memory", "GET /api/v1/memory"])
    }

    @Test("load() reads the switches, clamps the limits, and groups the list like the desktop")
    func loadReadsSettingsAndList() async throws {
        let server = server()
        let vm = await loaded(server)
        #expect(vm.hasLoadedSettings)
        #expect(vm.autoCapture && !vm.useInChat && vm.lcmEnabled)
        #expect(vm.contextWindowPercent == 80)
        #expect(vm.freshTailSize == 24)
        #expect(vm.listState == .loaded)
        #expect(vm.activeGroups.map(\.section) == [.profile, .topic, .person])
        #expect(vm.activeGroups.map { $0.entries.map(\.id) } == [["p1"], ["t1"], ["h1"]])
        #expect(vm.disabledEntries.map(\.id) == ["x1"])
        #expect(vm.entries.first { $0.id == "h1" }?.details == [])
        #expect(server.memoryRequests == ["GET /api/v1/memory"])
    }

    @Test(
        "a stored threshold reads as the desktop means it: unset is 75, else rounded into 50–95",
        arguments: [(nil, 75), (40.0, 50), (99.0, 95), (77.4, 77), (50.0, 50)] as [(Double?, Int)])
    func percentReading(raw: Double?, expected: Int) {
        #expect(MemorySettingsViewModel.percent(from: raw) == expected)
    }

    @Test(
        "a stored fresh tail reads like the desktop's freshTailRuns(): unset is 6, else clamped to 2–24 runs",
        arguments: [(nil, 6), (1.0, 2), (32.0, 24), (64.0, 24), (8.0, 8)] as [(Double?, Int)])
    func freshTailReading(raw: Double?, expected: Int) {
        #expect(MemorySettingsViewModel.freshTail(from: raw) == expected)
    }

    @Test("a switch is written at once over the column as the server holds it now, other keys kept")
    func switchIsReadModifyWrite() async throws {
        let server = server()
        let vm = await loaded(server)
        server.serve(rows: [
            #"{"id":"global","lastBackupAt":null,"memory":{"autoCapture":true,"useInChat":false,"freshTailSize":10,"futureKnob":"kept"}}"#
        ])
        await vm.setUseInChat(true)?.value
        #expect(server.methods == ["GET", "GET", "POST"])
        let body = try server.onlyPostBody()
        #expect(Set(body.keys) == ["id", "lastBackupAt", "memory"])
        #expect(body["lastBackupAt"] is NSNull)
        let memory = try #require(body["memory"] as? [String: Any])
        #expect(memory["useInChat"] as? Bool == true)
        #expect(memory["autoCapture"] as? Bool == true)
        #expect(memory["freshTailSize"] as? Int == 10)
        #expect(memory["futureKnob"] as? String == "kept")
        #expect(memory["contextWindowPercent"] == nil)
        #expect(vm.useInChat && vm.freshTailSize == 10)
    }

    @Test("limits are clamped before they are written: 120% becomes 95, 0 runs becomes 2")
    func limitsAreClamped() async throws {
        let server = server()
        let vm = await loaded(server)
        await vm.setContextWindowPercent(120)?.value
        #expect(vm.contextWindowPercent == 95)
        await vm.setFreshTailSize(0)?.value
        #expect(vm.freshTailSize == 2)
        let bodies = server.postBodies.compactMap { $0["memory"] as? [String: Any] }
        #expect(bodies.count == 2)
        #expect(bodies.first?["contextWindowPercent"] as? Int == 95)
        #expect(bodies.last?["freshTailSize"] as? Int == 2)
    }

    @Test("switching LCM off writes lcmEnabled and nothing else of the column changes")
    func lcmSwitch() async throws {
        let server = server()
        let vm = await loaded(server)
        await vm.setLcmEnabled(false)?.value
        let memory = try #require(try server.onlyPostBody()["memory"] as? [String: Any])
        #expect(memory["lcmEnabled"] as? Bool == false)
        #expect(memory["freshTailSize"] as? Int == 32)
        #expect(memory["contextWindowPercent"] as? Int == 80)
    }

    @Test("a failed write shows the column as the server holds it and reports the error")
    func failedSettingsWriteReverts() async throws {
        let server = SettingsPageTestServer(rows: [Self.row], postStatus: 500)
        server.serve(memoryLists: [Self.list])
        let vm = await loaded(server)
        await vm.setAutoCapture(false)?.value
        #expect(vm.autoCapture)
        #expect(vm.errorMessage != nil)
        #expect(vm.pendingWrites == 0)
    }

    @Test("nothing is written before the settings loaded")
    func noWriteBeforeLoad() async throws {
        let server = server()
        let client = server.makeClient().0
        let vm = MemorySettingsViewModel(store: SettingsStore(apiClient: client), apiClient: client)
        #expect(vm.setAutoCapture(false) == nil)
        #expect(vm.autoCapture)
        #expect(server.methods.isEmpty)
    }

    // MARK: Entries

    @Test("add posts the desktop's body, trimmed and with details one per line, then re-reads the list")
    func createPostsAndRereads() async throws {
        let server = server()
        let vm = await loaded(server)
        server.serve(memoryLists: [#"[{"id":"n1","section":"person","key":"Grace","summary":"","details":[]}]"#])
        let draft = MemoryDraft(section: .person, key: "  Grace ", summary: " Friend ", detailsText: "- Navy\n\n* COBOL \n")
        #expect(await vm.create(draft))
        #expect(server.memoryRequests == ["GET /api/v1/memory", "POST /api/v1/memory", "GET /api/v1/memory"])
        let body = try #require(server.lastMemoryBody("POST"))
        #expect(Set(body.keys) == ["section", "key", "summary", "details", "source"])
        #expect(body["section"] as? String == "person")
        #expect(body["key"] as? String == "Grace")
        #expect(body["summary"] as? String == "Friend")
        #expect(body["details"] as? [String] == ["Navy", "COBOL"])
        #expect(body["source"] as? String == "explicit")
        #expect(vm.entries.map(\.id) == ["n1"])
        #expect(vm.failure == nil)
    }

    @Test("a blank title is refused and nothing is sent")
    func blankTitleIsRefused() async throws {
        let server = server()
        let vm = await loaded(server)
        #expect(await vm.create(MemoryDraft(key: "  \n")) == false)
        let entry = try #require(vm.entries.first)
        var draft = MemoryDraft(entry: entry)
        draft.key = " "
        #expect(await vm.save(draft, for: entry) == false)
        #expect(vm.failure == .titleRequired)
        #expect(server.memoryRequests == ["GET /api/v1/memory"])
    }

    @Test("edit sends only the fields that changed, to the entry's path, then re-reads the list")
    func editPatchesChangedFields() async throws {
        let server = server()
        let vm = await loaded(server)
        let entry = try #require(vm.entries.first { $0.id == "t1" })
        var draft = MemoryDraft(entry: entry)
        draft.summary = "Bach and Pärt "
        draft.detailsText = "Goldberg\n- Tabula Rasa"
        #expect(await vm.save(draft, for: entry))
        #expect(server.memoryRequests == ["GET /api/v1/memory", "PATCH /api/v1/memory/t1", "GET /api/v1/memory"])
        let body = try #require(server.lastMemoryBody("PATCH"))
        #expect(Set(body.keys) == ["summary", "details"])
        #expect(body["summary"] as? String == "Bach and Pärt")
        #expect(body["details"] as? [String] == ["Goldberg", "Tabula Rasa"])
    }

    @Test("a renamed title is sent trimmed, and an unchanged draft sends nothing")
    func renameAndNoop() async throws {
        let server = server()
        let vm = await loaded(server)
        let entry = try #require(vm.entries.first { $0.id == "p1" })
        #expect(await vm.save(MemoryDraft(entry: entry), for: entry))
        #expect(server.memoryRequests == ["GET /api/v1/memory"])
        var draft = MemoryDraft(entry: entry)
        draft.key = " My setup "
        #expect(await vm.save(draft, for: entry))
        #expect(server.lastMemoryBody("PATCH").map { $0 as NSDictionary } == ["key": "My setup"] as NSDictionary)
    }

    @Test("disable and restore patch isActive alone")
    func disableAndRestore() async throws {
        let server = server()
        let vm = await loaded(server)
        let active = try #require(vm.entries.first { $0.id == "t1" })
        let disabled = try #require(vm.entries.first { $0.id == "x1" })
        #expect(await vm.setActive(active, false))
        #expect(server.lastMemoryBody("PATCH").map { $0 as NSDictionary } == ["isActive": false] as NSDictionary)
        #expect(await vm.setActive(disabled, true))
        #expect(server.lastMemoryBody("PATCH").map { $0 as NSDictionary } == ["isActive": true] as NSDictionary)
        #expect(
            server.memoryRequests == [
                "GET /api/v1/memory", "PATCH /api/v1/memory/t1", "GET /api/v1/memory", "PATCH /api/v1/memory/x1",
                "GET /api/v1/memory",
            ])
    }

    @Test("delete needs the confirmation: a request alone or a cancel sends nothing; confirming deletes for good")
    func deleteRequiresConfirm() async throws {
        let server = server()
        let vm = await loaded(server)
        let entry = try #require(vm.entries.first { $0.id == "h1" })
        vm.requestDelete(entry)
        #expect(vm.pendingDeletion == entry)
        vm.cancelDelete()
        #expect(vm.pendingDeletion == nil)
        #expect(vm.confirmDelete() == nil)
        #expect(server.memoryRequests == ["GET /api/v1/memory"])

        server.serve(memoryLists: ["[]"])
        vm.requestDelete(entry)
        let deletion = vm.confirmDelete()
        #expect(vm.pendingDeletion == nil)
        #expect(await deletion?.value == true)
        #expect(server.memoryRequests == ["GET /api/v1/memory", "DELETE /api/v1/memory/h1?hard=true", "GET /api/v1/memory"])
        #expect(vm.pendingDeletion == nil)
        #expect(vm.entries.isEmpty)
    }

    @Test("a failed write reports which operation failed and still re-reads the list")
    func failedEntryWrites() async throws {
        let server = server()
        let vm = await loaded(server)
        let entry = try #require(vm.entries.first)
        server.setMemoryStatus("DELETE", 500)
        vm.requestDelete(entry)
        #expect(await vm.confirmDelete()?.value == false)
        #expect(vm.failure == .delete("memory down"))
        server.setMemoryStatus("POST", 500)
        #expect(await vm.create(MemoryDraft(key: "X")) == false)
        #expect(vm.failure == .create("memory down"))
        server.setMemoryStatus("PATCH", 500)
        #expect(await vm.setActive(entry, false) == false)
        #expect(vm.failure == .save("memory down"))
        #expect(server.memoryRequests.filter { $0 == "GET /api/v1/memory" }.count == 4)
        #expect(vm.entries.count == 4)
    }

    @Test("a failed list load shows the error state with the settings still usable; a retry recovers")
    func failedListLoad() async throws {
        let server = server()
        server.setMemoryStatus("GET", 500)
        let vm = await loaded(server)
        #expect(vm.hasLoadedSettings)
        #expect(vm.listState == .failed("memory down"))
        #expect(vm.entries.isEmpty)
        server.setMemoryStatus("GET", 200)
        await vm.loadList()
        #expect(vm.listState == .loaded)
        #expect(vm.entries.count == 4)
    }

    @Test("a failed re-read keeps the list on screen and says so")
    func failedRereadKeepsList() async throws {
        let server = server()
        let vm = await loaded(server)
        server.setMemoryStatus("GET", 500)
        await vm.loadList()
        #expect(vm.listState == .loaded)
        #expect(vm.entries.count == 4)
        #expect(vm.failure == .load("memory down"))
    }

    @Test("an empty list is loaded, not failed")
    func emptyList() async throws {
        let server = server(list: "[]")
        let vm = await loaded(server)
        #expect(vm.listState == .loaded)
        #expect(vm.entries.isEmpty && vm.activeGroups.isEmpty && vm.disabledEntries.isEmpty)
    }

    @Test(
        "details parse like the desktop's detailsFromText",
        arguments: [
            ("- a\n* b\n\n  c  \n-", ["a", "b", "c"]),
            ("  - kept dash", ["- kept dash"]),
            ("one\r\ntwo", ["one", "two"]),
            ("", []),
        ] as [(String, [String])])
    func detailsParsing(text: String, expected: [String]) {
        #expect(MemoryDraft.details(from: text) == expected)
    }
}
