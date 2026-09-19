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
        let first = try #require(vm.chats.first)
        #expect(first.title == "Trip planning")
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
        let first = try #require(vm.chats.first)
        await vm.delete(first)
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
        let first = try #require(vm.chats.first)
        await vm.delete(first)
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

        let first = try #require(vm.chats.first)
        await vm.delete(first)
        #expect(vm.errorMessage == nil)
        #expect(vm.chats.count == 2)
    }

    // MARK: - One error surface (the alert is only for errors the empty state can't show)

    @Test("an empty list whose load failed keeps the error text for the empty state and raises no alert")
    func aFailedFirstLoadRaisesNoAlert() async throws {
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.errorMessage == "Failed to get chat history")  // what the "Can't load chats" state displays
        #expect(vm.loadFailed)
        #expect(vm.chats.isEmpty)
        #expect(vm.showsErrorAlert == false)
    }

    @Test("a failed delete with chats on screen raises the alert until it is dismissed")
    func aFailedDeleteRaisesTheAlert() async throws {
        serve(
            history: twoChatsJSON,
            deleteStatus: 500,
            deleteBody: #"{"type":"error","error":{"code":"DB_QUERY_FAILED","message":"Failed to delete chat"}}"#,
            recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.showsErrorAlert == false)
        let first = try #require(vm.chats.first)
        await vm.delete(first)
        #expect(vm.errorMessage == "Failed to delete chat")
        #expect(vm.showsErrorAlert)
        vm.errorMessage = nil  // what dismissing the alert does
        #expect(vm.showsErrorAlert == false)
    }

    @Test("a failed reload with chats on screen raises the alert")
    func aFailedReloadRaisesTheAlert() async throws {
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        await vm.load()
        #expect(vm.chats.count == 2)
        #expect(vm.loadFailed)
        #expect(vm.errorMessage == "Failed to get chat history")
        #expect(vm.showsErrorAlert)
    }

    @Test("with no error there is no alert, before and after a load")
    func noErrorMeansNoAlert() async throws {
        let vm = makeViewModel()
        #expect(vm.errorMessage == nil)
        #expect(vm.showsErrorAlert == false)
        serve(history: twoChatsJSON, recorder: RequestRecorder())
        await vm.load()
        #expect(vm.showsErrorAlert == false)
    }

    // MARK: - hasLoaded (the empty state must not read "No chats yet" before the first load finishes)

    @Test("a fresh view model has not loaded: it looks empty but must not be read as 'loaded and empty'")
    func aFreshViewModelHasNotLoaded() async throws {
        let vm = makeViewModel()
        #expect(vm.hasLoaded == false)
        #expect(vm.isLoading == false)
        #expect(vm.loadFailed == false)
        #expect(vm.chats.isEmpty)
    }

    @Test("hasLoaded becomes true when a load finishes successfully")
    func hasLoadedAfterASuccessfulLoad() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.hasLoaded)
        #expect(vm.chats.isEmpty)  // loaded and empty: this is the only state that reads "No chats yet"
        #expect(vm.loadFailed == false)
    }

    @Test("hasLoaded becomes true when a load finishes with a failure")
    func hasLoadedAfterAFailedLoad() async throws {
        serve(history: serverErrorJSON, historyStatus: 500, recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.hasLoaded)
        #expect(vm.loadFailed)
    }

    @Test("a load that is only cancelled does not count as loaded")
    func aCancelledLoadDoesNotCountAsLoaded() async throws {
        ChatListMockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        let vm = makeViewModel()
        await vm.load()
        #expect(vm.hasLoaded == false)
        #expect(vm.loadFailed == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
    }

    // MARK: - A load cannot resurrect a chat deleted earlier

    @Test("a load that still returns a chat deleted earlier does not bring it back")
    func aLoadCannotResurrectADeletedChat() async throws {
        let recorder = RequestRecorder()
        serve(history: twoChatsJSON, recorder: recorder)
        let vm = makeViewModel()
        await vm.load()
        let first = try #require(vm.chats.first)
        #expect(first.id == "c1")
        await vm.delete(first)
        #expect(vm.chats.map(\.id) == ["c2"])

        await vm.load()  // the mock still answers [c1, c2], as a load that started before the delete would
        #expect(vm.chats.map(\.id) == ["c2"])
        #expect(recorder.requests == ["GET /api/history", "DELETE /api/chat/c1", "GET /api/history"])
    }

    @Test("a chat whose delete FAILED is not remembered as deleted, so a reload still shows it")
    func aFailedDeleteIsNotRemembered() async throws {
        serve(
            history: twoChatsJSON,
            deleteStatus: 500,
            deleteBody: #"{"type":"error","error":{"code":"DB_QUERY_FAILED","message":"Failed to delete chat"}}"#,
            recorder: RequestRecorder())
        let vm = makeViewModel()
        await vm.load()
        let first = try #require(vm.chats.first)
        await vm.delete(first)
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        await vm.load()
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
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
