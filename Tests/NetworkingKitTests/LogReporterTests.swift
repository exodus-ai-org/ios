import Foundation
import Models
import Synchronization
import Testing

@testable import NetworkingKit

/// Routes each request by host to the `LogTestServer` that registered it, so suites can run in parallel.
final class LogTestURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Data) -> (status: Int, body: Data)?
    static let handlers = Mutex<[String: Handler]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.read(request.httpBodyStream)
        let host = request.url?.host ?? ""
        guard let handler = Self.handlers.withLock({ $0[host] }), let (status, data) = handler(request, body) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LogTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>
    init(_ value: Value) { mutex = Mutex(value) }
    func withLock<R: Sendable>(_ body: (inout sending Value) -> sending R) -> R { mutex.withLock(body) }
}

/// A fake computer: answers each request with the next scripted status (nil = unreachable), then 204.
final class LogTestServer: Sendable {
    let host = "logs-\(UUID().uuidString.lowercased()).test"
    private let script: Locked<[Int?]>
    private let received = Locked<[(path: String, body: Data)]>([])
    let config: ServerConfigStore
    let session = LogTestURLProtocol.makeSession()

    init(statuses: [Int?] = [], respond: (@Sendable (URLRequest) -> (Int, Data))? = nil) {
        script = Locked(statuses)
        config = ServerConfigStore(userDefaults: UserDefaults(suiteName: "log-tests-\(UUID().uuidString)")!)
        config.manualBaseURLString = "http://\(host)"
        LogTestURLProtocol.handlers.withLock { [script, received] handlers in
            handlers[host] = { request, body in
                received.withLock { $0.append((request.url?.path ?? "", body)) }
                if let respond { return respond(request) }
                let scripted: [Int?] = script.withLock { $0.isEmpty ? [] : [$0.removeFirst()] }
                let status = scripted.first ?? 204
                guard let status else { return nil }
                return (status, Data())
            }
        }
    }

    deinit {
        LogTestURLProtocol.handlers.withLock { _ = $0.removeValue(forKey: host) }
    }

    var requestCount: Int { received.withLock { $0.count } }
    var bodies: [String] { received.withLock { $0.map { String(decoding: $0.body, as: UTF8.self) } } }

    private var rawBodies: [Data] { received.withLock { $0.map(\.body) } }

    /// Each request's `reports` array, decoded.
    var batches: [[[String: Any]]] {
        rawBodies.compactMap { body in
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["reports"] as? [[String: Any]]
        }
    }

    var topLevelSources: [String?] {
        rawBodies.map { body in
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["source"] as? String
        }
    }
}

final class Flag: Sendable {
    private let value: Mutex<Bool>
    init(_ initial: Bool) { value = Mutex(initial) }
    var isSet: Bool { value.withLock { $0 } }
    func set(_ newValue: Bool) { value.withLock { $0 = newValue } }
}

final class SleepLog: Sendable {
    private let durations = Mutex<[Duration]>([])
    var all: [Duration] { durations.withLock { $0 } }
    func note(_ duration: Duration) { durations.withLock { $0.append(duration) } }
}

/// Polls `condition` until it holds or two seconds pass; the reporter's work runs on its own tasks.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

@Suite("LogReporter")
struct LogReporterTests {
    private func configuration(
        debounce: Duration = .milliseconds(20), capacity: Int = 200, repeatWindow: Duration = .zero
    ) -> LogReporter.Configuration {
        var configuration = LogReporter.Configuration()
        configuration.debounce = debounce
        configuration.capacity = capacity
        configuration.repeatWindow = repeatWindow
        configuration.initialBackoff = .seconds(1)
        configuration.maxBackoff = .seconds(2)
        return configuration
    }

    private func makeReporter(
        _ server: LogTestServer, configuration: LogReporter.Configuration? = nil, ready: Flag = Flag(true),
        sleep: (@Sendable (Duration) async throws -> Void)? = nil,
        now: (@Sendable () -> ContinuousClock.Instant)? = nil
    ) -> LogReporter {
        LogReporter(
            session: server.session, serverConfig: server.config, configuration: configuration ?? self.configuration(),
            isReady: { ready.isSet }, sleep: sleep ?? { try await Task.sleep(for: $0) },
            now: now ?? { ContinuousClock.now })
    }

    @Test("sends at most 50 reports per request, each marked source ios")
    func batchesOfFifty() async throws {
        let server = LogTestServer()
        let ready = Flag(false)
        let reporter = makeReporter(server, ready: ready)
        for index in 0..<120 { await reporter.record(.error, scope: "test", message: "failure \(index)") }
        ready.set(true)
        await reporter.flush()

        #expect(server.batches.map(\.count) == [50, 50, 20])
        let reports = server.batches.flatMap { $0 }
        #expect(reports.allSatisfy { $0["source"] as? String == "ios" })
        #expect(server.topLevelSources.allSatisfy { $0 == "ios" })
        #expect(reports.first?["level"] as? String == "error")
        #expect(reports.map { $0["message"] as? String } == (0..<120).map { "failure \($0)" })
        #expect(await reporter.pending.isEmpty)
    }

    @Test("redacts keys, tokens, URL queries and body-like attributes before anything is queued")
    func redaction() async throws {
        let server = LogTestServer()
        let reporter = makeReporter(server, ready: Flag(false))
        await reporter.record(
            .warn, scope: "api",
            message:
                "failed https://user:hunter2@example.com/v1/models?key=AIzaSyA1234567890abcdefghijk#frag with Bearer abc.def-ghi and sk-ant-api03-SECRETSECRET",
            attributes: [
                "apiKey": .string("sk-live-123"), "body": .string(#"{"prompt":"my diary"}"#),
                "authorization": .string("Bearer zzz"), "pairingCode": .string("123456"),
                "url": .string("http://192.168.1.2:63129/api/v1/chat?token=abc&c=999"), "status": .int(500),
            ])
        let entry = try #require(await reporter.pending.first)
        #expect(entry.message.contains("https://example.com/v1/models"))
        #expect(entry.attributes["url"] == .string("http://192.168.1.2:63129/api/v1/chat"))
        #expect(entry.attributes["status"] == .int(500))

        let ready = Flag(true)
        let sender = makeReporter(server, ready: ready)
        await sender.record(entry.level, scope: entry.scope, message: entry.message, attributes: entry.attributes)
        await sender.flush()
        let body = try #require(server.bodies.first)
        for secret in [
            "hunter2", "user:", "key=", "AIzaSy", "#frag", "abc.def", "SECRETSECRET", "sk-live", "my diary", "zzz",
            "123456", "token=", "c=999",
        ] {
            #expect(!body.contains(secret), "\(secret) leaked")
        }
    }

    @Test("long text is cut on the phone")
    func truncation() async throws {
        let reporter = makeReporter(LogTestServer(), ready: Flag(false))
        await reporter.record(
            .warn, scope: String(repeating: "s", count: 100), message: String(repeating: "word ", count: 400),
            attributes: ["detail": .string(String(repeating: "x ", count: 1000))])
        let entry = try #require(await reporter.pending.first)
        #expect(entry.scope.count == 64)
        #expect(entry.message.count == 500)
        #expect(entry.message.hasSuffix("…"))
        #expect(entry.attributes["detail"].map { if case .string(let text) = $0 { text.count } else { 0 } } == 500)
    }

    @Test("a full buffer drops the oldest and sends the drop count with the next flush")
    func ringBuffer() async throws {
        let server = LogTestServer()
        let ready = Flag(false)
        let reporter = makeReporter(server, configuration: configuration(capacity: 10), ready: ready)
        for index in 0..<15 { await reporter.record(.warn, scope: "test", message: "m\(index)") }
        #expect(await reporter.pending.map(\.message) == (5..<15).map { "m\($0)" })
        #expect(await reporter.droppedCount == 5)

        ready.set(true)
        await reporter.flush()
        let reports = try #require(server.batches.first)
        #expect(reports.first?["message"] as? String == "m5")
        #expect((reports.first?["attributes"] as? [String: Any])?["droppedBefore"] as? Int == 5)
        #expect(reports.dropFirst().allSatisfy { ($0["attributes"] as? [String: Any])?["droppedBefore"] == nil })
        #expect(await reporter.droppedCount == 0)
    }

    @Test("a failed flush keeps the reports, and the next sign of life sends them")
    func retryKeepsEntries() async throws {
        let server = LogTestServer(statuses: [500])
        let reporter = makeReporter(
            server,
            sleep: { duration in
                // The backoff waits (the test lifts it with `noteReachable`); the debounce passes at once.
                if duration >= .seconds(1) { try await Task.sleep(for: .seconds(60)) }
            })
        await reporter.record(.error, scope: "test", message: "kept")
        #expect(await eventually { server.requestCount == 1 })
        #expect(await eventually { await reporter.pending.map(\.message) == ["kept"] })
        #expect(await reporter.isIdle == false)

        reporter.noteReachable()
        #expect(await eventually { server.requestCount == 2 })
        #expect(await eventually { await reporter.pending.isEmpty })
        #expect(server.batches.map { $0.map { $0["message"] as? String } } == [["kept"], ["kept"]])
    }

    @Test("backoff doubles after each failure up to the cap, then resets on success")
    func backoff() async throws {
        let server = LogTestServer(statuses: [500, nil, 503, 423, 204])
        let sleeps = SleepLog()
        let reporter = makeReporter(server, sleep: { sleeps.note($0) })
        await reporter.record(.error, scope: "test", message: "retried")
        #expect(await eventually { server.requestCount == 5 })
        #expect(await eventually { await reporter.pending.isEmpty })
        #expect(await eventually { await reporter.isIdle })
        #expect(sleeps.all == [.milliseconds(20), .seconds(1), .seconds(2), .seconds(2), .seconds(2)])

        await reporter.record(.error, scope: "test", message: "after success")
        #expect(await eventually { server.requestCount == 6 })
        #expect(sleeps.all.last == .milliseconds(20))
    }

    @Test("a 400 drops that batch instead of retrying it forever")
    func rejectedBatchIsDropped() async throws {
        let server = LogTestServer(statuses: [400])
        let ready = Flag(false)
        let reporter = makeReporter(server, ready: ready)
        await reporter.record(.error, scope: "test", message: "refused")
        ready.set(true)
        await reporter.flush()
        #expect(server.requestCount == 1)
        #expect(await reporter.pending.isEmpty)
        #expect(await reporter.isIdle)
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requestCount == 1)

        await reporter.record(.error, scope: "test", message: "next")
        await reporter.flush()
        let next = try #require(server.batches.last?.first)
        #expect(next["message"] as? String == "next")
        #expect((next["attributes"] as? [String: Any])?["droppedBefore"] as? Int == 1)
    }

    @Test("its own failures are never reported to itself")
    func noRecursion() async throws {
        let server = LogTestServer(statuses: [500, 500, 500, 500])
        let sleeps = SleepLog()
        let reporter = makeReporter(server, sleep: { sleeps.note($0) })
        await reporter.record(.error, scope: "test", message: "only one")
        #expect(await eventually { server.requestCount == 5 })
        #expect(server.batches.allSatisfy { $0.count == 1 && $0.first?["message"] as? String == "only one" })
        #expect(await reporter.pending.isEmpty)

        // An APIClient that carries the reporter does not report a failed call to the log route itself.
        let client = APIClient(session: server.session, serverConfig: server.config, reporter: reporter)
        let failing = LogTestServer(statuses: [500])
        let failingClient = APIClient(session: failing.session, serverConfig: failing.config, reporter: reporter)
        do { try await failingClient.post(LogReporter.path, body: ["x": 1]) } catch {}
        do { try await client.post(LogReporter.path, body: ["x": 1]) } catch {}
        try await Task.sleep(for: .milliseconds(50))
        #expect(await reporter.pending.isEmpty)
    }

    @Test("reports arriving within the debounce go out in one request")
    func debounceCoalesces() async throws {
        let server = LogTestServer()
        let reporter = makeReporter(server, configuration: configuration(debounce: .milliseconds(200)))
        for index in 0..<10 { reporter.report(.warn, scope: "test", message: "burst \(index)") }
        #expect(await eventually { server.requestCount == 1 })
        #expect(await eventually { await reporter.pending.isEmpty })
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.requestCount == 1)
        #expect(server.batches.first?.count == 10)
    }

    @Test("a repeated report within the window is counted, not sent again")
    func repeatsAreCounted() async throws {
        let clock = Mutex(ContinuousClock.now)
        let reporter = makeReporter(
            LogTestServer(), configuration: configuration(repeatWindow: .seconds(60)), ready: Flag(false),
            now: { clock.withLock { $0 } })
        for _ in 0..<3 { await reporter.record(.warn, scope: "api", message: "HTTP 500 /api/v1/history") }
        await reporter.record(.warn, scope: "api", message: "HTTP 500 /api/v1/usage")
        #expect(await reporter.pending.count == 2)

        clock.withLock { $0 = $0.advanced(by: .seconds(61)) }
        await reporter.record(.warn, scope: "api", message: "HTTP 500 /api/v1/history")
        #expect(await reporter.pending.count == 3)
        #expect(await reporter.pending.last?.attributes["repeatsSuppressed"] == .int(2))
    }

    @Test("nothing is sent while the app is locked; reports wait for the unlock")
    func waitsWhileLocked() async throws {
        let server = LogTestServer()
        let ready = Flag(false)
        let reporter = makeReporter(server, ready: ready)
        await reporter.record(.warn, scope: "test", message: "while locked")
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requestCount == 0)
        #expect(await reporter.pending.count == 1)

        ready.set(true)
        reporter.noteReachable()
        #expect(await eventually { server.requestCount == 1 })
    }

    @Test("APIClient reports a failed request by status and path only")
    func apiClientFailure() async throws {
        let server = LogTestServer(respond: { _ in (500, Data(#"{"error":{"code":"X","message":"echo sk-secret-value"}}"#.utf8)) })
        let reporter = makeReporter(server, ready: Flag(false))
        let client = APIClient(session: server.session, serverConfig: server.config, reporter: reporter)
        let _: [ChatSummary]? = try? await client.get(
            "/api/v1/history", query: [URLQueryItem(name: "q", value: "private words")])
        #expect(await eventually { await reporter.pending.count == 1 })
        let entry = try #require(await reporter.pending.first)
        #expect(entry.scope == "api")
        #expect(entry.level == .error)
        #expect(entry.message == "HTTP 500 /api/v1/history")
        #expect(entry.attributes.filter { $0.key != "occurredAt" } == ["status": .int(500), "path": .string("/api/v1/history")])
    }

    @Test("every report carries when it happened on the phone, in UTC with milliseconds, not when it was sent")
    func occurredAtIsTheTimeOfTheReport() async throws {
        let server = LogTestServer()
        let ready = Flag(false)
        let clock = Mutex(Date(timeIntervalSince1970: 1_790_236_800.125))
        let reporter = LogReporter(
            session: server.session, serverConfig: server.config, configuration: configuration(),
            isReady: { ready.isSet }, wallClock: { clock.withLock { $0 } })
        await reporter.record(.warn, scope: "test", message: "first")
        clock.withLock { $0 = Date(timeIntervalSince1970: 1_790_240_400.5) }
        reporter.report(.error, scope: "test", message: "second")
        #expect(await eventually { await reporter.pending.count == 2 })
        clock.withLock { $0 = Date(timeIntervalSince1970: 1_800_000_000) }
        ready.set(true)
        await reporter.flush()

        let reports = try #require(server.batches.first)
        let stamps = reports.map { ($0["attributes"] as? [String: Any])?["occurredAt"] as? String }
        #expect(stamps == ["2026-09-24T08:00:00.125Z", "2026-09-24T09:00:00.500Z"])
    }
}

@Suite("SSE reporting")
struct SSEReportingTests {
    /// The reporter's own repeat window would hide a per-frame report; these tests check the stream's own limit.
    private static var noRepeatWindow: LogReporter.Configuration {
        var configuration = LogReporter.Configuration()
        configuration.repeatWindow = .zero
        return configuration
    }

    @Test("a stream of undecodable frames produces one report, not one per frame")
    func undecodableFramesReportedOnce() async throws {
        let frames =
            (0..<5).map { _ in #"data: {"type":"message_update","message":{"secret":"diary"}}"# }
            + [#"data: {"type":"title","title":"Fine"}"#]
        let sse = LogTestServer(respond: { _ in (200, Data((frames.joined(separator: "\n\n") + "\n\n").utf8)) })
        let logs = LogTestServer()
        let reporter = LogReporter(
            session: logs.session, serverConfig: logs.config, configuration: Self.noRepeatWindow, isReady: { false })
        let client = SSEClient(session: sse.session, reporter: reporter)
        var events: [ChatSseEvent] = []
        for try await event in client.events(for: URLRequest(url: URL(string: "http://\(sse.host)/api/v1/chat")!)) {
            events.append(event)
        }
        #expect(events.count == 1)
        #expect(await eventually { await reporter.pending.count == 1 })
        try await Task.sleep(for: .milliseconds(50))
        let entries = await reporter.pending
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.scope == "sse")
        #expect(entry.attributes["frames"] == .int(5))
        #expect(entry.attributes["eventType"] == .string("message_update"))
        #expect(entry.attributes["path"] == .string("/api/v1/chat"))
        #expect(!entry.attributes.values.contains { $0.text.contains("diary") })
    }

    @Test("an unknown event type is reported once per turn")
    func unknownEventReportedOnce() async throws {
        let frames = (0..<4).map { _ in #"data: {"type":"brand_new_event","payload":1}"# }
        let sse = LogTestServer(respond: { _ in (200, Data((frames.joined(separator: "\n\n") + "\n\n").utf8)) })
        let logs = LogTestServer()
        let reporter = LogReporter(
            session: logs.session, serverConfig: logs.config, configuration: Self.noRepeatWindow, isReady: { false })
        let manager = ChatStreamManager(sseClient: SSEClient(session: sse.session), reporter: reporter)
        for await _ in await manager.send(chatId: "c1", messages: [], serverConfig: sse.config) {}
        #expect(await eventually { await reporter.pending.count == 1 })
        try await Task.sleep(for: .milliseconds(50))
        let entries = await reporter.pending
        #expect(entries.map(\.message) == ["Unknown SSE event type"])
        #expect(entries.first?.attributes["eventType"] == .string("brand_new_event"))
    }
}
