import Foundation
import Models
import Synchronization
import Testing

@testable import NetworkingKit

private final class StreamingMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var chunks: [Data] = []
    /// When `false`, delivers `chunks` but never calls `didFinishLoading` —
    /// simulates a still-open SSE connection instead of a completed HTTP
    /// response. `ChatStreamManager.finish(chatId:)` only runs once the
    /// underlying byte stream actually ends, so a mock that finishes
    /// instantly (the default) cannot be used to test "the turn is still
    /// in flight" — it stops being in flight essentially immediately.
    nonisolated(unsafe) static var finishesLoading: Bool = true
    /// HTTP status the mock answers with. Every test that depends on it sets it
    /// explicitly (the suite is `.serialized`, statics are shared).
    nonisolated(unsafe) static var statusCode: Int = 200
    /// The `timeoutInterval` of the last request the mock saw — lets a test pin
    /// the request configuration `ChatStreamManager` builds.
    nonisolated(unsafe) static var lastTimeout: TimeInterval?
    /// When set, the mock answers with a transport failure (`didFailWithError`) instead of a
    /// response — e.g. `.cannotConnectToHost` when the server is not running.
    nonisolated(unsafe) static var failure: URLError?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastTimeout = request.timeoutInterval
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        // Snapshot the shared statics up front: a test may reconfigure them for
        // its next request while this connection is still open, and this
        // request must not pick up that later configuration.
        let statusCode = Self.statusCode
        let chunks = Self.chunks
        let finishesLoading = Self.finishesLoading
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        if finishesLoading {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// Restores the defaults so one test's configuration can't leak into the next.
    static func reset() {
        chunks = []
        finishesLoading = true
        statusCode = 200
        failure = nil
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreamingMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// Everything one observer of a turn receives. The observer is drained in its own task and the
/// test polls this log against a deadline, so a stream that never ends fails the test instead
/// of hanging the run.
private final class UpdateLog: Sendable {
    private let storage = Mutex<[ChatStreamUpdate]>([])
    private let endedFlag = Mutex(false)

    func drain(_ updates: AsyncStream<ChatStreamUpdate>) async {
        for await update in updates { storage.withLock { $0.append(update) } }
        endedFlag.withLock { $0 = true }
    }

    /// True once the observer's stream has finished (no more updates will ever arrive).
    var ended: Bool { endedFlag.withLock { $0 } }

    /// The updates in arrival order, one short tag each: "status:idle", "messages", "title",
    /// "finished", "failed:<message>".
    var tags: [String] {
        storage.withLock {
            $0.map { update in
                switch update {
                case .status(let status): "status:\(status.rawValue)"
                case .messages: "messages"
                case .title: "title"
                case .finished: "finished"
                case .failed(let message): "failed:\(message)"
                case .notice(let notice): "notice:\(notice.level):\(notice.message)"
                case .approval(.required(let request)): "approval:required:\(request.toolCallId)"
                case .approval(.resolved(_, let toolCallId, let outcome)): "approval:resolved:\(toolCallId):\(outcome)"
                case .memoriesUsed(let runId, let memories): "memories:\(runId):\(memories.map(\.key).joined(separator: ","))"
                case .memoryChanged: "memoryChanged"
                }
            }
        }
    }

    var finishedMessages: [[ChatMessage]] {
        storage.withLock {
            $0.compactMap { update -> [ChatMessage]? in
                if case .finished(let messages) = update { return messages }
                return nil
            }
        }
    }
}

/// Polls (bounded) until `condition` holds; a deadline, not a timing assumption.
private func waitUntil(
    _ what: String, timeout: Duration = .seconds(10), _ condition: @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
        try #require(ContinuousClock.now < deadline, "timed out waiting for \(what)")
        try await Task.sleep(for: .milliseconds(2))
    }
}

@Suite("ChatStreamManager", .serialized)
struct ChatStreamManagerTests {
    @Test("streams message_update frames then finishes on done, collecting the final messages")
    func streamsToCompletion() async throws {
        let sse = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"He"}}\n\n\
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"Hello"}}\n\n\
            data: {"type":"done","messages":[{"id":"u1","role":"user","content":"hi"},{"id":"a1","role":"assistant","content":"Hello"}]}\n\n
            """
        StreamingMockURLProtocol.finishesLoading = true
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.chunks = [Data(sse.utf8)]

        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        var seenStatuses: [ChatStatus] = []
        var finalMessages: [ChatMessage] = []
        for await update in await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig) {
            switch update {
            case .status(let s): seenStatuses.append(s)
            case .finished(let messages): finalMessages = messages
            default: break
            }
        }

        #expect(seenStatuses.first == .submitted)
        #expect(finalMessages.count == 2)
        #expect(finalMessages.last?.displayText == "Hello")
        #expect(await manager.isStreaming("c1") == false)
        // The server sends no keep-alive frames, so the request must tolerate a
        // long silent stretch (see `makeRequest`).
        #expect(StreamingMockURLProtocol.lastTimeout == 3600)
    }

    @Test("a non-2xx response (e.g. no provider configured yet) surfaces the server's message as .failed and ends the stream")
    func httpErrorSurfacesServerMessage() async throws {
        StreamingMockURLProtocol.finishesLoading = true
        StreamingMockURLProtocol.statusCode = 400
        StreamingMockURLProtocol.chunks = [
            Data(#"{"type":"error","error":{"code":"NO_PROVIDER","message":"Please configure a provider in Settings"}}"#.utf8)
        ]
        defer { StreamingMockURLProtocol.statusCode = 200 }

        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        var seenStatuses: [ChatStatus] = []
        var failure: String?
        var sawFinished = false
        for await update in await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig) {
            switch update {
            case .status(let s): seenStatuses.append(s)
            case .failed(let message): failure = message
            case .finished: sawFinished = true
            default: break
            }
        }

        #expect(failure == "Please configure a provider in Settings")
        #expect(seenStatuses.last == .error)
        #expect(!sawFinished)
        #expect(await manager.isStreaming("c1") == false)
    }

    @Test("a transport failure (server not running) surfaces a readable message, not the developer dump of the error")
    func transportFailureSurfacesReadableMessage() async throws {
        StreamingMockURLProtocol.failure = URLError(.cannotConnectToHost)
        defer { StreamingMockURLProtocol.reset() }

        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        var seenStatuses: [ChatStatus] = []
        var failures: [String] = []
        var sawFinished = false
        for await update in await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig) {
            switch update {
            case .status(let s): seenStatuses.append(s)
            case .failed(let message): failures.append(message)
            case .finished: sawFinished = true
            default: break
            }
        }

        // `String(describing:)` of the error is the developer dump
        // ("URLError(_nsError: Error Domain=NSURLErrorDomain Code=-1004 …)"); the user gets the
        // localized text.
        #expect(failures == [URLError(.cannotConnectToHost).localizedDescription])
        #expect(failures.first?.contains("Domain=") == false)
        #expect(seenStatuses.last == .error)
        #expect(!sawFinished)
        #expect(await manager.isStreaming("c1") == false)
    }

    @Test("an in-flight stream can be attached to from a second observer and replays current state")
    func attachReplaysSnapshot() async throws {
        // finishesLoading = false: the mock delivers one chunk and never
        // signals completion, so the underlying byte stream stays open —
        // genuinely "still in flight," not a race against a mock that would
        // otherwise finish (and call ChatStreamManager.finish(chatId:)) in
        // well under a millisecond.
        StreamingMockURLProtocol.finishesLoading = false
        StreamingMockURLProtocol.statusCode = 200
        let sse = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"partial"}}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(sse.utf8)]
        let session = StreamingMockURLProtocol.makeSession()
        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        let updates = await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig)
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()  // .status(.submitted)
        _ = await iterator.next()  // .messages([...]) once the one chunk is parsed — awaiting
        // this deterministically waits for that point without any sleep.

        let attached = try #require(await manager.attach("c1"))
        #expect(await manager.isStreaming("c1"))

        // End the still-open connection. `attach` has already returned, so its
        // replay is buffered ahead of anything the shutdown produces; cancelling
        // only guarantees the stream terminates, so a broken replay makes the
        // reads below fail instead of hanging on a stream that never yields.
        // It comes after the `isStreaming` check because it ends the turn.
        session.invalidateAndCancel()

        // `attach` must replay the current snapshot: the messages so far (the user
        // message plus the streamed assistant one), then the current status.
        var replay = attached.makeAsyncIterator()
        let first = await replay.next()
        guard case .messages(let replayedMessages)? = first else {
            Issue.record("expected the first replayed update to be .messages, got \(String(describing: first))")
            return
        }
        #expect(replayedMessages.count == 2)
        #expect(replayedMessages.last?.displayText == "partial")

        let second = await replay.next()
        guard case .status(let replayedStatus)? = second else {
            Issue.record("expected the second replayed update to be .status, got \(String(describing: second))")
            return
        }
        #expect(replayedStatus == .streaming)
    }

    @Test("approval frames are relayed in order, and replayed to an observer that attaches while the call waits")
    func approvalsRelayedAndReplayed() async throws {
        StreamingMockURLProtocol.finishesLoading = false
        StreamingMockURLProtocol.statusCode = 200
        let sse = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"reading"}}\n\n\
            data: {"type":"approval_required","runId":"u1","toolCallId":"call_1","toolName":"read_file","summary":"~/.ssh/id_rsa","expiresAt":1790000000000}\n\n\
            data: {"type":"approval_required","runId":"u1","toolCallId":"call_2","toolName":"terminal","summary":"cat ~/.aws/credentials","expiresAt":1790000000000}\n\n\
            data: {"type":"approval_resolved","runId":"u1","toolCallId":"call_1","outcome":"denied"}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(sse.utf8)]
        let session = StreamingMockURLProtocol.makeSession()
        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let log = UpdateLog()
        let updates = await manager.send(
            chatId: "c1", messages: [.userMessage(id: "u1", text: "hi", timestampMs: 0)], serverConfig: serverConfig)
        let drain = Task { await log.drain(updates) }
        try await waitUntil("the resolved frame") { log.tags.contains("approval:resolved:call_1:denied") }
        #expect(
            log.tags.filter { $0.hasPrefix("approval") } == [
                "approval:required:call_1", "approval:required:call_2", "approval:resolved:call_1:denied",
            ])

        let attached = try #require(await manager.attach("c1"))
        await drain.value
        session.invalidateAndCancel()
        let replay = UpdateLog()
        await replay.drain(attached)
        #expect(
            Array(replay.tags.prefix(5)) == [
                "messages", "status:streaming", "approval:required:call_1", "approval:required:call_2",
                "approval:resolved:call_1:denied",
            ])
    }

    @Test("memories_used is relayed and replayed on attach; update_memory's end says memory changed, other tools' do not")
    func memoryFramesRelayedAndReplayed() async throws {
        StreamingMockURLProtocol.finishesLoading = false
        StreamingMockURLProtocol.statusCode = 200
        let sse = """
            data: {"type":"memories_used","runId":"u1","memories":[{"id":"m1","key":"Music","section":"topic"},{"id":"m2","key":"Work","section":"profile"}]}\n\n\
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"ok"}}\n\n\
            data: {"type":"tool_call_end","toolCallId":"k1","toolName":"weather","isError":false}\n\n\
            data: {"type":"tool_call_end","toolCallId":"k2","toolName":"update_memory","isError":true}\n\n\
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"done"}}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(sse.utf8)]
        let session = StreamingMockURLProtocol.makeSession()
        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let log = UpdateLog()
        let updates = await manager.send(
            chatId: "c1", messages: [.userMessage(id: "u1", text: "hi", timestampMs: 0)], serverConfig: serverConfig)
        let drain = Task { await log.drain(updates) }
        try await waitUntil("the last frame") { log.tags.filter { $0 == "messages" }.count >= 2 }
        #expect(log.tags.filter { $0.hasPrefix("memor") } == ["memories:u1:Music,Work", "memoryChanged"])

        let attached = try #require(await manager.attach("c1"))
        await drain.value
        session.invalidateAndCancel()
        let replay = UpdateLog()
        await replay.drain(attached)
        #expect(Array(replay.tags.prefix(3)) == ["messages", "status:streaming", "memories:u1:Music,Work"])
        #expect(!replay.tags.contains("memoryChanged"), "a change already reported is not replayed")
    }

    @Test("a server-sent error frame is terminal: .status(.error) then .failed, no .idle or .finished, entry removed")
    func serverErrorFrameIsTerminal() async throws {
        // The server sends the error frame and closes the connection right after,
        // so this run ends by itself (no time limit needed): the assertions below
        // fail rather than hang if the frame is not treated as terminal.
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.finishesLoading = true
        let sse = """
            data: {"type":"error","error":"boom"}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(sse.utf8)]
        defer { StreamingMockURLProtocol.reset() }

        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        var seenStatuses: [ChatStatus] = []
        var failures: [String] = []
        var sawFinished = false
        for await update in await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig) {
            switch update {
            case .status(let s): seenStatuses.append(s)
            case .failed(let message): failures.append(message)
            case .finished: sawFinished = true
            default: break
            }
        }

        #expect(failures == ["boom"])
        #expect(seenStatuses.last == .error)
        #expect(!seenStatuses.contains(.idle))
        #expect(!sawFinished)
        #expect(await manager.isStreaming("c1") == false)
    }

    // Time limit: without the fix the first stream's consumer is stranded (its
    // `next()` suspends forever), so a regression must fail, not hang the run.
    @Test(
        "re-sending while a turn is in flight starts a clean new turn and ends the first turn's stream",
        .timeLimit(.minutes(1)))
    func resendWhileStreamingKeepsNewTurnAlive() async throws {
        // First turn: one partial chunk on a connection that never finishes, so
        // it is genuinely still in flight when the second send arrives.
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.finishesLoading = false
        let partial = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"partial"}}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(partial.utf8)]
        defer { StreamingMockURLProtocol.reset() }

        let session = StreamingMockURLProtocol.makeSession()
        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        let first = await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig)
        var firstIterator = first.makeAsyncIterator()
        _ = await firstIterator.next()  // .status(.submitted)
        _ = await firstIterator.next()  // .messages([...]): the first turn is now mid-stream

        // Second turn: a complete response, then the connection closes.
        StreamingMockURLProtocol.finishesLoading = true
        let fresh = """
            data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"fresh"}}\n\n\
            data: {"type":"done","messages":[{"id":"u1","role":"user","content":"hi"},{"id":"a2","role":"assistant","content":"fresh"}]}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(fresh.utf8)]

        var seenStatuses: [ChatStatus] = []
        var finalMessages: [ChatMessage] = []
        var failure: String?
        for await update in await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig) {
            switch update {
            case .status(let s): seenStatuses.append(s)
            case .finished(let messages): finalMessages = messages
            case .failed(let message): failure = message
            default: break
            }
        }

        // The cancelled first turn must not have torn down the second one.
        #expect(failure == nil)
        #expect(seenStatuses.last == .idle)
        #expect(finalMessages.count == 2)
        #expect(finalMessages.last?.displayText == "fresh")
        #expect(await manager.isStreaming("c1") == false)

        // The first turn's stream was finished, not stranded: its consumer's
        // `next()` returns nil instead of suspending forever.
        let end = await firstIterator.next()
        #expect(end == nil)
    }

    // Time limit: without the fix `attach` drops the previous observer's
    // continuation unfinished, so its `next()` suspends forever.
    @Test(
        "attach finishes the previous observer's stream instead of leaving it suspended",
        .timeLimit(.minutes(1)))
    func attachEndsPreviousObserversStream() async throws {
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.finishesLoading = false
        let partial = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"partial"}}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(partial.utf8)]
        defer { StreamingMockURLProtocol.reset() }

        let session = StreamingMockURLProtocol.makeSession()
        // End the open connection when the test is done so nothing is left running.
        defer { session.invalidateAndCancel() }
        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        let original = await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig)
        var originalIterator = original.makeAsyncIterator()
        _ = await originalIterator.next()  // .status(.submitted)
        _ = await originalIterator.next()  // .messages([...]): the turn is now mid-stream

        // Latest observer wins: attaching replaces the original observer, whose
        // stream (nothing left buffered) must now end rather than stay suspended.
        _ = try #require(await manager.attach("c1"))
        let end = await originalIterator.next()
        #expect(end == nil)
    }

    // MARK: - cancel (the user's Stop)

    // Time limit: a `cancel` that leaves the observer's stream open would hang the drain.
    @Test(
        "cancel ends an in-flight turn as idle, not as a failure: .status(.idle) then .finished with the partial reply, and the entry is gone",
        .timeLimit(.minutes(1)))
    func cancelEndsTheTurnAsIdle() async throws {
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.finishesLoading = false
        let partial = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"partial"}}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(partial.utf8)]
        defer { StreamingMockURLProtocol.reset() }

        let session = StreamingMockURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }  // ends the held-open connection even if an assertion below fails
        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        let log = UpdateLog()
        let updates = await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig)
        let drain = Task { await log.drain(updates) }
        try await waitUntil("the partial reply to arrive") { log.tags.contains("messages") }
        #expect(await manager.isStreaming("c1"))

        #expect(await manager.cancel("c1"))  // found and cancelled a real, active stream
        // Removed by `cancel` itself, not later by the cancelled task unwinding.
        #expect(await manager.isStreaming("c1") == false)
        #expect(await manager.cancel("c1") == false)  // a second cancel finds nothing and must not double-finish anything

        try await waitUntil("the observer's stream to end") { log.ended }
        await drain.value

        #expect(log.tags == ["status:submitted", "messages", "status:idle", "finished"])
        let finished = try #require(log.finishedMessages.first)
        #expect(finished.map(\.displayText) == ["hi", "partial"])
        #expect(await manager.isStreaming("c1") == false)
        #expect(await manager.attach("c1") == nil)
    }

    @Test(
        "a send after a cancel runs a clean new turn, and the cancelled turn's task cannot disturb it",
        .timeLimit(.minutes(1)))
    func sendAfterCancelStartsACleanTurn() async throws {
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.finishesLoading = false
        let partial = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"partial"}}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(partial.utf8)]
        defer { StreamingMockURLProtocol.reset() }

        let session = StreamingMockURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }
        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        let firstLog = UpdateLog()
        let first = await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig)
        let firstDrain = Task { await firstLog.drain(first) }
        try await waitUntil("the partial reply to arrive") { firstLog.tags.contains("messages") }
        #expect(await manager.cancel("c1"))
        try await waitUntil("the first observer's stream to end") { firstLog.ended }
        await firstDrain.value

        // Second turn on the same chat: a complete response, then the connection closes.
        StreamingMockURLProtocol.finishesLoading = true
        let fresh = """
            data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"fresh"}}\n\n\
            data: {"type":"done","messages":[{"id":"u1","role":"user","content":"hi"},{"id":"a2","role":"assistant","content":"fresh"}]}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(fresh.utf8)]
        let secondLog = UpdateLog()
        let second = await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig)
        await secondLog.drain(second)  // returns when the turn ends; bounded by the time limit

        let tags = secondLog.tags
        #expect(tags.first == "status:submitted")
        #expect(tags.suffix(2) == ["status:idle", "finished"])
        #expect(tags.contains { $0.hasPrefix("failed") } == false)
        #expect(secondLog.finishedMessages.first?.last?.displayText == "fresh")
        #expect(await manager.isStreaming("c1") == false)
        // The first observer got exactly one ending, from the cancel.
        #expect(firstLog.tags == ["status:submitted", "messages", "status:idle", "finished"])
    }

    @Test(
        "cancel does nothing when no turn is in flight for that chat, and leaves another chat's turn alone",
        .timeLimit(.minutes(1)))
    func cancelWithNothingInFlightIsANoOp() async throws {
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.finishesLoading = false
        let partial = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"partial"}}\n\n
            """
        StreamingMockURLProtocol.chunks = [Data(partial.utf8)]
        defer { StreamingMockURLProtocol.reset() }

        let session = StreamingMockURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }
        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        #expect(await manager.cancel("c1") == false)  // nothing at all has been sent yet
        #expect(await manager.isStreaming("c1") == false)

        let log = UpdateLog()
        let updates = await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig)
        let drain = Task { await log.drain(updates) }
        try await waitUntil("the partial reply to arrive") { log.tags.contains("messages") }

        #expect(await manager.cancel("some-other-chat") == false)
        #expect(await manager.isStreaming("some-other-chat") == false)
        #expect(await manager.isStreaming("c1"))  // c1's turn is untouched
        #expect(log.ended == false)
        #expect(log.tags == ["status:submitted", "messages"])

        #expect(await manager.cancel("c1"))  // clean up the held-open turn
        try await waitUntil("the observer's stream to end") { log.ended }
        await drain.value
    }
}

/// A per-path handler, unlike `StreamingMockURLProtocol`'s shared statics: the unlock-retry
/// tests need `/api/v1/chat` and `/api/v1/lock/unlock` to answer independently, and the first
/// call to `/api/v1/chat` to answer differently from the second (the retry).
private final class RoutedMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.handler?(request) ?? (404, Data())
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RoutedMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

@Suite("ChatStreamManager: the paired computer's own lock", .serialized)
struct ChatStreamManagerLockedTests {
    private static let appLocked = #"{"type":"error","error":{"code":"APP_LOCKED","message":"Application is locked"}}"#

    private func makePairedConfig(_ suite: String) -> ServerConfigStore {
        let store = InMemoryCredentialStore(
            PairedServer(
                hosts: ["10.0.0.2"], port: 63129, fingerprint: "PIN", name: "Mac",
                deviceId: "dev-1", token: "TOKEN"))
        let connection = ServerConnection(store: store)
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: suite)!)
        config.connection = connection
        return config
    }

    @Test("a 423 on the chat request unlocks the computer and retries, streaming normally")
    func unlocksAndRetries() async throws {
        let serverConfig = makePairedConfig(#function)
        try await serverConfig.connection?.unlock(reason: "test")
        let chatCalls = Mutex<Int>(0)
        let session = RoutedMockURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }
        RoutedMockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/v1/lock/unlock":
                return (200, Data(#"{"locked":false}"#.utf8))
            case "/api/v1/chat":
                let calls = chatCalls.withLock { $0 += 1; return $0 }
                if calls == 1 { return (423, Data(Self.appLocked.utf8)) }
                let sse = """
                    data: {"type":"done","messages":[{"id":"u1","role":"user","content":"hi"},\
                    {"id":"a1","role":"assistant","content":"Hello"}]}\n\n
                    """
                return (200, Data(sse.utf8))
            default:
                return (404, Data())
            }
        }

        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)
        var finalMessages: [ChatMessage] = []
        var failure: String?
        for await update in await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig) {
            switch update {
            case .finished(let messages): finalMessages = messages
            case .failed(let message): failure = message
            default: break
            }
        }

        #expect(failure == nil)
        #expect(finalMessages.last?.displayText == "Hello")
        #expect(chatCalls.withLock { $0 } == 2)
    }

    @Test("the unlock call failing surfaces the original locked message as .failed, not a new one")
    func unlockFailureSurfacesTheOriginalError() async throws {
        let serverConfig = makePairedConfig(#function)
        try await serverConfig.connection?.unlock(reason: "test")
        let session = RoutedMockURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }
        RoutedMockURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/lock/unlock" {
                return (500, Data(#"{"type":"error","error":{"code":"X","message":"boom"}}"#.utf8))
            }
            return (423, Data(Self.appLocked.utf8))
        }

        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)
        var failure: String?
        for await update in await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig) {
            if case .failed(let message) = update { failure = message }
        }

        #expect(failure == "Application is locked")
    }

    @Test("a notice frame reaches the observer as .notice, in order between the messages, and does not end the turn")
    func noticeFrameIsRelayed() async throws {
        let sse = """
            data: {"type":"message_update","message":{"id":"a1","role":"assistant","content":"He"}}\n\n\
            data: {"type":"notice","level":"warning","message":"Places key expired"}\n\n\
            data: {"type":"done","messages":[{"id":"u1","role":"user","content":"hi"},{"id":"a1","role":"assistant","content":"Hello"}]}\n\n
            """
        StreamingMockURLProtocol.finishesLoading = true
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.chunks = [Data(sse.utf8)]
        defer { StreamingMockURLProtocol.reset() }

        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        let log = UpdateLog()
        await log.drain(await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig))

        #expect(
            log.tags == [
                "status:submitted", "messages", "notice:warning:Places key expired", "messages", "status:idle",
                "finished"
            ])
    }

    @Test("a repeated notice is relayed once per turn, a different one is relayed too")
    func repeatedNoticeIsRelayedOnce() async throws {
        let sse = """
            data: {"type":"notice","level":"warning","message":"Places key expired"}\n\n\
            data: {"type":"notice","level":"warning","message":"Places key expired"}\n\n\
            data: {"type":"notice","level":"info","message":"Places key expired"}\n\n\
            data: {"type":"notice","level":"warning","message":"Rate limited"}\n\n\
            data: {"type":"notice","level":"warning","message":"Places key expired"}\n\n
            """
        StreamingMockURLProtocol.finishesLoading = true
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.chunks = [Data(sse.utf8)]
        defer { StreamingMockURLProtocol.reset() }

        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        let log = UpdateLog()
        await log.drain(await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig))

        // The desktop keys its `seenNotices` on level + message: same text at another level is a new notice.
        #expect(
            log.tags.filter { $0.hasPrefix("notice:") } == [
                "notice:warning:Places key expired", "notice:info:Places key expired", "notice:warning:Rate limited"
            ])

        // A second turn starts with an empty set.
        StreamingMockURLProtocol.chunks = [
            Data(#"data: {"type":"notice","level":"warning","message":"Places key expired"}\#n\#n"#.utf8)
        ]
        let second = UpdateLog()
        await second.drain(await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig))
        #expect(second.tags.filter { $0.hasPrefix("notice:") } == ["notice:warning:Places key expired"])
    }

    @Test("a notice whose message is blank is not relayed")
    func blankNoticeIsDropped() async throws {
        let sse = """
            data: {"type":"notice","level":"warning","message":""}\n\n\
            data: {"type":"notice","level":"info","message":"  \\n "}\n\n\
            data: {"type":"notice","level":"warning","message":"Rate limited"}\n\n
            """
        StreamingMockURLProtocol.finishesLoading = true
        StreamingMockURLProtocol.statusCode = 200
        StreamingMockURLProtocol.chunks = [Data(sse.utf8)]
        defer { StreamingMockURLProtocol.reset() }

        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let log = UpdateLog()
        await log.drain(
            await manager.send(
                chatId: "c1", messages: [.userMessage(id: "u1", text: "hi", timestampMs: 0)], serverConfig: serverConfig))
        #expect(log.tags.filter { $0.hasPrefix("notice:") } == ["notice:warning:Rate limited"])
    }

    @Test("a notice level mirrors the server's normaliser: only info is info, anything else is a warning")
    func unknownNoticeLevelIsWarning() {
        #expect(StreamNotice(level: "warning", message: "m").level == .warning)
        #expect(StreamNotice(level: "info", message: "m").level == .info)
        #expect(StreamNotice(level: "critical", message: "m").level == .warning)
        #expect(StreamNotice(level: "", message: "m").level == .warning)
        #expect(StreamNotice(level: "Info", message: "m").level == .warning)
    }

    @Test("an unpaired connection gets the original locked message, with no unlock attempt")
    func unpairedGetsTheOriginalError() async throws {
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        serverConfig.connection = ServerConnection(store: InMemoryCredentialStore())
        let session = RoutedMockURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }
        let seen = Mutex<[String]>([])
        RoutedMockURLProtocol.handler = { request in
            seen.withLock { $0.append(request.url?.path ?? "") }
            return (423, Data(Self.appLocked.utf8))
        }

        let manager = ChatStreamManager(sseClient: SSEClient(session: session))
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)
        var failure: String?
        for await update in await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig) {
            if case .failed(let message) = update { failure = message }
        }

        #expect(failure == "Application is locked")
        #expect(seen.withLock { $0 } == ["/api/v1/chat"])
    }
}
