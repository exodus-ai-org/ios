import Foundation
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

private final class AnswerMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    /// A `POST /api/v1/chat` answered but never finished: a reply still on its way.
    nonisolated(unsafe) static var holdsChatPostOpen = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
            if !(isChatPost && Self.holdsChatPostOpen) { client?.urlProtocolDidFinishLoading(self) }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// The bodies of `POST /api/v1/chat`, recorded behind a lock (the handler runs on a URLProtocol thread).
private final class ChatPosts: Sendable {
    private let storage = Mutex<[Data]>([])
    func record(_ body: Data) { storage.withLock { $0.append(body) } }
    var bodies: [String] { storage.withLock { $0.map { String(decoding: $0, as: UTF8.self) } } }
}

private let reply = """
    data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"Done."}}\n\n\
    data: {"type":"done","messages":[{"id":"u2","role":"user","content":"ok"},{"id":"a2","role":"assistant","content":"Done."}]}\n\n
    """
private let answer = "```exodus-answer\n{\"block\":\"confirm\",\"decision\":\"approve\",\"ref\":\"u1\",\"title\":\"Go?\"}\n```\n\n**Go?** Approved"

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

/// The history (an empty chat, as a page or as rows — whichever the build asks for) and the reply.
private func serve(historyStatus: Int = 200, holdReplyOpen: Bool = false, posts: ChatPosts) {
    AnswerMockURLProtocol.holdsChatPostOpen = holdReplyOpen
    AnswerMockURLProtocol.handler = { request in
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        if method == "GET", path.hasSuffix("/page") {
            let page = #"{"messages":[],"sources":[],"questions":[],"hasOlder":false,"olderCursor":null}"#
            return (historyStatus, Data(page.utf8))
        }
        if method == "GET", path.hasPrefix("/api/v1/chat/") { return (historyStatus, Data("[]".utf8)) }
        if method == "POST", path == "/api/v1/chat" {
            posts.record(request.bodyData())
            return (200, Data(reply.utf8))
        }
        return (404, Data(#"{"type":"error","error":{"code":"NOT_FOUND","message":"Not found"}}"#.utf8))
    }
}

@MainActor
private func makeModel(_ suite: String = #function) -> ChatDetailViewModel {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let config = ServerConfigStore(userDefaults: defaults)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AnswerMockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return ChatDetailViewModel(
        chatId: "c1", apiClient: APIClient(session: session, serverConfig: config),
        streamManager: ChatStreamManager(sseClient: SSEClient(session: session)), serverConfig: config)
}

@MainActor
@Suite("ChatDetailViewModel.sendText: a block's answer is sent past the composer", .serialized)
struct ChatDetailViewModelAnswerTests {
    @Test("the answer is sent as the next message; the composer keeps what was being typed")
    func sendsPastTheComposer() async throws {
        let posts = ChatPosts()
        serve(posts: posts)
        let model = makeModel()
        await model.loadHistory()
        model.composerText = "half-typed"
        #expect(model.canAnswer)
        #expect(await model.sendText(answer))
        #expect(posts.bodies.count == 1)
        let body = try #require(posts.bodies.first)
        #expect(body.contains("exodus-answer"))
        #expect(body.contains("Approved"))
        #expect(model.composerText == "half-typed")
    }

    @Test("nothing is sent before the history is known, or while a reply is on its way")
    func waitsForHistoryAndForTheTurnInFlight() async throws {
        let posts = ChatPosts()
        serve(historyStatus: 500, posts: posts)
        let failed = makeModel("failed-history")
        await failed.loadHistory()
        #expect(!failed.canAnswer)
        #expect(await failed.sendText(answer) == false)
        #expect(posts.bodies.isEmpty)

        serve(holdReplyOpen: true, posts: posts)
        let model = makeModel("in-flight")
        await model.loadHistory()
        let first = Task { await model.sendText(answer) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !model.isTurnInFlight {
            try #require(ContinuousClock.now < deadline, "timed out waiting for the turn")
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(!model.canAnswer)
        // Not sent, and said so: the block gives no "Sent" haptic or announcement.
        #expect(await model.sendText(answer) == false)
        #expect(posts.bodies.count == 1)
        await model.stop()
        first.cancel()
    }
}
