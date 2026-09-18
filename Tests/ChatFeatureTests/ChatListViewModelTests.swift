import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

private final class ChatListMockURLProtocol: URLProtocol, @unchecked Sendable {
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
        config.protocolClasses = [ChatListMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// The handler runs on a URLProtocol thread, so the requests it sees are recorded behind a
/// lock and asserted from the test afterwards.
private final class RequestRecorder: Sendable {
    private let storage = Mutex<[String]>([])
    func record(_ line: String) { storage.withLock { $0.append(line) } }
    var requests: [String] { storage.withLock { $0 } }
}

private let twoChatsJSON = #"""
    [{"id":"c1","title":"Trip planning","createdAt":"2026-09-18T00:00:00.000Z","favorite":false,"projectId":null},
     {"id":"c2","title":"New chat","createdAt":"2026-09-17T00:00:00.000Z","favorite":null,"projectId":"p1"}]
    """#

private let serverErrorJSON =
    #"{"type":"error","error":{"code":"DB_QUERY_FAILED","message":"Failed to get chat history"}}"#

/// Answers `GET /api/history` and `DELETE /api/chat/<id>`, recording "METHOD path" for every request.
private func serve(
    history: String = "[]",
    historyStatus: Int = 200,
    deleteStatus: Int = 200,
    deleteBody: String = #"{"success":true}"#,
    recorder: RequestRecorder
) {
    ChatListMockURLProtocol.handler = { request in
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        recorder.record("\(method) \(path)")
        if method == "GET", path == "/api/history" {
            return (historyStatus, Data(history.utf8))
        }
        if method == "DELETE", path.hasPrefix("/api/chat/") {
            return (deleteStatus, Data(deleteBody.utf8))
        }
        return (404, Data(#"{"type":"error","error":{"code":"NOT_FOUND","message":"no route"}}"#.utf8))
    }
}

@MainActor
@Suite("ChatListViewModel", .serialized)
struct ChatListViewModelTests {
    private func makeViewModel(_ suite: String = #function) -> ChatListViewModel {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let client = APIClient(session: ChatListMockURLProtocol.makeSession(), serverConfig: config)
        return ChatListViewModel(apiClient: client)
    }

    @Test("load() fills the list from GET /api/history, in the server's order")
    func loadPopulatesChatsInServerOrder() async throws {
        let recorder = RequestRecorder()
        serve(history: twoChatsJSON, recorder: recorder)
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.chats[0].title == "Trip planning")
        #expect(recorder.requests == ["GET /api/history"])
        #expect(vm.errorMessage == nil)
        #expect(vm.loadFailed == false)
    }

    @Test("delete(_:) sends DELETE /api/chat/<id> and removes only that chat after it succeeds")
    func deleteRemovesChatAfterSuccessfulDelete() async throws {
        let recorder = RequestRecorder()
        serve(history: twoChatsJSON, recorder: recorder)
        let vm = makeViewModel()
        await vm.load()
        await vm.delete(vm.chats[0])
        #expect(recorder.requests == ["GET /api/history", "DELETE /api/chat/c1"])
        #expect(vm.chats.map(\.id) == ["c2"])
        #expect(vm.errorMessage == nil)
    }

    @Test("a failed delete keeps the chat in the list and shows the server's message")
    func failedDeleteKeepsTheChat() async throws {
        serve(
            history: twoChatsJSON,
            deleteStatus: 500,
            deleteBody: #"{"type":"error","error":{"code":"DB_QUERY_FAILED","message":"Failed to delete chat"}}"#,
            recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        await vm.delete(vm.chats[0])
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.errorMessage == "Failed to delete chat")
    }

    @Test("a failed load surfaces the server's message and is marked as a failure, not an empty list")
    func loadSurfacesError() async throws {
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.errorMessage == "Failed to get chat history")
        #expect(vm.loadFailed)
        #expect(vm.chats.isEmpty)
    }

    @Test("a failed reload keeps the chats already on screen")
    func failedReloadKeepsExistingChats() async throws {
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        await vm.load()
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.errorMessage == "Failed to get chat history")
        #expect(vm.loadFailed)
    }

    @Test("a successful reload clears the failure state")
    func successfulReloadClearsFailure() async throws {
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.loadFailed)
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        await vm.load()
        #expect(vm.loadFailed == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.chats.count == 2)
    }

    @Test("a cancelled load or delete is not shown as an error")
    func cancellationIsNotAnError() async throws {
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()

        ChatListMockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        await vm.load()
        #expect(vm.errorMessage == nil)
        #expect(vm.loadFailed == false)
        #expect(vm.chats.count == 2)

        await vm.delete(vm.chats[0])
        #expect(vm.errorMessage == nil)
        #expect(vm.chats.count == 2)
    }

    @Test("a transport failure is shown as a human message, not a URLError dump")
    func transportErrorUsesAHumanMessage() async throws {
        ChatListMockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let vm = makeViewModel()
        await vm.load()
        let message = try #require(vm.errorMessage)
        #expect(message == URLError(.cannotConnectToHost).localizedDescription)
        // A bare in-process URLError describes itself as "(NSURLErrorDomain error -1004.)"; the
        // dump form (`String(describing:)`) contains "Domain=" and must not reach the user.
        #expect(message.contains("Domain=") == false)
        #expect(vm.loadFailed)
    }

    @Test("relative time is human-readable, handles fractional and plain ISO strings, and falls back to the raw text")
    func relativeTimeIsHumanReadable() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-20T00:00:00Z"))
        let en = Locale(identifier: "en_US")
        #expect(ChatListViewModel.relativeTime(forCreatedAt: "2026-09-18T00:00:00.000Z", now: now, locale: en) == "2 days ago")
        #expect(ChatListViewModel.relativeTime(forCreatedAt: "2026-09-19T21:00:00Z", now: now, locale: en) == "3 hours ago")
        #expect(ChatListViewModel.relativeTime(forCreatedAt: "not a date", now: now, locale: en) == "not a date")
    }
}
