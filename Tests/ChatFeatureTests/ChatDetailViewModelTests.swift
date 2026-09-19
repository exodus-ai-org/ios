import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

private final class ChatDetailMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    /// When true, a `POST /api/chat` answer is delivered but the connection is never finished,
    /// i.e. a turn that is still streaming.
    nonisolated(unsafe) static var holdsChatPostOpen = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let holdsOpen = Self.holdsChatPostOpen
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let isChatPost = request.httpMethod == "POST" && request.url?.path == "/api/chat"
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
                headerFields: isChatPost ? ["Content-Type": "text/event-stream"] : nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            if !(isChatPost && holdsOpen) {
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatDetailMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private struct RecordedRequest: Sendable {
    let line: String  // "METHOD path"
    let body: Data
}

/// The handler runs on a URLProtocol thread, so requests are recorded behind a lock and asserted afterwards.
private final class RequestRecorder: Sendable {
    private let storage = Mutex<[RecordedRequest]>([])
    func record(_ request: RecordedRequest) { storage.withLock { $0.append(request) } }
    var lines: [String] { storage.withLock { $0.map(\.line) } }

    /// The JSON object of the one and only body sent to `POST path`.
    func onlyJSONBody(forPOST path: String) throws -> [String: Any] {
        let bodies = storage.withLock { $0.filter { $0.line == "POST \(path)" }.map(\.body) }
        try #require(bodies.count == 1)
        let object = try JSONSerialization.jsonObject(with: bodies[0])
        return try #require(object as? [String: Any])
    }
}

private let historyRowsJSON = #"""
    [{"id":"u1","chatId":"c1","role":"user","content":"hi","searchText":"hi","createdAt":"2026-09-18T12:00:00.000Z"},
     {"id":"a1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"hello"}],"usage":{"input":3},"api":"anthropic-messages","provider":"anthropic","model":"claude-x","stopReason":"stop","createdAt":"2026-09-18T12:00:05.000Z"}]
    """#

private let helloReply = """
    data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"Hel"}}\n\n\
    data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"Hello!"}}\n\n\
    data: {"type":"title","title":"Greeting"}\n\n\
    data: {"type":"done","messages":[{"id":"u2","role":"user","content":"hey"},{"id":"a2","role":"assistant","content":"Hello!"}]}\n\n
    """

private let partialReply = """
    data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"Hel"}}\n\n
    """

private let toolResultReply = """
    data: {"type":"message_update","message":{"id":"t1","role":"toolResult","toolName":"search","content":"ok"}}\n\n
    """

/// A chat whose transcript ends with the user's message (for example a turn that failed): nothing
/// is in flight, so there must be no pending row.
private let userOnlyHistoryJSON = #"""
    [{"id":"u1","chatId":"c1","role":"user","content":"hi","searchText":"hi","createdAt":"2026-09-18T12:00:00.000Z"}]
    """#

private let envelope404 = #"{"type":"error","error":{"code":"CHAT_NOT_FOUND","message":"Chat not found"}}"#

/// Answers `GET /api/chat/<id>` with `history` and `POST /api/chat` with `reply`, recording every request.
private func serve(
    history: String = "[]",
    historyStatus: Int = 200,
    reply: String = "",
    replyStatus: Int = 200,
    holdReplyOpen: Bool = false,
    recorder: RequestRecorder
) {
    ChatDetailMockURLProtocol.holdsChatPostOpen = holdReplyOpen
    ChatDetailMockURLProtocol.handler = { request in
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let body = method == "POST" ? try request.httpBodyStreamData() : Data()
        recorder.record(RecordedRequest(line: "\(method) \(path)", body: body))
        if method == "GET", path.hasPrefix("/api/chat/") { return (historyStatus, Data(history.utf8)) }
        if method == "POST", path == "/api/chat" { return (replyStatus, Data(reply.utf8)) }
        return (404, Data(envelope404.utf8))
    }
}

extension URLRequest {
    fileprivate func httpBodyStreamData() throws -> Data {
        guard let stream = httpBodyStream else { return httpBody ?? Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Polls (bounded) until `condition` holds — no timing assumption, just a deadline so a broken build fails instead of hanging.
@MainActor
private func waitUntil(
    _ what: String, timeout: Duration = .seconds(10), _ condition: @MainActor () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
        try #require(ContinuousClock.now < deadline, "timed out waiting for \(what)")
        try await Task.sleep(for: .milliseconds(2))
    }
}

/// One session, one API client and ONE stream manager, so two view models can share the manager like the app does.
@MainActor
private struct Harness {
    let session: URLSession
    let apiClient: APIClient
    let manager: ChatStreamManager
    let config: ServerConfigStore

    init(_ suite: String = #function) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        config = ServerConfigStore(userDefaults: defaults)
        session = ChatDetailMockURLProtocol.makeSession()
        apiClient = APIClient(session: session, serverConfig: config)
        manager = ChatStreamManager(sseClient: SSEClient(session: session))
    }

    func makeViewModel(chatId: String = "c1") -> ChatDetailViewModel {
        ChatDetailViewModel(chatId: chatId, apiClient: apiClient, streamManager: manager, serverConfig: config)
    }
}

@MainActor
@Suite("ChatDetailViewModel", .serialized)
struct ChatDetailViewModelTests {
    @Test("loadHistory shows the desktop-shaped messages converted from the database rows")
    func loadHistoryConvertsDatabaseRows() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(recorder.lines == ["GET /api/chat/c1"])
        #expect(vm.messages.map(\.displayText) == ["hi", "hello"])
        #expect(vm.messages.allSatisfy { $0.raw.keys.contains("chatId") == false && $0.timestampMs != nil })
        #expect(vm.hasLoadedHistory)
        #expect(vm.errorMessage == nil)
    }

    @Test("a chat with no server record yet loads as an empty transcript, not an error")
    func aNewChatLoadsAsEmpty() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        let vm = Harness().makeViewModel(chatId: "brand-new")
        await vm.loadHistory()
        #expect(vm.messages.isEmpty)
        #expect(vm.hasLoadedHistory)
        #expect(vm.errorMessage == nil)
    }

    @Test("a failed history load blocks sending, keeps the draft, and posts nothing")
    func aFailedHistoryLoadBlocksSending() async throws {
        let recorder = RequestRecorder()
        serve(history: envelope404, historyStatus: 500, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.hasLoadedHistory == false)
        #expect(vm.errorMessage == "Chat not found")

        vm.composerText = "hello"
        #expect(vm.canSend == false)
        await vm.sendMessage()
        #expect(recorder.lines == ["GET /api/chat/c1"])
        #expect(vm.composerText == "hello")
        #expect(vm.messages.isEmpty)
    }

    @Test("a cancelled history load is not shown as an error")
    func aCancelledHistoryLoadIsNotAnError() async throws {
        ChatDetailMockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.errorMessage == nil)
        #expect(vm.hasLoadedHistory == false)
    }

    @Test("sendMessage posts the full transcript — converted prior turns plus the new user message — and nothing else")
    func sendMessageSendsTheFullTranscript() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, reply: helloReply, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()

        let body = try recorder.onlyJSONBody(forPOST: "/api/chat")
        #expect(Set(body.keys) == ["id", "messages", "advancedTools"])
        #expect(body["id"] as? String == "c1")
        #expect((body["advancedTools"] as? [Any])?.isEmpty == true)
        let messages = try #require(body["messages"] as? [[String: Any]])
        try #require(messages.count == 3)  // `#require`, not `#expect`: the indexing below must not crash the run
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        // Prior turns are the desktop-shaped conversion, not the raw rows.
        #expect(messages[0].keys.contains("chatId") == false)
        #expect(messages[0]["timestamp"] is NSNumber)
        #expect(messages[1]["stopReason"] as? String == "stop")
        // The new message is the last one, with a lowercase UUID id and a numeric timestamp.
        let last = messages[2]
        #expect(last["content"] as? String == "hey")
        let id = try #require(last["id"] as? String)
        #expect(id == id.lowercased() && UUID(uuidString: id) != nil)
        #expect(last["timestamp"] is NSNumber)
    }

    @Test("the sent text is trimmed of surrounding whitespace and newlines, and the composer is cleared")
    func theSentTextIsTrimmed() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: helloReply, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "  hi there \n"
        await vm.sendMessage()

        let body = try recorder.onlyJSONBody(forPOST: "/api/chat")
        let messages = try #require(body["messages"] as? [[String: Any]])
        try #require(messages.count == 1)  // an empty history, so the new message is the whole transcript
        #expect(messages[0]["content"] as? String == "hi there")  // inner space kept, both ends trimmed
        #expect(vm.composerText.isEmpty)
    }

    @Test("sendMessage streams the reply to completion: final messages from `done`, title event applied, composer cleared")
    func sendMessageStreamsToCompletion() async throws {
        serve(history: "[]", reply: helloReply, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.messages.map(\.displayText) == ["hey", "Hello!"])
        #expect(vm.status == .idle)
        #expect(vm.composerText.isEmpty)
        #expect(vm.chatTitle == "Greeting")
        #expect(vm.errorMessage == nil)
    }

    @Test("empty or whitespace-only drafts are not sent")
    func emptyDraftsAreNotSent() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: helloReply, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        for draft in ["", "   ", "\n \n"] {
            vm.composerText = draft
            #expect(vm.canSend == false)
            await vm.sendMessage()
        }
        #expect(recorder.lines == ["GET /api/chat/c1"])
        #expect(vm.messages.isEmpty)
    }

    @Test("a server error frame ends the turn in the error state with the message shown, and the composer usable again")
    func aServerErrorFrameEndsTheTurnInAnErrorState() async throws {
        serve(history: "[]", reply: #"data: {"type":"error","error":"Invalid API key"}\#n\#n"#, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.errorMessage == "Invalid API key")
        #expect(vm.status == .error)  // not overwritten by a trailing idle
        vm.composerText = "again"
        #expect(vm.canSend)
    }

    @Test("a second send while a turn is in flight is ignored", .timeLimit(.minutes(1)))
    func aSecondSendWhileInFlightIsIgnored() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "first"
        let firstSend = Task { await vm.sendMessage() }
        try await waitUntil("the partial reply to arrive") { vm.messages.last?.displayText == "Hel" }

        vm.composerText = "second"
        #expect(vm.canSend == false)
        await vm.sendMessage()
        #expect(recorder.lines.filter { $0 == "POST /api/chat" }.count == 1)
        #expect(vm.composerText == "second")

        harness.session.invalidateAndCancel()  // end the held-open connection so the first send returns
        await firstSend.value
    }

    @Test("loadHistory during a turn (pull-to-refresh) does not replace the streaming reply with database rows", .timeLimit(.minutes(1)))
    func loadHistoryDoesNotReplaceAStreamingReply() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, reply: partialReply, holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the partial reply to arrive") { vm.messages.last?.displayText == "Hel" }
        let messagesBefore = vm.messages
        let statusBefore = vm.status

        await vm.loadHistory()  // what a pull-to-refresh does while the turn is still streaming

        #expect(recorder.lines.filter { $0 == "GET /api/chat/c1" }.count == 1)  // only the setup load, no second fetch
        #expect(vm.messages == messagesBefore)
        #expect(vm.messages.last?.displayText == "Hel")
        #expect(vm.status == statusBefore)
        #expect(vm.errorMessage == nil)
        #expect(vm.hasLoadedHistory)

        harness.session.invalidateAndCancel()  // end the held-open connection so the send returns
        await send.value
    }

    @Test("returning to a chat whose reply is still streaming re-attaches to it instead of reloading history", .timeLimit(.minutes(1)))
    func onAppearReattachesToAnInFlightTurn() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, reply: partialReply, holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        let first = harness.makeViewModel()
        await first.loadHistory()
        first.composerText = "hey"
        let firstSend = Task { await first.sendMessage() }
        try await waitUntil("the partial reply to arrive") { await harness.manager.isStreaming("c1") && first.messages.last?.displayText == "Hel" }

        // A new view model for the same chat (what leaving and returning creates) shares the manager.
        let second = harness.makeViewModel()
        let appear = Task { await second.onAppear() }
        try await waitUntil("the re-attached view model to show the partial reply") {
            second.messages.last?.displayText == "Hel"
        }
        #expect(second.hasLoadedHistory)
        #expect(second.status == .streaming)
        #expect(recorder.lines.filter { $0 == "GET /api/chat/c1" }.count == 1)  // only the first view model's load

        harness.session.invalidateAndCancel()
        await firstSend.value
        await appear.value
    }

    // MARK: - Pending row (waiting for the first token)

    @Test("showsPendingRow is false while idle: on an empty chat, after a history ending with the user's message, and after a completed turn")
    func pendingRowIsHiddenWhileIdle() async throws {
        serve(history: "[]", reply: helloReply, recorder: RequestRecorder())
        let empty = Harness().makeViewModel()
        await empty.loadHistory()
        #expect(empty.messages.isEmpty)
        #expect(empty.showsPendingRow == false)

        serve(history: userOnlyHistoryJSON, recorder: RequestRecorder())
        let endsWithUser = Harness().makeViewModel()
        await endsWithUser.loadHistory()
        #expect(endsWithUser.messages.map(\.role) == ["user"])
        #expect(endsWithUser.showsPendingRow == false)

        serve(history: "[]", reply: helloReply, recorder: RequestRecorder())
        let completed = Harness().makeViewModel()
        await completed.loadHistory()
        completed.composerText = "hey"
        await completed.sendMessage()
        #expect(completed.status == .idle)
        #expect(completed.showsPendingRow == false)
    }

    @Test("showsPendingRow is true from tapping send until the server's first assistant message", .timeLimit(.minutes(1)))
    func pendingRowShowsWhileWaitingForTheFirstToken() async throws {
        let recorder = RequestRecorder()
        // The server has accepted the turn but sent nothing yet (a reasoning model thinking).
        serve(history: "[]", reply: "", holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the chat POST to reach the server") { recorder.lines.contains("POST /api/chat") }

        #expect(vm.isTurnInFlight)
        #expect(vm.messages.map(\.role) == ["user"])  // the last message is the user's: nothing else on screen yet
        #expect(vm.showsPendingRow)

        harness.session.invalidateAndCancel()  // end the held-open connection so the send returns
        await send.value
    }

    @Test("showsPendingRow turns false once the assistant's partial reply arrives, while the turn is still in flight", .timeLimit(.minutes(1)))
    func pendingRowHidesOnceTheAssistantReplies() async throws {
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: RequestRecorder())
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the partial reply to arrive") { vm.messages.last?.displayText == "Hel" }

        #expect(vm.isTurnInFlight)
        #expect(vm.messages.last?.role == "assistant")
        #expect(vm.showsPendingRow == false)

        harness.session.invalidateAndCancel()
        await send.value
    }

    @Test("showsPendingRow stays true while the last message is a tool result: the model has not spoken since", .timeLimit(.minutes(1)))
    func pendingRowShowsAfterAToolResult() async throws {
        serve(history: "[]", reply: toolResultReply, holdReplyOpen: true, recorder: RequestRecorder())
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the tool result to arrive") { vm.messages.last?.role == "toolResult" }

        #expect(vm.isTurnInFlight)
        #expect(vm.showsPendingRow)

        harness.session.invalidateAndCancel()
        await send.value
    }

    // MARK: - Stop

    @Test("stop() ends an in-flight turn: the partial reply stays, no error appears, and the composer works again", .timeLimit(.minutes(1)))
    func stopEndsAnInFlightTurn() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }  // ends the held-open connection even if an assertion below fails
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the partial reply to arrive") { vm.messages.last?.displayText == "Hel" }
        #expect(vm.isTurnInFlight)
        #expect(vm.canSend == false)

        await vm.stop()
        try await waitUntil("the stopped turn to end") { vm.status == .idle }
        await send.value  // `sendMessage` returns by itself: the observer's stream was finished (bounded by the time limit)

        #expect(vm.status == .idle)
        #expect(vm.messages.map(\.role) == ["user", "assistant"])
        #expect(vm.messages.last?.displayText == "Hel")  // the partial reply stays
        #expect(vm.errorMessage == nil)  // a stop is not an error
        #expect(vm.showsPendingRow == false)
        #expect(await harness.manager.isStreaming("c1") == false)
        #expect(recorder.lines.filter { $0 == "POST /api/chat" }.count == 1)

        vm.composerText = "again"
        #expect(vm.canSend)
    }

    @Test("stop() with no turn in flight does nothing")
    func stopWhileIdleIsANoOp() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        let before = vm.messages

        await vm.stop()

        #expect(vm.status == .idle)
        #expect(vm.messages == before)
        #expect(vm.errorMessage == nil)
        #expect(recorder.lines == ["GET /api/chat/c1"])
    }

    @Test("stop() from a view model that is not in a turn does not cancel a turn another view model started", .timeLimit(.minutes(1)))
    func stopFromAnIdleViewModelLeavesTheTurnAlone() async throws {
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: RequestRecorder())
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let first = harness.makeViewModel()
        await first.loadHistory()
        first.composerText = "hey"
        let send = Task { await first.sendMessage() }
        try await waitUntil("the partial reply to arrive") {
            await harness.manager.isStreaming("c1") && first.messages.last?.displayText == "Hel"
        }

        // Same chat, same manager, but this view model never attached to the turn, so it is idle.
        let bystander = harness.makeViewModel()
        #expect(bystander.status == .idle)
        await bystander.stop()

        #expect(await harness.manager.isStreaming("c1"))
        #expect(first.isTurnInFlight)
        #expect(first.messages.last?.displayText == "Hel")

        harness.session.invalidateAndCancel()
        await send.value
    }

    @Test("the navigation title comes from the title event, else New Chat for an empty transcript and Chat once there are messages")
    func displayTitle() async throws {
        serve(history: historyRowsJSON, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        #expect(vm.displayTitle == "New Chat")
        await vm.loadHistory()
        #expect(vm.displayTitle == "Chat")
    }
}
