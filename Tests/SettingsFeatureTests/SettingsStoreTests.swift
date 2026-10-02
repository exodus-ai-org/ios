import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import SettingsFeature

private final class StoreMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StoreMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// A fake `/api/v1/settings`: serves `rows` in turn to successive GETs (the last one repeats) and logs every
/// request, in order, with its body. The handler runs on a URLProtocol thread, so everything sits behind a lock.
private final class FakeSettingsServer: Sendable {
    private struct State {
        var rows: [String]
        var log: [(method: String, body: Data)] = []
        var postStatus = 200
    }

    private let state: Mutex<State>

    init(rows: [String], postStatus: Int = 200, getStatus: Int = 200) {
        state = Mutex(State(rows: rows, postStatus: postStatus))
        StoreMockURLProtocol.handler = { [self] request in
            let method = request.httpMethod ?? ""
            let body = try request.bodyStreamData()
            return state.withLock { state in
                state.log.append((method, body))
                guard request.url?.path == "/api/v1/settings" else { return (404, Data()) }
                if method == "POST" { return (state.postStatus, Data("{}".utf8)) }
                let row = state.rows.count > 1 ? state.rows.removeFirst() : state.rows[0]
                return (getStatus, Data(row.utf8))
            }
        }
    }

    var methods: [String] { state.withLock { $0.log.map(\.method) } }

    func onlyPostBody() throws -> [String: Any] {
        let posts = state.withLock { $0.log.filter { $0.method == "POST" } }
        try #require(posts.count == 1)
        return try #require(try JSONSerialization.jsonObject(with: posts[0].body) as? [String: Any])
    }
}

@MainActor
@Suite("SettingsStore", .serialized)
struct SettingsStoreTests {
    private func makeStore(_ suite: String = #function) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        return SettingsStore(apiClient: APIClient(session: StoreMockURLProtocol.makeSession(), serverConfig: config))
    }

    private static let row = #"""
        {"id":"global","lastBackupAt":"2026-09-18T12:00:00.000Z",
         "tools":{"disabledTools":["web_search"]},"memory":{"autoCapture":true},
         "providers":{"anthropicApiKey":"sk-ant-1"}}
        """#

    @Test("load() reads the row and keeps it as the snapshot")
    func loadReadsTheRow() async throws {
        let server = FakeSettingsServer(rows: [Self.row])
        let store = makeStore()
        let row = try await store.load()
        #expect(row.tools?.disabledTools == ["web_search"])
        #expect(store.snapshot?.id == "global")
        #expect(server.methods == ["GET"])
    }

    @Test("a patch posts exactly id, lastBackupAt and the one column")
    func patchBodyHasExactlyTheColumn() async throws {
        let server = FakeSettingsServer(rows: [Self.row])
        let store = makeStore()
        try await store.patch(.memory, value: MemorySettings(autoCapture: false))
        let body = try server.onlyPostBody()
        #expect(Set(body.keys) == ["id", "lastBackupAt", "memory"])
        #expect(body["id"] as? String == "global")
        #expect((body["memory"] as? [String: Any])?["autoCapture"] as? Bool == false)
    }

    @Test("a lastBackupAt the server holds is echoed as the same string")
    func lastBackupAtStringIsEchoed() async throws {
        let server = FakeSettingsServer(rows: [Self.row])
        try await makeStore().patch(.tools, value: ToolsSettings())
        #expect(try server.onlyPostBody()["lastBackupAt"] as? String == "2026-09-18T12:00:00.000Z")
    }

    @Test(
        "a lastBackupAt that is null or absent is echoed as JSON null",
        arguments: [#"{"id":"global","lastBackupAt":null}"#, #"{"id":"global"}"#])
    func nullLastBackupAtIsEchoedAsNull(row: String) async throws {
        let server = FakeSettingsServer(rows: [row])
        try await makeStore().patch(.tools, value: ToolsSettings())
        let body = try server.onlyPostBody()
        #expect(body.keys.contains("lastBackupAt"))
        #expect(body["lastBackupAt"] is NSNull)
    }

    @Test("a write re-reads the row first and echoes what it reads now, not what was loaded earlier")
    func writeReReadsBeforePosting() async throws {
        // The desktop backed up between the page's load and its save.
        let server = FakeSettingsServer(rows: [
            #"{"id":"global","lastBackupAt":null}"#,
            #"{"id":"global","lastBackupAt":"2026-09-24T08:00:00.000Z"}"#,
        ])
        let store = makeStore()
        try await store.load()
        try await store.patch(.tools, value: ToolsSettings(disabledTools: ["grep"]))
        #expect(server.methods == ["GET", "GET", "POST"])
        #expect(try server.onlyPostBody()["lastBackupAt"] as? String == "2026-09-24T08:00:00.000Z")
    }

    @Test("update() edits the column as the server holds it now, keeping what the page did not touch")
    func updateIsReadModifyWrite() async throws {
        let server = FakeSettingsServer(rows: [
            #"{"id":"global","tools":{"disabledTools":["web_search"]}}"#,
            // Since the load, the desktop switched off `terminal` and wrote a key this app does not model.
            #"{"id":"global","tools":{"disabledTools":["web_search","terminal"],"futureFlag":true}}"#,
        ])
        let store = makeStore()
        try await store.load()
        let written = try await store.update(.tools) { $0.disabledTools.append("grep") }
        #expect(written.disabledTools == ["web_search", "terminal", "grep"])
        #expect(server.methods == ["GET", "GET", "POST"])
        let tools = try #require(try server.onlyPostBody()["tools"] as? [String: Any])
        #expect(tools["disabledTools"] as? [String] == ["web_search", "terminal", "grep"])
        #expect(tools["futureFlag"] as? Bool == true)
        #expect(store.snapshot?.tools?.disabledTools == ["web_search", "terminal", "grep"])
    }

    @Test("update() starts from the column's empty value when the row has none")
    func updateStartsFromEmpty() async throws {
        let server = FakeSettingsServer(rows: [#"{"id":"global"}"#])
        try await makeStore().update(.memory) { $0.useInChat = false }
        let memory = try #require(try server.onlyPostBody()["memory"] as? [String: Any])
        #expect(memory["useInChat"] as? Bool == false)
        #expect(memory["autoCapture"] as? Bool == true)
    }

    @Test("several columns go in one request")
    func multiColumnPatch() async throws {
        let server = FakeSettingsServer(rows: [Self.row])
        let store = makeStore()
        try await store.patch([
            SettingsColumn.tools.assigning(ToolsSettings()),
            SettingsColumn.personality.assigning(PersonalitySettings(nickname: "Y")),
        ])
        let body = try server.onlyPostBody()
        #expect(Set(body.keys) == ["id", "lastBackupAt", "tools", "personality"])
        #expect(store.snapshot?.personality?.nickname == "Y")
        #expect(store.snapshot?.tools?.disabledTools == [])
        // Held as the computer shows it, never in plaintext.
        #expect(store.snapshot?.providers?.anthropicApiKey == "••••")
    }

    @Test("when the re-read fails nothing is posted")
    func failedReReadPostsNothing() async throws {
        let server = FakeSettingsServer(rows: [#"{"type":"error","error":{"code":"INTERNAL","message":"down"}}"#], getStatus: 500)
        await #expect(throws: HTTPError.self) {
            try await makeStore().patch(.tools, value: ToolsSettings())
        }
        #expect(server.methods == ["GET"])
    }

    @Test("a column the phone cannot read is never written: the write is refused and nothing is posted")
    func unreadableColumnIsNotWritten() async throws {
        let server = FakeSettingsServer(rows: [
            #"{"id":"global","providers":{"anthropicApiKey":"sk-ant-1","openaiApiKey":5},"tools":{"disabledTools":[]}}"#
        ])
        let store = makeStore()
        await #expect(throws: SettingsStoreError.unreadableColumn("providers")) {
            try await store.update(.providers) { $0.googleGeminiApiKey = "AIza" }
        }
        await #expect(throws: SettingsStoreError.unreadableColumn("providers")) {
            try await store.load(requiring: ["providerConfig", "providers"])
        }
        #expect(server.methods == ["GET", "GET"])
        // Other columns of the same row are still written.
        try await store.update(.tools) { $0.disabledTools = ["grep"] }
        #expect(Set(try server.onlyPostBody().keys) == ["id", "lastBackupAt", "tools"])
    }

    @Test("a failed post throws and leaves the snapshot as read")
    func failedPostKeepsSnapshot() async throws {
        _ = FakeSettingsServer(rows: [Self.row], postStatus: 500)
        let store = makeStore()
        await #expect(throws: HTTPError.self) {
            try await store.patch(.tools, value: ToolsSettings(disabledTools: ["grep"]))
        }
        #expect(store.snapshot?.tools?.disabledTools == ["web_search"])
    }
}

@Suite("Settings hub")
struct SettingsHubTests {
    @Test("every page has exactly one row")
    func everyPageHasOneRow() {
        for page in SettingsPage.allCases {
            #expect(SettingsHubRow.all.filter { $0.page == page }.count == 1, "\(page)")
        }
        #expect(SettingsHubRow.all.count == SettingsPage.allCases.count)
    }

    @Test("the groups run Computer, AI, Behaviour, Data, and only groups with a page have rows")
    func groups() {
        #expect(SettingsGroup.allCases == [.general, .computer, .ai, .behaviour, .data])
        #expect(SettingsHubRow.rows(in: .general).map(\.page) == [.colorTone, .workingCards])
        #expect(SettingsHubRow.rows(in: .computer).map(\.page) == [.connection])
        #expect(SettingsHubRow.rows(in: .ai).map(\.page) == [.providers, .tools, .skills, .mcp])
        #expect(SettingsHubRow.rows(in: .behaviour).map(\.page) == [.personality, .memory])
        #expect(SettingsHubRow.rows(in: .data).map(\.page) == [.profile, .backup])
    }
}

extension URLRequest {
    fileprivate func bodyStreamData() throws -> Data {
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
