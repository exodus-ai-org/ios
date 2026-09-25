import Foundation
import Models
import Synchronization
import Testing

@testable import NetworkingKit

/// Uses `MockURLProtocol`, whose handler is process-global — hence `.serialized`.
@Suite("ServerConnection", .serialized)
struct ServerConnectionTests {
    private let stored = PairedServer(
        hosts: ["10.0.0.2", "mac.local"], port: 63129, fingerprint: "PIN", name: "Mac",
        deviceId: "dev-1", token: "TOKEN")

    private let link = PairingLink(
        string: "exodus://pair?h=10.0.0.2%2Cmac.local&p=63129&c=CODE&f=PIN&n=Mac")!

    @Test("unpaired, it contributes nothing — the app uses the manual address")
    func unpaired() {
        let connection = ServerConnection(store: InMemoryCredentialStore())
        #expect(!connection.isPaired)
        #expect(!connection.isUnlocked)
        #expect(connection.baseURLString == nil)
        #expect(connection.authorization == nil)
        #expect(connection.pin == nil)
    }

    @Test("paired but locked, it still gives nothing away until unlocked")
    func lockedUntilUnlocked() async throws {
        let connection = ServerConnection(store: InMemoryCredentialStore(stored))
        #expect(connection.isPaired)
        #expect(!connection.isUnlocked)
        #expect(connection.authorization == nil)

        try await connection.unlock(reason: "test")
        #expect(connection.isUnlocked)
        #expect(connection.baseURLString == "https://10.0.0.2:63129")
        #expect(connection.authorization == "Bearer TOKEN")
        #expect(connection.pin == "PIN")
        #expect(connection.serverName == "Mac")
    }

    @Test("the pinned session caches nothing: settings and MCP responses never reach the disk")
    func sessionHasNoDiskCache() {
        let configuration = ServerConnection(store: InMemoryCredentialStore()).session.configuration
        #expect((configuration.urlCache?.diskCapacity ?? 0) == 0)
        #expect((configuration.urlCache?.memoryCapacity ?? 0) == 0)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForRequest == URLSessionConfiguration.default.timeoutIntervalForRequest)
    }

    @Test("lock() forgets the token but not the pairing")
    func lockForgets() async throws {
        let connection = ServerConnection(store: InMemoryCredentialStore(stored))
        try await connection.unlock(reason: "test")
        connection.lock()

        #expect(connection.isPaired)
        #expect(!connection.isUnlocked)
        #expect(connection.authorization == nil)
        #expect(connection.baseURLString == nil)
    }

    @Test("unpair() forgets everything")
    func unpairClears() async throws {
        let store = InMemoryCredentialStore(stored)
        let connection = ServerConnection(store: store)
        try await connection.unlock(reason: "test")
        connection.unpair()

        #expect(!connection.isPaired)
        #expect(!store.exists)
        #expect(connection.authorization == nil)
    }

    @Test("unpair() tells whoever keeps things from the computer, once per unpair; lock() does not")
    func unpairNotifies() {
        let calls = Mutex(0)
        let connection = ServerConnection(store: InMemoryCredentialStore(stored))
        connection.onComputerChange { calls.withLock { $0 += 1 } }
        connection.lock()
        #expect(calls.withLock { $0 } == 0)
        connection.unpair()
        #expect(calls.withLock { $0 } == 1)
    }

    @Test("unlockComputer() is a no-op on an unpaired connection — no request sent")
    func unlockComputerUnpaired() async throws {
        let connection = ServerConnection(store: InMemoryCredentialStore())
        let seen = Mutex<Int>(0)
        MockURLProtocol.handler = { _ in
            seen.withLock { $0 += 1 }
            return (200, Data())
        }

        let unlocked = await connection.unlockComputer(session: MockURLProtocol.makeSession())
        #expect(!unlocked)
        #expect(seen.withLock { $0 } == 0)
    }

    @Test("unlockComputer() posts the token to /api/v1/lock/unlock and reports success on 2xx")
    func unlockComputerSucceeds() async throws {
        let connection = ServerConnection(store: InMemoryCredentialStore(stored))
        try await connection.unlock(reason: "test")
        let seen = Mutex<(url: String, authorization: String?)?>(nil)
        MockURLProtocol.handler = { request in
            seen.withLock {
                $0 = (
                    request.url?.absoluteString ?? "",
                    request.value(forHTTPHeaderField: "Authorization")
                )
            }
            return (200, Data(#"{"locked":false}"#.utf8))
        }

        let unlocked = await connection.unlockComputer(session: MockURLProtocol.makeSession())
        #expect(unlocked)
        let request = try #require(seen.withLock { $0 })
        #expect(request.url == "https://10.0.0.2:63129/api/v1/lock/unlock")
        #expect(request.authorization == "Bearer TOKEN")
    }

    @Test("unlockComputer() reports failure on a non-2xx, and on a transport error")
    func unlockComputerFails() async throws {
        let connection = ServerConnection(store: InMemoryCredentialStore(stored))
        try await connection.unlock(reason: "test")
        MockURLProtocol.handler = { _ in (500, Data()) }
        #expect(await connection.unlockComputer(session: MockURLProtocol.makeSession()) == false)

        MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        #expect(await connection.unlockComputer(session: MockURLProtocol.makeSession()) == false)
    }

    @Test("unlockComputer() reads the token first (Face ID) when it isn't already in memory")
    func unlockComputerReadsTheTokenFirst() async throws {
        let connection = ServerConnection(store: InMemoryCredentialStore(stored))
        #expect(!connection.isUnlocked)
        MockURLProtocol.handler = { _ in (200, Data(#"{"locked":false}"#.utf8)) }

        let unlocked = await connection.unlockComputer(session: MockURLProtocol.makeSession())
        #expect(unlocked)
        #expect(connection.isUnlocked)
    }

    @Test("remembers the address that answered, and tries it first from then on")
    func remembersReachableHost() async throws {
        let store = InMemoryCredentialStore(stored)
        let connection = ServerConnection(store: store)
        try await connection.unlock(reason: "test")

        connection.noteReachable(host: "mac.local")
        #expect(connection.baseURLString == "https://mac.local:63129")
        #expect(try await store.load(reason: "test")?.lastGoodHost == "mac.local")

        // An address the computer never advertised is not adopted.
        connection.noteReachable(host: "evil.example")
        #expect(connection.baseURLString == "https://mac.local:63129")
    }

    @Test("pairing posts the code, stores the token, and leaves the connection unlocked")
    func pairs() async throws {
        let store = InMemoryCredentialStore()
        let connection = ServerConnection(store: store)
        let changes = Mutex(0)
        connection.onComputerChange { changes.withLock { $0 += 1 } }
        let seen = Mutex<(url: String, body: [String: String])?>(nil)
        MockURLProtocol.handler = { request in
            let body = request.httpBodyStream.map { stream -> Data in
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                return data
            } ?? request.httpBody ?? Data()
            let json = (try? JSONDecoder().decode([String: String].self, from: body)) ?? [:]
            seen.withLock { $0 = (request.url?.absoluteString ?? "", json) }
            return (200, Data(#"{"deviceId":"dev-9","token":"NEW-TOKEN"}"#.utf8))
        }

        try await connection.pair(link, deviceName: "Test iPhone", session: MockURLProtocol.makeSession())
        #expect(changes.withLock { $0 } == 1, "a new computer: what was kept from the old one goes")

        let request = try #require(seen.withLock { $0 })
        #expect(request.url == "https://10.0.0.2:63129/api/v1/pair")
        #expect(request.body == ["code": "CODE", "deviceName": "Test iPhone"])
        #expect(connection.isUnlocked)
        #expect(connection.authorization == "Bearer NEW-TOKEN")
        #expect(connection.pin == "PIN")
        let saved = try #require(try await store.load(reason: "test"))
        #expect(saved.token == "NEW-TOKEN")
        #expect(saved.hosts == ["10.0.0.2", "mac.local"])
        #expect(saved.lastGoodHost == "10.0.0.2")
    }

    @Test("a refused code pairs nothing and says why")
    func refusedCode() async throws {
        let store = InMemoryCredentialStore()
        let connection = ServerConnection(store: store)
        MockURLProtocol.handler = { _ in (403, Data(#"{"type":"error"}"#.utf8)) }

        await #expect(throws: HTTPError.self) {
            try await connection.pair(link, deviceName: "iPhone", session: MockURLProtocol.makeSession())
        }
        #expect(!store.exists)
        #expect(!connection.isUnlocked)
        // The pin it trusted while trying is gone again.
        #expect(connection.pin == nil)
    }

    @Test("the config store sends requests to the paired computer once unlocked")
    func configStoreFollowsConnection() async throws {
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        #expect(config.baseURLString == "http://localhost:60223")
        #expect(config.authorization == nil)

        let connection = ServerConnection(store: InMemoryCredentialStore(stored))
        config.connection = connection
        // Paired but locked: still the manual address, still no token.
        #expect(config.baseURLString == "http://localhost:60223")

        try await connection.unlock(reason: "test")
        #expect(config.baseURLString == "https://10.0.0.2:63129")
        #expect(config.authorization == "Bearer TOKEN")
        #expect(config.manualBaseURLString == "http://localhost:60223")
    }
}

@Suite("APIClient with a paired computer", .serialized)
struct PairedAPIClientTests {
    private struct Empty: Decodable {}

    private func makePairedClient() async throws -> (APIClient, ServerConnection, InMemoryCredentialStore) {
        let store = InMemoryCredentialStore(
            PairedServer(
                hosts: ["10.0.0.2"], port: 63129, fingerprint: "PIN", name: "Mac",
                deviceId: "dev-1", token: "TOKEN"))
        let connection = ServerConnection(store: store)
        try await connection.unlock(reason: "test")
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        config.connection = connection
        return (APIClient(session: MockURLProtocol.makeSession(), serverConfig: config), connection, store)
    }

    @Test("sends its token to the paired computer, over https")
    func sendsToken() async throws {
        let (client, _, _) = try await makePairedClient()
        let seen = Mutex<(String, String?)?>(nil)
        MockURLProtocol.handler = { request in
            seen.withLock {
                $0 = (request.url?.absoluteString ?? "", request.value(forHTTPHeaderField: "Authorization"))
            }
            return (200, Data("{}".utf8))
        }

        let _: Empty = try await client.get("/api/v1/history")

        let (url, authorization) = try #require(seen.withLock { $0 })
        #expect(url == "https://10.0.0.2:63129/api/v1/history")
        #expect(authorization == "Bearer TOKEN")
    }

    @Test("a 401 means revoked: the pairing is forgotten, so the app returns to pairing")
    func unauthorizedUnpairs() async throws {
        let (client, connection, store) = try await makePairedClient()
        MockURLProtocol.handler = { _ in
            (401, Data(#"{"type":"error","error":{"code":"UNAUTHORIZED","message":"Pair this device"}}"#.utf8))
        }

        await #expect(throws: HTTPError.self) {
            let _: Empty = try await client.get("/api/v1/history")
        }
        #expect(!connection.isPaired)
        #expect(!store.exists)
    }

    @Test("data(_:) returns the raw bytes, with the token, from the paired computer")
    func rawBytes() async throws {
        let (client, _, _) = try await makePairedClient()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
        let seen = Mutex<(String, String?)?>(nil)
        MockURLProtocol.handler = { request in
            seen.withLock {
                $0 = (request.url?.absoluteString ?? "", request.value(forHTTPHeaderField: "Authorization"))
            }
            return (200, bytes)
        }

        let data = try await client.data("/api/v1/media/c1/a.png")

        #expect(data == bytes)
        let (url, authorization) = try #require(seen.withLock { $0 })
        #expect(url == "https://10.0.0.2:63129/api/v1/media/c1/a.png")
        #expect(authorization == "Bearer TOKEN")
    }

    @Test("data(_:) throws the server's status: 404 keeps the pairing, 401 forgets it")
    func rawBytesErrors() async throws {
        let (client, connection, _) = try await makePairedClient()
        MockURLProtocol.handler = { _ in (404, Data(#"{"type":"error","error":{"code":"NOT_FOUND","message":"gone"}}"#.utf8)) }
        do {
            _ = try await client.data("/api/v1/media/c1/a.png")
            Issue.record("expected a 404")
        } catch let error as HTTPError {
            #expect(error.statusCode == 404)
        }
        #expect(connection.isPaired)

        MockURLProtocol.handler = { _ in (401, Data()) }
        do {
            _ = try await client.data("/api/v1/media/c1/a.png")
            Issue.record("expected a 401")
        } catch let error as HTTPError {
            #expect(error.statusCode == 401)
        }
        #expect(!connection.isPaired)
    }

    @Test("an unpaired client sends no Authorization header at all")
    func unpairedSendsNoToken() async throws {
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let client = APIClient(session: MockURLProtocol.makeSession(), serverConfig: config)
        let seen = Mutex<String??>(nil)
        MockURLProtocol.handler = { request in
            seen.withLock { $0 = .some(request.value(forHTTPHeaderField: "Authorization")) }
            return (200, Data("{}".utf8))
        }

        let _: Empty = try await client.get("/api/v1/history")
        #expect(try #require(seen.withLock { $0 }) == nil)
    }
}

/// The computer's own lock (a separate feature from `UnlockGate`'s: that one guards this
/// device's own token, this one is the computer refusing all `/api/*` access — see
/// exodus's `src/main/lib/server/middlewares/lock-gate.ts`). A paired, already-unlocked
/// client answers it by calling the computer's `POST /api/v1/lock/unlock` and retrying —
/// no fresh Face ID, because holding a valid token already proves who this device is.
@Suite("APIClient: the paired computer's own lock", .serialized)
struct AppLockedRetryTests {
    private struct Empty: Decodable {}
    private static let appLocked = #"{"type":"error","error":{"code":"APP_LOCKED","message":"Application is locked"}}"#

    private func makePairedClient() async throws -> (APIClient, ServerConnection, InMemoryCredentialStore) {
        let store = InMemoryCredentialStore(
            PairedServer(
                hosts: ["10.0.0.2"], port: 63129, fingerprint: "PIN", name: "Mac",
                deviceId: "dev-1", token: "TOKEN"))
        let connection = ServerConnection(store: store)
        try await connection.unlock(reason: "test")
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        config.connection = connection
        return (APIClient(session: MockURLProtocol.makeSession(), serverConfig: config), connection, store)
    }

    @Test("a 423 unlocks the computer and retries the same request once, succeeding")
    func unlocksAndRetries() async throws {
        let (client, connection, _) = try await makePairedClient()
        let seen = Mutex<[String]>([])  // "METHOD path"
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? ""
            seen.withLock { $0.append("\(method) \(path)") }
            if path == "/api/v1/history" {
                let historyCalls = seen.withLock { $0.filter { $0.hasSuffix("/api/v1/history") }.count }
                if historyCalls == 1 { return (423, Data(Self.appLocked.utf8)) }
                return (200, Data("{}".utf8))
            }
            if path == "/api/v1/lock/unlock" {
                return (200, Data(#"{"locked":false}"#.utf8))
            }
            return (404, Data())
        }

        let _: Empty = try await client.get("/api/v1/history")

        #expect(seen.withLock { $0 } == [
            "GET /api/v1/history",
            "POST /api/v1/lock/unlock",
            "GET /api/v1/history",
        ])
        // Already unlocked before the 423 (see `makePairedClient`), and still is: no re-prompt.
        #expect(connection.isUnlocked)
    }

    @Test("already unlocked, it never prompts Face ID again — straight to the unlock call")
    func doesNotRepromptWhenAlreadyUnlocked() async throws {
        let store = CountingCredentialStore(
            PairedServer(
                hosts: ["10.0.0.2"], port: 63129, fingerprint: "PIN", name: "Mac",
                deviceId: "dev-1", token: "TOKEN"))
        let connection = ServerConnection(store: store)
        try await connection.unlock(reason: "test")
        let loadCallsAfterUnlock = store.loadCount
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        config.connection = connection
        let client = APIClient(session: MockURLProtocol.makeSession(), serverConfig: config)
        let historyCalls = Mutex<Int>(0)
        MockURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/history" {
                let calls = historyCalls.withLock { $0 += 1; return $0 }
                if calls == 1 { return (423, Data(Self.appLocked.utf8)) }
                return (200, Data("{}".utf8))
            }
            return (200, Data(#"{"locked":false}"#.utf8))
        }

        let _: Empty = try await client.get("/api/v1/history")
        // Reading the token again (a fresh `load(reason:)`) is the Face ID prompt; unchanged
        // means the retry used the token `unlock(reason:)` already put in memory above.
        #expect(store.loadCount == loadCallsAfterUnlock)
    }

    @Test("the unlock call failing surfaces the original locked error, not a new one")
    func unlockFailureSurfacesTheOriginalError() async throws {
        let (client, _, _) = try await makePairedClient()
        MockURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/lock/unlock" {
                return (500, Data(#"{"type":"error","error":{"code":"X","message":"boom"}}"#.utf8))
            }
            return (423, Data(Self.appLocked.utf8))
        }

        await #expect(throws: HTTPError(statusCode: 423, code: "APP_LOCKED", message: "Application is locked")) {
            let _: Empty = try await client.get("/api/v1/history")
        }
    }

    @Test("an unpaired client gets the original locked error, with no unlock attempt")
    func unpairedGetsTheOriginalError() async throws {
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        config.connection = ServerConnection(store: InMemoryCredentialStore())
        let client = APIClient(session: MockURLProtocol.makeSession(), serverConfig: config)
        let seen = Mutex<[String]>([])
        MockURLProtocol.handler = { request in
            seen.withLock { $0.append(request.url?.path ?? "") }
            return (423, Data(Self.appLocked.utf8))
        }

        await #expect(throws: HTTPError.self) {
            let _: Empty = try await client.get("/api/v1/history")
        }
        // The manual address (unpaired) was tried once; nothing under /api/v1/lock.
        #expect(seen.withLock { $0 } == ["/api/v1/history"])
    }
}

@Suite("APIClient host failover", .serialized)
struct HostFailoverTests {
    private struct Empty: Decodable {}

    private func makeClient() async throws -> (APIClient, InMemoryCredentialStore) {
        let store = InMemoryCredentialStore(
            PairedServer(
                hosts: ["10.0.0.2", "100.64.0.7"], port: 63129, fingerprint: "PIN", name: "Mac",
                deviceId: "dev-1", token: "TOKEN"))
        let connection = ServerConnection(store: store)
        try await connection.unlock(reason: "test")
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        config.connection = connection
        return (APIClient(session: MockURLProtocol.makeSession(), serverConfig: config), store)
    }

    @Test("falls over to the next address when the first is unreachable, and remembers it")
    func failsOver() async throws {
        let (client, store) = try await makeClient()
        let hosts = Mutex<[String]>([])
        MockURLProtocol.handler = { request in
            let host = request.url?.host ?? ""
            hosts.withLock { $0.append(host) }
            if host == "10.0.0.2" { throw URLError(.cannotConnectToHost) }
            return (200, Data("{}".utf8))
        }

        let _: Empty = try await client.get("/api/v1/history")

        #expect(hosts.withLock { $0 } == ["10.0.0.2", "100.64.0.7"])
        #expect(try await store.load(reason: "test")?.lastGoodHost == "100.64.0.7")

        // Next time, the address that answered goes first.
        hosts.withLock { $0 = [] }
        let _: Empty = try await client.get("/api/v1/history")
        #expect(hosts.withLock { $0 } == ["100.64.0.7"])
    }

    @Test("does not fall over on an answer — a 500 is the computer's, not the address's")
    func serverErrorIsNotFailover() async throws {
        let (client, _) = try await makeClient()
        let hosts = Mutex<[String]>([])
        MockURLProtocol.handler = { request in
            hosts.withLock { $0.append(request.url?.host ?? "") }
            return (500, Data(#"{"type":"error","error":{"code":"X","message":"boom"}}"#.utf8))
        }

        await #expect(throws: HTTPError.self) {
            let _: Empty = try await client.get("/api/v1/history")
        }
        #expect(hosts.withLock { $0 } == ["10.0.0.2"])
    }

    @Test("reports the last address's error when none answers")
    func allUnreachable() async throws {
        let (client, _) = try await makeClient()
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }

        await #expect(throws: URLError.self) {
            let _: Empty = try await client.get("/api/v1/history")
        }
    }

    private struct Note: Encodable { let text: String }

    private final class HostLog: Sendable {
        let hosts = Mutex<[String]>([])
        var all: [String] { hosts.withLock { $0 } }
    }

    /// Every request's host, the first address failing with `error`.
    private func hostsLog(firstFailsWith error: URLError.Code) -> HostLog {
        let log = HostLog()
        MockURLProtocol.handler = { request in
            let host = request.url?.host ?? ""
            log.hosts.withLock { $0.append(host) }
            if host == "10.0.0.2" { throw URLError(error) }
            return (200, Data("{}".utf8))
        }
        return log
    }

    @Test("a POST that timed out may have reached the computer: it is not sent again elsewhere")
    func postTimeoutIsNotResent() async throws {
        let (client, _) = try await makeClient()
        let hosts = hostsLog(firstFailsWith: .timedOut)

        await #expect(throws: URLError.self) {
            try await client.post("/api/v1/backup/now", body: Note(text: "x"))
        }
        #expect(hosts.all == ["10.0.0.2"])
    }

    @Test("a POST whose connection was lost after sending is not sent again elsewhere")
    func postConnectionLostIsNotResent() async throws {
        let (client, _) = try await makeClient()
        let hosts = hostsLog(firstFailsWith: .networkConnectionLost)

        await #expect(throws: URLError.self) {
            try await client.post("/api/v1/memory", body: Note(text: "x"))
        }
        #expect(hosts.all == ["10.0.0.2"])
    }

    @Test("a POST that never connected fails over to the next address")
    func postCannotConnectFailsOver() async throws {
        let (client, _) = try await makeClient()
        let hosts = hostsLog(firstFailsWith: .cannotConnectToHost)

        try await client.post("/api/v1/memory", body: Note(text: "x"))
        #expect(hosts.all == ["10.0.0.2", "100.64.0.7"])
    }

    @Test("a GET that timed out is idempotent: it still fails over")
    func getTimeoutFailsOver() async throws {
        let (client, _) = try await makeClient()
        let hosts = hostsLog(firstFailsWith: .timedOut)

        let _: Empty = try await client.get("/api/v1/history")
        #expect(hosts.all == ["10.0.0.2", "100.64.0.7"])
    }

    @Test("a PATCH that timed out is not sent again elsewhere")
    func patchTimeoutIsNotResent() async throws {
        let (client, _) = try await makeClient()
        let hosts = hostsLog(firstFailsWith: .timedOut)

        await #expect(throws: URLError.self) {
            try await client.patch("/api/v1/skills/x/toggle", body: Note(text: "x"))
        }
        #expect(hosts.all == ["10.0.0.2"])
    }

    @Test("a PUT that timed out is idempotent: it fails over")
    func putTimeoutFailsOver() async throws {
        let (client, _) = try await makeClient()
        let hosts = hostsLog(firstFailsWith: .timedOut)

        try await client.put("/api/v1/mcp/1", body: Note(text: "x"))
        #expect(hosts.all == ["10.0.0.2", "100.64.0.7"])
    }

    @Test("a cancelled request never fails over")
    func cancelledIsNotResent() async throws {
        let (client, _) = try await makeClient()
        let hosts = hostsLog(firstFailsWith: .cancelled)

        await #expect(throws: URLError.self) {
            let _: Empty = try await client.get("/api/v1/history")
        }
        #expect(hosts.all == ["10.0.0.2"])
    }

    @Test("a POST's own timeout overrides the 15 s failover wait")
    func postTimeoutParameter() async throws {
        let (client, _) = try await makeClient()
        let timeouts = Mutex<[TimeInterval]>([])
        MockURLProtocol.handler = { request in
            timeouts.withLock { $0.append(request.timeoutInterval) }
            return (200, Data("{}".utf8))
        }

        try await client.post("/api/v1/backup/now", body: Note(text: "x"), timeout: 300)
        try await client.post("/api/v1/memory", body: Note(text: "x"))
        #expect(timeouts.withLock { $0 } == [300, 15])
    }
}

/// `InMemoryCredentialStore` with no way to see how many times it prompted — this counts
/// `load(reason:)` calls, standing in for "how many times Face ID would have run."
private final class CountingCredentialStore: CredentialStoring, @unchecked Sendable {
    private let count = Mutex<Int>(0)
    private let server: PairedServer?

    init(_ server: PairedServer? = nil) { self.server = server }

    var loadCount: Int { count.withLock { $0 } }
    var exists: Bool { server != nil }
    func load(reason: String) async throws -> PairedServer? {
        count.withLock { $0 += 1 }
        return server
    }
    func save(_ server: PairedServer) throws {}
    func clear() throws {}
}
