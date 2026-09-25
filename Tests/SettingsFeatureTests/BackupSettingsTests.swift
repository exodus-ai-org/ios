import Foundation
import Models
import NetworkingKit
import Testing

@testable import SettingsFeature

@MainActor
@Suite("Backups")
struct BackupSettingsViewModelTests {
    private static let status = #"{"autoBackup":true,"lastBackupAt":"2026-09-23T03:00:01.004Z"}"#
    private static let statusAfter = #"{"autoBackup":true,"lastBackupAt":"2026-09-24T09:15:00.500Z"}"#
    private static let list = #"[{"name":"2026-09-23.tar.gz","size":1000,"createdAt":"2026-09-23T03:00:01.004Z"}]"#
    private static let listAfter = #"""
        [{"name":"2026-09-24.tar.gz","size":1200,"createdAt":"2026-09-24T09:15:00.500Z"},
         {"name":"2026-09-23.tar.gz","size":1000,"createdAt":"2026-09-23T03:00:01.004Z"}]
        """#
    private static let failure = #"{"type":"error","error":{"code":"INTERNAL","message":"disk full"}}"#

    private func server(now: [(Int, String)] = [(200, #"{"filePath":"/b/2026-09-24.tar.gz"}"#)])
        -> SettingsPageTestServer
    {
        let server = SettingsPageTestServer(rows: ["{}"])
        server.route("GET", "/api/v1/backup/status", [(200, Self.status), (200, Self.statusAfter)])
        server.route("GET", "/api/v1/backup/list", [(200, Self.list), (200, Self.listAfter)])
        server.route("POST", "/api/v1/backup/now", now)
        return server
    }

    private func loaded(_ server: SettingsPageTestServer) async -> BackupSettingsViewModel {
        let vm = BackupSettingsViewModel(apiClient: server.makeClient().0)
        await vm.load()
        return vm
    }

    @Test("load() reads the status and the stored backups")
    func loadReadsStatusAndList() async {
        let vm = await loaded(server())
        #expect(vm.loadState == .loaded)
        #expect(vm.status?.autoBackup == true)
        #expect(vm.status?.lastBackupDate == BackupInfo.date(from: "2026-09-23T03:00:01.004Z"))
        #expect(vm.backups.map(\.name) == ["2026-09-23.tar.gz"])
        #expect(vm.phase == .idle)
    }

    @Test("Back Up Now posts /backup/now, then re-reads status and list; settings are never written")
    func backUpNowThenRereads() async throws {
        let server = server()
        let vm = await loaded(server)
        let task = try #require(vm.backUpNow())
        #expect(vm.phase == .running)
        #expect(vm.backUpNow() == nil)
        await task.value
        #expect(vm.phase == .succeeded)
        #expect(vm.status?.lastBackupAt == "2026-09-24T09:15:00.500Z")
        #expect(vm.backups.count == 2)
        let requests = server.requests(under: "/api/v1")
        #expect(requests.filter { $0 == "POST /api/v1/backup/now" }.count == 1)
        #expect(requests.count == 5)
        #expect(requests[2] == "POST /api/v1/backup/now")
        #expect(Set(requests[3...]) == ["GET /api/v1/backup/status", "GET /api/v1/backup/list"])
        #expect(!requests.contains { $0.contains("/api/v1/settings") })
        #expect(server.timeout("POST", "/api/v1/backup/now") == 300)
    }

    @Test("a failed backup shows the server's message, and the status is still re-read")
    func failedBackup() async throws {
        let server = server(now: [(500, Self.failure)])
        let vm = await loaded(server)
        await vm.backUpNow()?.value
        #expect(vm.phase == .failed("disk full"))
        #expect(server.requests(under: "/api/v1/backup").last?.hasPrefix("GET ") == true)
        #expect(vm.status?.lastBackupAt == "2026-09-24T09:15:00.500Z")
    }

    @Test("a failed first load is an error state; a failed reload keeps the status and reports it")
    func loadFailures() async {
        let down = SettingsPageTestServer(rows: ["{}"])
        down.route("GET", "/api/v1/backup/status", [(500, Self.failure)])
        down.route("GET", "/api/v1/backup/list", [(200, Self.list)])
        let first = await loaded(down)
        #expect(first.loadState == .failed("disk full"))

        let flaky = SettingsPageTestServer(rows: ["{}"])
        flaky.route("GET", "/api/v1/backup/status", [(200, Self.status), (500, Self.failure)])
        flaky.route("GET", "/api/v1/backup/list", [(200, Self.list)])
        let second = await loaded(flaky)
        await second.load()
        #expect(second.loadState == .loaded)
        #expect(second.status?.lastBackupAt == "2026-09-23T03:00:01.004Z")
        #expect(second.refreshError == "disk full")
    }
}
