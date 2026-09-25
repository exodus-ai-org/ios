import Foundation
import Models
import NetworkingKit
import Testing

@testable import ChatFeature

private final class RunGrouperMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let rows = #"""
    [{"id":"u1","runId":"u1","chatId":"c1","role":"user","content":"hi","createdAt":"2026-09-18T12:00:00.000Z"},
     {"id":"a1","runId":"u1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"Checking."},{"type":"toolCall","id":"k1","name":"grep","arguments":{}}],"stopReason":"toolUse","createdAt":"2026-09-18T12:00:01.000Z"},
     {"id":"t1","runId":"u1","chatId":"c1","role":"toolResult","toolCallId":"k1","toolName":"grep","content":[],"details":null,"isError":false,"createdAt":"2026-09-18T12:00:02.000Z"},
     {"id":"a2","runId":"u1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"Found it."}],"stopReason":"stop","durationMs":2000,"createdAt":"2026-09-18T12:00:03.000Z"}]
    """#

@MainActor
@Suite("ChatDetailViewModel.segments", .serialized)
struct RunGrouperViewModelTests {
    @Test("segments follow messages: a loaded history is one user row and one turn")
    func segmentsFollowMessages() async {
        RunGrouperMockURLProtocol.body = Data(rows.utf8)
        let suite = "RunGrouperViewModelTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [RunGrouperMockURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        let vm = ChatDetailViewModel(
            chatId: "c1", apiClient: APIClient(session: session, serverConfig: config),
            streamManager: ChatStreamManager(sseClient: SSEClient(session: session)), serverConfig: config)
        #expect(vm.segments.isEmpty)
        await vm.loadHistory()
        #expect(vm.messages.count == 4)
        #expect(vm.segments.map(\.id) == ["u1", "run:u1"])
        guard case .assistantTurn(let turn) = vm.segments.last else {
            Issue.record("no turn")
            return
        }
        #expect(turn.body == "Checking.\n\nFound it.")
        #expect(turn.durationMs == 2000)
    }
}
