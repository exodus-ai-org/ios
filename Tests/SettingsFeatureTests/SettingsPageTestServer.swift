import Foundation
import NetworkingKit
import Synchronization
import Testing

@testable import SettingsFeature

/// A fake `/api/v1/settings` and `/api/v1/memory` per test. Each server answers at a host of its own, and the one
/// URLProtocol class routes by host, so suites using it can run in parallel. GETs are served `rows` (settings) and
/// `memoryLists` in turn (the last one repeats); every request is logged with its query and body.
final class SettingsPageTestServer: Sendable {
    private struct State {
        var rows: [String]
        var getStatus: Int
        var postStatus: Int
        var memoryLists: [String] = ["[]"]
        var memoryStatus: [String: Int] = [:]
        /// "METHOD path" → answers given in turn (the last one repeats).
        var routes: [String: [(status: Int, body: String)]] = [:]
        var log: [(method: String, path: String, query: String?, body: Data)] = []
        /// "METHOD path" → the timeout the last such request carried.
        var timeouts: [String: TimeInterval] = [:]
    }

    private let state: Mutex<State>
    private let tag = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

    init(rows: [String], getStatus: Int = 200, postStatus: Int = 200) {
        state = Mutex(State(rows: rows, getStatus: getStatus, postStatus: postStatus))
        RoutedSettingsURLProtocol.register(tag) { [weak self] request in self?.respond(to: request) ?? (410, Data()) }
    }

    deinit { RoutedSettingsURLProtocol.unregister(tag) }

    func makeClient(_ suite: String = #function) -> (APIClient, ServerConfigStore) {
        let defaults = UserDefaults(suiteName: "page-\(suite)-\(tag)")!
        let config = ServerConfigStore(userDefaults: defaults)
        config.manualBaseURLString = "http://s\(tag).test"
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [RoutedSettingsURLProtocol.self]
        return (APIClient(session: URLSession(configuration: session), serverConfig: config), config)
    }

    @MainActor
    func makeStore(_ suite: String = #function) -> SettingsStore {
        SettingsStore(apiClient: makeClient(suite).0)
    }

    /// The next GETs answer with these rows (the desktop saved in between).
    func serve(rows: [String]) { state.withLock { $0.rows = rows } }

    func setPostStatus(_ status: Int) { state.withLock { $0.postStatus = status } }

    /// The next `GET /api/v1/memory` answers with these arrays, in turn.
    func serve(memoryLists: [String]) { state.withLock { $0.memoryLists = memoryLists } }

    /// The status every `/api/v1/memory` request of this method gets from now on.
    func setMemoryStatus(_ method: String, _ status: Int) { state.withLock { $0.memoryStatus[method] = status } }

    /// Answers "METHOD path" with these (status, body) pairs in turn; the last one repeats.
    func route(_ method: String, _ path: String, _ answers: [(Int, String)]) {
        state.withLock { $0.routes["\(method) \(path)"] = answers.map { (status: $0.0, body: $0.1) } }
    }

    /// The timeout the last "METHOD path" request carried.
    func timeout(_ method: String, _ path: String) -> TimeInterval? {
        state.withLock { $0.timeouts["\(method) \(path)"] }
    }

    /// Requests whose path starts with `prefix`, in order, as "METHOD path".
    func requests(under prefix: String) -> [String] {
        state.withLock { $0.log.filter { $0.path.hasPrefix(prefix) } }.map { "\($0.method) \($0.path)" }
    }

    /// The JSON body of the last request with this method and path.
    func lastBody(_ method: String, _ path: String) -> [String: Any]? {
        let data = state.withLock { $0.log.last { $0.method == method && $0.path == path }?.body }
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// Requests to `/api/v1/memory…`, in order, as "METHOD path[?query]".
    var memoryRequests: [String] {
        state.withLock { $0.log.filter { $0.path.hasPrefix("/api/v1/memory") } }
            .map { "\($0.method) \($0.path)" + ($0.query.map { "?\($0)" } ?? "") }
    }

    /// The JSON body of the last `/api/v1/memory…` request with this method.
    func lastMemoryBody(_ method: String) -> [String: Any]? {
        let data = state.withLock { $0.log.last { $0.method == method && $0.path.hasPrefix("/api/v1/memory") }?.body }
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// Methods of the requests to `/api/v1/settings`, in order.
    var methods: [String] { state.withLock { $0.log.filter { $0.path == "/api/v1/settings" }.map(\.method) } }

    func lastBody(to path: String) -> [String: Any]? {
        let data = state.withLock { $0.log.last { $0.path == path }?.body }
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    var paths: [String] { state.withLock { $0.log.map(\.path) } }

    /// Bodies posted to `/api/v1/settings` (not to `/models`).
    var postBodies: [[String: Any]] {
        state.withLock { $0.log.filter { $0.method == "POST" && $0.path == "/api/v1/settings" }.map(\.body) }
            .compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func onlyPostBody() throws -> [String: Any] {
        let bodies = postBodies
        try #require(bodies.count == 1)
        return bodies[0]
    }

    private func respond(to request: URLRequest) -> (Int, Data) {
        let method = request.httpMethod ?? ""
        let body = request.testBodyData()
        return state.withLock { state in
            let path = request.url?.path ?? ""
            state.log.append((method, path, request.url?.query, body))
            state.timeouts["\(method) \(path)"] = request.timeoutInterval
            let key = "\(method) \(path)"
            if var answers = state.routes[key], !answers.isEmpty {
                let answer = answers.count > 1 ? answers.removeFirst() : answers[0]
                state.routes[key] = answers
                return (answer.status, Data(answer.body.utf8))
            }
            if path == "/api/v1/settings/models" { return (200, Data(#"{"models":[]}"#.utf8)) }
            if path.hasPrefix("/api/v1/memory") {
                let status = state.memoryStatus[method] ?? (method == "POST" ? 201 : 200)
                if !(200..<300).contains(status) {
                    return (status, Data(#"{"type":"error","error":{"code":"INTERNAL","message":"memory down"}}"#.utf8))
                }
                guard method == "GET" else { return (status, Data(#"{"success":true}"#.utf8)) }
                let list = state.memoryLists.count > 1 ? state.memoryLists.removeFirst() : state.memoryLists[0]
                return (status, Data(list.utf8))
            }
            guard path == "/api/v1/settings" else { return (404, Data()) }
            if method == "POST" {
                return (state.postStatus, Data(#"{"type":"error","error":{"code":"INTERNAL","message":"down"}}"#.utf8))
            }
            let row = state.rows.count > 1 ? state.rows.removeFirst() : state.rows[0]
            return (state.getStatus, Data(row.utf8))
        }
    }
}

final class RoutedSettingsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handlers = Mutex<[String: @Sendable (URLRequest) -> (Int, Data)]>([:])

    static func register(_ tag: String, _ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        handlers.withLock { $0[tag] = handler }
    }

    static func unregister(_ tag: String) { _ = handlers.withLock { $0.removeValue(forKey: tag) } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let tag = String((request.url?.host ?? "").dropFirst().prefix { $0 != "." })
        guard let handler = Self.handlers.withLock({ $0[tag] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLRequest {
    func testBodyData() -> Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
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
