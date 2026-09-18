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

    @Test("the navigation title comes from the title event, else New Chat for an empty transcript and Chat once there are messages")
    func displayTitle() async throws {
        serve(history: historyRowsJSON, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        #expect(vm.displayTitle == "New Chat")
        await vm.loadHistory()
        #expect(vm.displayTitle == "Chat")
    }
}
