import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

private final class ActionsMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    /// A `POST /api/v1/chat` answer is delivered but the connection stays open: a turn still streaming.
    nonisolated(unsafe) static var holdsChatPostOpen = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let holdsOpen = Self.holdsChatPostOpen
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let isChatPost = request.httpMethod == "POST" && request.url?.path == "/api/v1/chat"
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
                headerFields: isChatPost ? ["Content-Type": "text/event-stream"] : nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            if !(isChatPost && holdsOpen) { client?.urlProtocolDidFinishLoading(self) }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// The bodies of the `POST /api/v1/chat` requests, in order; the handler runs on a URLProtocol thread.
private final class ChatPosts: Sendable {
    private let bodies = Mutex<[Data]>([])
    func record(_ body: Data) { bodies.withLock { $0.append(body) } }
    var count: Int { bodies.withLock { $0.count } }

    func messages(ofPost index: Int) throws -> [[String: Any]] {
        let data = try #require(bodies.withLock { $0.indices.contains(index) ? $0[index] : nil })
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["messages"] as? [[String: Any]])
    }
}

/// Lets a test hold the notice timer and release it: no clock, no sleeping.
private final class ManualSleeper: Sendable {
    private let waiters = Mutex<[UUID: CheckedContinuation<Void, Never>]>([:])
    var waiterCount: Int { waiters.withLock { $0.count } }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters.withLock { $0[id] = continuation }
                if Task.isCancelled { waiters.withLock { $0.removeValue(forKey: id) }?.resume() }
            }
        } onCancel: {
            waiters.withLock { $0.removeValue(forKey: id) }?.resume()
        }
        try Task.checkCancellation()
    }

    func release() {
        let all = waiters.withLock { waiters in
            defer { waiters = [:] }
            return waiters
        }
        for continuation in all.values { continuation.resume() }
    }
}

private let history = #"""
    [{"id":"u1","runId":"u1","chatId":"c1","role":"user","content":"hi","createdAt":"2026-09-18T12:00:00.000Z"},
     {"id":"a1","runId":"u1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"hello"}],"stopReason":"stop","createdAt":"2026-09-18T12:00:05.000Z"}]
    """#
private let twoRuns = #"""
    [{"id":"u1","runId":"u1","chatId":"c1","role":"user","content":"one","createdAt":"2026-09-18T12:00:00.000Z"},
     {"id":"a1","runId":"u1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"A1"}],"stopReason":"stop","createdAt":"2026-09-18T12:00:05.000Z"},
     {"id":"u2","runId":"u2","chatId":"c1","role":"user","content":"two","createdAt":"2026-09-18T12:01:00.000Z"},
     {"id":"a2","runId":"u2","chatId":"c1","role":"assistant","content":[{"type":"text","text":"A2"}],"stopReason":"stop","createdAt":"2026-09-18T12:01:05.000Z"}]
    """#
private let imageQuestion = #"""
    [{"id":"u1","runId":"u1","chatId":"c1","role":"user","content":[{"type":"text","text":"what is this?"},{"type":"image","data":"data:image/png;base64,AAAA","mimeType":"image/png"}],"createdAt":"2026-09-18T12:00:00.000Z"},
     {"id":"a1","runId":"u1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"A cat."}],"stopReason":"stop","createdAt":"2026-09-18T12:00:05.000Z"}]
    """#
private let searchedHistory = #"""
    [{"id":"u1","runId":"u1","chatId":"c1","role":"user","content":"news","createdAt":"2026-09-18T12:00:00.000Z"},
     {"id":"a1","runId":"u1","chatId":"c1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"web_search","arguments":{"query":"news"}}],"stopReason":"toolUse","createdAt":"2026-09-18T12:00:01.000Z"},
     {"id":"t1","runId":"u1","chatId":"c1","role":"toolResult","toolCallId":"k1","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":[{"rank":1,"link":"https://a.example/1","title":"One"},{"rank":2,"link":"https://b.example/2","title":"Two"}],"isError":false,"createdAt":"2026-09-18T12:00:02.000Z"},
     {"id":"a2","runId":"u1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"Two hits 【1-source】"}],"stopReason":"stop","createdAt":"2026-09-18T12:00:05.000Z"}]
    """#

private let helloReply = """
    data: {"type":"message_update","message":{"id":"a9","runId":"NEW","role":"assistant","content":"Hel"}}\n\n\
    data: {"type":"done","messages":[{"id":"u9","role":"user","content":"x"},{"id":"a9","role":"assistant","content":"Hello!"}]}\n\n
    """
private let partialReply = """
    data: {"type":"message_update","message":{"id":"a9","role":"assistant","content":"Hel"}}\n\n
    """
private let partialThenError = """
    data: {"type":"message_update","message":{"id":"a9","role":"assistant","content":"Hel"}}\n\n\
    data: {"type":"error","error":"boom"}\n\n
    """

private func noticeReply(level: String, message: String, more: String = "") -> String {
    """
    data: {"type":"notice","level":"\(level)","message":"\(message)"}\n\n\(more)\
    data: {"type":"done","messages":[{"id":"u9","role":"user","content":"x"},{"id":"a9","role":"assistant","content":"Hello!"}]}\n\n
    """
}

@MainActor
private func waitUntil(_ what: String, timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        try #require(ContinuousClock.now < deadline, "timed out waiting for \(what)")
        try await Task.sleep(for: .milliseconds(2))
    }
}

@MainActor
private struct Rig {
    let posts = ChatPosts()
    let sleeper = ManualSleeper()
    let vm: ChatDetailViewModel
    /// From now on, a `POST /api/v1/chat` gets `reply` and is left open: the next turn stays in flight.
    let holdReply: (String) -> Void
    /// From now on, a chat POST gets this reply and the stream ends.
    let reply: (String) -> Void

    /// Answers `GET /api/v1/chat/c1` with `history` and every `POST /api/v1/chat` with `reply`.
    init(history: String = "[]", reply: String = helloReply, holdsOpen: Bool = false, _ suite: String = #function) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [ActionsMockURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        let posts = self.posts
        ActionsMockURLProtocol.holdsChatPostOpen = holdsOpen
        ActionsMockURLProtocol.handler = { request in
            if request.httpMethod == "POST", request.url?.path == "/api/v1/chat" {
                posts.record(request.bodyData())
                return (200, Data(reply.utf8))
            }
            return (200, Data(history.utf8))
        }
        let sleeper = self.sleeper
        self.holdReply = { reply in
            ActionsMockURLProtocol.holdsChatPostOpen = true
            ActionsMockURLProtocol.handler = { request in
                if request.httpMethod == "POST" { posts.record(request.bodyData()) }
                return (200, Data(reply.utf8))
            }
        }
        self.reply = { reply in
            ActionsMockURLProtocol.holdsChatPostOpen = false
            ActionsMockURLProtocol.handler = { request in
                if request.httpMethod == "POST", request.url?.path == "/api/v1/chat" {
                    posts.record(request.bodyData())
                    return (200, Data(reply.utf8))
                }
                return (200, Data(history.utf8))
            }
        }
        vm = ChatDetailViewModel(
            chatId: "c1", apiClient: APIClient(session: session, serverConfig: config),
            streamManager: ChatStreamManager(sseClient: SSEClient(session: session)), serverConfig: config,
            noticeLifetime: .seconds(6), noticeSleep: { try await sleeper.sleep($0) })
    }
}

extension URLRequest {
    fileprivate func bodyData() -> Data {
        guard let stream = httpBodyStream else { return httpBody ?? Data() }
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

/// One serialized parent: every suite below shares the mock's statics.
@Suite("ChatDetailViewModel actions", .serialized)
struct ChatDetailViewModelActionsTests {}

extension ChatDetailViewModelActionsTests {
@MainActor
@Suite("regenerate")
struct RegenerateTests {
    @Test("sends the transcript so far plus a new copy of the last question, and keeps the previous answer in it")
    func resendsTheTranscriptAndACopyOfTheQuestion() async throws {
        let rig = Rig(history: history)
        await rig.vm.loadHistory()
        #expect(rig.vm.canRegenerate)
        await rig.vm.regenerate()

        #expect(rig.posts.count == 1)
        let sent = try rig.posts.messages(ofPost: 0)
        try #require(sent.count == 3)
        #expect(sent.map { $0["role"] as? String } == ["user", "assistant", "user"])
        // Nothing is dropped: the earlier question and its answer go up unchanged, as the desktop's `regenerate` does.
        #expect(sent[0]["id"] as? String == "u1")
        #expect(sent[1]["id"] as? String == "a1")
        #expect((sent[1]["content"] as? [[String: Any]])?.first?["text"] as? String == "hello")
        // The new one is the same question under a new id, opening its own run.
        let copy = sent[2]
        let id = try #require(copy["id"] as? String)
        #expect(id != "u1" && id == id.lowercased() && UUID(uuidString: id) != nil)
        #expect(copy["runId"] as? String == id)
        #expect(copy["content"] as? String == "hi")
        #expect(copy["timestamp"] is NSNumber)
    }

    @Test("the previous answer stays on screen while the new one streams, and a new run follows it")
    func thePreviousAnswerStays() async throws {
        let rig = Rig(history: history, reply: partialReply, holdsOpen: true)
        await rig.vm.loadHistory()
        let running = Task { await rig.vm.regenerate() }
        try await waitUntil("the new reply to start") { rig.vm.messages.count == 4 }

        #expect(rig.vm.messages.map(\.id).prefix(2) == ["u1", "a1"])
        #expect(rig.vm.messages.count == 4)
        #expect(rig.vm.messages[2].role == "user" && rig.vm.messages[2].displayText == "hi")
        #expect(rig.vm.segments.count == 4)
        guard case .assistantTurn(let old) = rig.vm.segments[1] else {
            Issue.record("the previous answer is gone")
            return
        }
        #expect(old.body == "hello")
        #expect(rig.vm.streamingTurnId == rig.vm.segments.last?.id)
        #expect(rig.vm.sendCount == 1)

        await rig.vm.stop()
        await running.value
    }

    @Test("the question's images go with it")
    func attachmentsAreKept() async throws {
        let rig = Rig(history: imageQuestion)
        await rig.vm.loadHistory()
        await rig.vm.regenerate()
        let sent = try rig.posts.messages(ofPost: 0)
        let copy = try #require(sent.last)
        #expect(copy["role"] as? String == "user")
        #expect(copy["content"] as? [[String: String]] == [
            ["type": "text", "text": "what is this?"],
            ["type": "image", "data": "data:image/png;base64,AAAA", "mimeType": "image/png"]
        ])
        #expect(copy["runId"] as? String == copy["id"] as? String)
    }

    @Test("asks the last question of a longer chat, not the first")
    func theLastQuestion() async throws {
        let rig = Rig(history: twoRuns)
        await rig.vm.loadHistory()
        #expect(rig.vm.regenerableTurnId == "run:u2")
        await rig.vm.regenerate()
        let sent = try rig.posts.messages(ofPost: 0)
        try #require(sent.count == 5)
        #expect(sent.last?["content"] as? String == "two")
        #expect(sent.prefix(4).map { $0["id"] as? String } == ["u1", "a1", "u2", "a2"])
    }

    @Test("not while a turn is in flight: the rule is false and calling it posts nothing more")
    func notWhileInFlight() async throws {
        let rig = Rig(history: history, reply: partialReply, holdsOpen: true)
        await rig.vm.loadHistory()
        rig.vm.composerText = "again"
        let sending = Task { await rig.vm.sendMessage() }
        try await waitUntil("the turn to be in flight") { rig.vm.isTurnInFlight && rig.posts.count == 1 }

        #expect(rig.vm.canRegenerate == false)
        #expect(rig.vm.regenerableTurnId == nil)
        await rig.vm.regenerate()
        #expect(rig.posts.count == 1)
        #expect(rig.vm.messages.filter { $0.role == "user" }.count == 2)

        await rig.vm.stop()
        await sending.value
        // The reply was cut short, not failed: the answer it left is the one that can be asked again.
        #expect(rig.vm.canRegenerate)
    }

    @Test("only the last answer of a loaded chat carries it; not before the history is known; not for an unanswered question")
    func whichTurn() async throws {
        let rig = Rig(history: twoRuns)
        #expect(rig.vm.regenerableTurnId == nil)
        await rig.vm.loadHistory()
        #expect(rig.vm.regenerableTurnId == "run:u2")

        let unanswered = Rig(history: #"[{"id":"u1","runId":"u1","chatId":"c1","role":"user","content":"hi","createdAt":"2026-09-18T12:00:00.000Z"}]"#)
        await unanswered.vm.loadHistory()
        #expect(unanswered.vm.canRegenerate == false)
        await unanswered.vm.regenerate()
        #expect(unanswered.posts.count == 0)
    }

    @Test("nothing to ask again without a user message: no request")
    func noQuestion() async throws {
        let rig = Rig(history: #"[{"id":"a1","runId":"r","chatId":"c1","role":"assistant","content":[{"type":"text","text":"hello"}],"stopReason":"stop","createdAt":"2026-09-18T12:00:05.000Z"}]"#)
        await rig.vm.loadHistory()
        #expect(rig.vm.canRegenerate == false)
        await rig.vm.regenerate()
        #expect(rig.posts.count == 0)
    }

    @Test("a reply that failed partway can be asked again, and the new turn clears the run's live error")
    func afterAFailure() async throws {
        let rig = Rig(history: history, reply: partialThenError)
        await rig.vm.loadHistory()
        rig.vm.composerText = "again"
        await rig.vm.sendMessage()
        #expect(rig.vm.status == .error)
        #expect(rig.vm.liveRunError?.message == "boom")
        #expect(rig.vm.canRegenerate)

        await rig.vm.regenerate()
        #expect(rig.posts.count == 2)
        #expect(rig.vm.sendCount == 2)
        let sent = try rig.posts.messages(ofPost: 1)
        #expect(sent.last?["content"] as? String == "again")
        // The second attempt failed the same way, so the live error is that run's, not the first one's.
        #expect(rig.vm.liveRunError?.runId == (sent.last?["runId"] as? String))
    }
}

@MainActor
@Suite("sources sheet")
struct SourcesSheetViewModelTests {
    @Test("a turn's sheet lists its own searches; a chip's marker marks its source; a user row or unknown id has none")
    func sheetForATurn() async throws {
        let rig = Rig(history: searchedHistory)
        await rig.vm.loadHistory()
        let plain = try #require(rig.vm.sourcesSheet(forTurn: "run:u1"))
        #expect(plain.entries.map(\.title) == ["One", "Two"])
        #expect(plain.highlightedId == nil)
        let chip = try #require(rig.vm.sourcesSheet(forTurn: "run:u1", marker: 2))
        #expect(chip.highlightedId == 1)
        #expect(rig.vm.sourcesSheet(forTurn: "u1") == nil)
        #expect(rig.vm.sourcesSheet(forTurn: "run:nope") == nil)
    }
}

@MainActor
@Suite("stream notices")
struct NoticeTests {
    @Test("a notice frame is exposed with its level and text as the server sent it")
    func exposed() async throws {
        let rig = Rig(reply: noticeReply(level: "warning", message: "Places key expired"))
        await rig.vm.loadHistory()
        rig.vm.composerText = "go"
        await rig.vm.sendMessage()
        defer { rig.vm.dismissNotice() }
        #expect(rig.vm.notice == StreamNotice(level: .warning, message: "Places key expired"))
        // The turn itself was not touched by it.
        #expect(rig.vm.status == .idle)
        #expect(rig.vm.errorMessage == nil)
        #expect(rig.vm.messages.last?.displayText == "Hello!")
    }

    @Test("the text is data: markup, brackets and outer whitespace come through untouched")
    func verbatim() async throws {
        let text = "**bold** <b>x</b> [link](https://x.example) 【1-source】 100%"
        let rig = Rig(reply: noticeReply(level: "info", message: text))
        await rig.vm.loadHistory()
        rig.vm.composerText = "go"
        await rig.vm.sendMessage()
        defer { rig.vm.dismissNotice() }
        #expect(rig.vm.notice?.message == text)
    }

    @Test("a level the client does not know shows as a warning, as the server normalises it")
    func unknownLevel() async throws {
        let rig = Rig(reply: noticeReply(level: "critical", message: "m"))
        await rig.vm.loadHistory()
        rig.vm.composerText = "go"
        await rig.vm.sendMessage()
        defer { rig.vm.dismissNotice() }
        #expect(rig.vm.notice?.level == .warning)
    }

    @Test("a blank notice is not shown")
    func blankNotice() async throws {
        let rig = Rig(reply: noticeReply(level: "warning", message: "  "))
        await rig.vm.loadHistory()
        rig.vm.composerText = "go"
        await rig.vm.sendMessage()
        #expect(rig.vm.notice == nil)
        #expect(rig.sleeper.waiterCount == 0)
    }

    @Test("it clears itself after its lifetime, with no real waiting")
    func autoClears() async throws {
        let rig = Rig(reply: noticeReply(level: "warning", message: "m"))
        await rig.vm.loadHistory()
        rig.vm.composerText = "go"
        await rig.vm.sendMessage()
        try await waitUntil("the timer to start") { rig.sleeper.waiterCount == 1 }
        #expect(rig.vm.notice != nil)

        rig.sleeper.release()
        try await waitUntil("the notice to clear") { rig.vm.notice == nil }
    }

    @Test("a newer notice replaces the one on screen and restarts the timer")
    func newerReplacesOlder() async throws {
        let second = #"data: {"type":"notice","level":"info","message":"second"}\#n\#n"#
        let rig = Rig(reply: noticeReply(level: "warning", message: "first", more: second))
        await rig.vm.loadHistory()
        rig.vm.composerText = "go"
        await rig.vm.sendMessage()
        #expect(rig.vm.notice == StreamNotice(level: .info, message: "second"))
        try await waitUntil("exactly one timer left") { rig.sleeper.waiterCount == 1 }
        rig.sleeper.release()
        try await waitUntil("the notice to clear") { rig.vm.notice == nil }
    }

    @Test("dismissing takes it off now and stops its timer")
    func dismiss() async throws {
        let rig = Rig(reply: noticeReply(level: "warning", message: "m"))
        await rig.vm.loadHistory()
        rig.vm.composerText = "go"
        await rig.vm.sendMessage()
        try await waitUntil("the timer to start") { rig.sleeper.waiterCount == 1 }

        rig.vm.dismissNotice()
        #expect(rig.vm.notice == nil)
        try await waitUntil("the timer to be cancelled") { rig.sleeper.waiterCount == 0 }
    }

    @Test("a new send clears it, and so does regenerate")
    func clearedByANewTurn() async throws {
        let rig = Rig(reply: noticeReply(level: "warning", message: "m"))
        await rig.vm.loadHistory()
        rig.vm.composerText = "go"
        await rig.vm.sendMessage()
        try await waitUntil("the timer to start") { rig.sleeper.waiterCount == 1 }
        #expect(rig.vm.notice != nil)

        // The next turn's stream is held open and silent, so what is asserted is the send's own doing.
        rig.holdReply("")
        rig.vm.composerText = "again"
        let sending = Task { await rig.vm.sendMessage() }
        try await waitUntil("the second request") { rig.posts.count == 2 }
        #expect(rig.vm.isTurnInFlight)
        #expect(rig.vm.notice == nil)
        #expect(rig.sleeper.waiterCount == 0)
        await rig.vm.stop()
        await sending.value
    }

    @Test("regenerate clears a notice too")
    func clearedByRegenerate() async throws {
        let rig = Rig(history: history, reply: noticeReply(level: "info", message: "m"))
        await rig.vm.loadHistory()
        await rig.vm.regenerate()
        #expect(rig.vm.notice != nil)

        rig.holdReply("")
        let running = Task { await rig.vm.regenerate() }
        try await waitUntil("the second request") { rig.posts.count == 2 }
        #expect(rig.vm.isTurnInFlight)
        #expect(rig.vm.notice == nil)
        await rig.vm.stop()
        await running.value
    }
}

@MainActor
@Suite("run errors")
struct RunErrorViewModelTests {
    @Test("fail, then send again: the new turn does not raise the old error as an alert")
    func sendAfterFailure() async throws {
        let rig = Rig(history: history, reply: partialThenError)
        await rig.vm.loadHistory()
        rig.vm.composerText = "again"
        await rig.vm.sendMessage()
        #expect(rig.vm.liveRunError?.message == "boom")
        #expect(rig.vm.showsErrorAlert == false)

        rig.reply(helloReply)
        rig.vm.composerText = "third"
        await rig.vm.sendMessage()
        #expect(rig.vm.status == .idle)
        #expect(rig.vm.liveRunError == nil)
        #expect(rig.vm.errorMessage == nil)
        #expect(rig.vm.showsErrorAlert == false)
    }

    @Test("fail, then Regenerate: no alert for the error the run already showed")
    func regenerateAfterFailure() async throws {
        let rig = Rig(history: history, reply: partialThenError)
        await rig.vm.loadHistory()
        rig.vm.composerText = "again"
        await rig.vm.sendMessage()
        rig.reply(helloReply)
        await rig.vm.regenerate()
        #expect(rig.posts.count == 2)
        #expect(rig.vm.errorMessage == nil)
        #expect(rig.vm.showsErrorAlert == false)
    }

    @Test("fail, then a pull-to-refresh that succeeds: no alert, and the rows own the error again")
    func refreshAfterFailure() async throws {
        let rig = Rig(history: history, reply: partialThenError)
        await rig.vm.loadHistory()
        rig.vm.composerText = "again"
        await rig.vm.sendMessage()
        await rig.vm.loadHistory()
        #expect(rig.vm.liveRunError == nil)
        #expect(rig.vm.errorMessage == nil)
        #expect(rig.vm.showsErrorAlert == false)
    }

    @Test("a second failure with the same text still counts as a new failure, for the haptic")
    func identicalFailuresCount() async throws {
        let rig = Rig(history: history, reply: partialThenError)
        await rig.vm.loadHistory()
        rig.vm.composerText = "again"
        await rig.vm.sendMessage()
        #expect(rig.vm.failureCount == 1)
        await rig.vm.regenerate()
        #expect(rig.vm.errorMessage == "boom")
        #expect(rig.vm.failureCount == 2)
    }

    @Test("a run that failed before any step offers Regenerate on its error line, sending what the bar's would")
    func orphanRetry() async throws {
        let rig = Rig(history: history, reply: #"data: {"type":"error","error":"Invalid API key"}\#n\#n"#)
        await rig.vm.loadHistory()
        #expect(rig.vm.canRetryOrphanError == false)
        rig.vm.composerText = "again"
        await rig.vm.sendMessage()
        #expect(TranscriptRules.orphanRunError(segments: rig.vm.segments, live: rig.vm.liveRunError) != nil)
        #expect(rig.vm.regenerableTurnId == nil)
        #expect(rig.vm.canRetryOrphanError)
        #expect(rig.vm.canRegenerate)

        rig.reply(helloReply)
        await rig.vm.regenerate()
        #expect(rig.posts.count == 2)
        let first = try rig.posts.messages(ofPost: 0)
        let retry = try rig.posts.messages(ofPost: 1)
        #expect(retry.count == first.count + 1)
        #expect(retry.last?["content"] as? String == "again")
        #expect(retry.last?["id"] as? String != first.last?["id"] as? String)
        #expect(retry.last?["runId"] as? String == retry.last?["id"] as? String)
        #expect(rig.vm.canRetryOrphanError == false)
    }
}
}
