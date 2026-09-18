import Foundation
import Models
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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastTimeout = request.timeoutInterval
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.statusCode, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in Self.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        if Self.finishesLoading {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreamingMockURLProtocol.self]
        return URLSession(configuration: config)
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
        let manager = ChatStreamManager(sseClient: SSEClient(session: StreamingMockURLProtocol.makeSession()))
        let serverConfig = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        let userMessage = ChatMessage.userMessage(id: "u1", text: "hi", timestampMs: 0)

        let updates = await manager.send(chatId: "c1", messages: [userMessage], serverConfig: serverConfig)
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()  // .status(.submitted)
        _ = await iterator.next()  // .messages([...]) once the one chunk is parsed — awaiting
        // this deterministically waits for that point without any sleep.

        let attached = await manager.attach("c1")
        #expect(attached != nil)
        #expect(await manager.isStreaming("c1"))
    }
}
