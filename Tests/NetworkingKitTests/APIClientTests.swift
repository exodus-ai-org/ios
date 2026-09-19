import Foundation
import Models
import Synchronization
import Testing

@testable import NetworkingKit

@Suite("APIClient", .serialized)
struct APIClientTests {
    private func makeClient() -> APIClient {
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        return APIClient(session: MockURLProtocol.makeSession(), serverConfig: config)
    }

    /// Installs a handler that records every request it receives and answers
    /// with `status`/`body`. Assert on the returned recorder *after* the call:
    /// checks made only inside the handler never run if the client sends nothing.
    private func stub(status: Int, body: String = "") -> RequestRecorder {
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            try recorder.record(request)
            return (status, Data(body.utf8))
        }
        return recorder
    }

    @Test("GET decodes a successful JSON response")
    func getDecodesSuccess() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/history")
            #expect(request.httpMethod == "GET")
            let json = """
                [{"id":"c1","title":"Trip","createdAt":"2026-09-18T00:00:00.000Z"}]
                """.data(using: .utf8)!
            return (200, json)
        }
        let chats: [ChatSummary] = try await makeClient().get("/api/history")
        #expect(chats.count == 1)
        #expect(chats[0].id == "c1")
    }

    @Test("POST encodes the body and decodes the response")
    func postDecodesSuccess() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            let body = try JSONSerialization.jsonObject(with: request.httpBodyStreamData()) as? [String: Any]
            #expect(body?["provider"] as? String == "Anthropic Claude")
            let json = """
                {"models":[]}
                """.data(using: .utf8)!
            return (200, json)
        }
        let request = ListModelsRequest(provider: "Anthropic Claude", apiKey: "k", baseUrl: nil, apiVersion: nil)
        let response: ListModelsResponse = try await makeClient().post("/api/settings/models", body: request)
        #expect(response.models.isEmpty)
    }

    @Test("POST with no expected response body sends the request and just checks status")
    func postWithoutDecoding() async throws {
        let recorder = stub(status: 200, body: "{}")
        let patch = SettingsPatch(id: "global", providerConfig: nil, providers: nil)
        try await makeClient().post("/api/settings", body: patch)

        let requests = recorder.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/settings")
        let body = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        #expect(body?["id"] as? String == "global")
    }

    @Test("POST with no expected response body accepts a 2xx with an empty body")
    func postWithoutDecodingAcceptsEmptyBody() async throws {
        let recorder = stub(status: 204)
        let patch = SettingsPatch(id: "global", providerConfig: nil, providers: nil)
        try await makeClient().post("/api/settings", body: patch)
        #expect(recorder.requests.count == 1)
    }

    @Test("POST with no expected response body accepts a 2xx with a non-JSON body")
    func postWithoutDecodingAcceptsNonJSONBody() async throws {
        let recorder = stub(status: 200, body: "OK")
        let patch = SettingsPatch(id: "global", providerConfig: nil, providers: nil)
        try await makeClient().post("/api/settings", body: patch)
        #expect(recorder.requests.count == 1)
    }

    @Test("POST with no expected response body throws HTTPError on a non-2xx status")
    func postWithoutDecodingThrowsHTTPErrorOnFailure() async throws {
        let recorder = stub(
            status: 500,
            body: #"{"type":"error","error":{"code":"INTERNAL_ERROR","message":"Could not save settings"}}"#)
        let patch = SettingsPatch(id: "global", providerConfig: nil, providers: nil)
        await #expect(
            throws: HTTPError(statusCode: 500, code: "INTERNAL_ERROR", message: "Could not save settings")
        ) {
            try await makeClient().post("/api/settings", body: patch)
            return
        }
        #expect(recorder.requests.count == 1)
    }

    @Test("DELETE sends the request and succeeds on 2xx")
    func deleteSucceeds() async throws {
        let recorder = stub(status: 200, body: #"{"success":true}"#)
        try await makeClient().delete("/api/chat/c1")

        let requests = recorder.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.method == "DELETE")
        #expect(request.path == "/api/chat/c1")
        #expect(request.body.isEmpty)
    }

    @Test("DELETE accepts a 2xx with an empty body")
    func deleteAcceptsEmptyBody() async throws {
        let recorder = stub(status: 204)
        try await makeClient().delete("/api/chat/c1")
        #expect(recorder.requests.count == 1)
    }

    @Test("DELETE accepts a 2xx with a non-JSON body")
    func deleteAcceptsNonJSONBody() async throws {
        let recorder = stub(status: 200, body: "deleted")
        try await makeClient().delete("/api/chat/c1")
        #expect(recorder.requests.count == 1)
    }

    @Test("DELETE throws HTTPError on a non-2xx status")
    func deleteThrowsHTTPErrorOnFailure() async throws {
        let recorder = stub(
            status: 404,
            body: #"{"type":"error","error":{"code":"NOT_FOUND","message":"Chat not found"}}"#)
        await #expect(
            throws: HTTPError(statusCode: 404, code: "NOT_FOUND", message: "Chat not found")
        ) {
            try await makeClient().delete("/api/chat/c1")
        }
        #expect(recorder.requests.count == 1)
    }

    // MARK: - Non-2xx with no usable body

    @Test("a non-2xx with an empty body reads 'HTTP <status>', not a blank message")
    func emptyErrorBodyFallsBackToTheStatus() async throws {
        let recorder = stub(status: 502)
        await #expect(
            throws: HTTPError(statusCode: 502, code: "UNKNOWN_ERROR", message: "HTTP 502")
        ) {
            try await makeClient().delete("/api/chat/c1")
        }
        #expect(recorder.requests.count == 1)
    }

    @Test("a non-2xx with a whitespace-only body reads 'HTTP <status>' too")
    func whitespaceErrorBodyFallsBackToTheStatus() async throws {
        let recorder = stub(status: 502, body: " \n\t ")
        await #expect(
            throws: HTTPError(statusCode: 502, code: "UNKNOWN_ERROR", message: "HTTP 502")
        ) {
            let _: [ChatSummary] = try await makeClient().get("/api/history")
        }
        #expect(recorder.requests.count == 1)
    }

    @Test("a non-2xx with a plain-text body keeps that text as the message")
    func plainTextErrorBodyIsKept() async throws {
        let recorder = stub(status: 502, body: "Bad Gateway")
        await #expect(
            throws: HTTPError(statusCode: 502, code: "UNKNOWN_ERROR", message: "Bad Gateway")
        ) {
            try await makeClient().delete("/api/chat/c1")
        }
        #expect(recorder.requests.count == 1)
    }

    // MARK: - Requests go to the configured base URL

    /// A client on its own isolated `UserDefaults` suite (removed first and again afterwards), so a
    /// test that changes the address cannot leak it into another test's client.
    private func withConfiguredClient(
        suite: String, baseURL: String?,
        _ body: (APIClient, ServerConfigStore) async throws -> Void
    ) async throws {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let serverConfig = ServerConfigStore(userDefaults: defaults)
        if let baseURL { serverConfig.baseURLString = baseURL }
        let client = APIClient(session: MockURLProtocol.makeSession(), serverConfig: serverConfig)
        try await body(client, serverConfig)
    }

    @Test("a request goes to the address in ServerConfigStore, not a hardcoded one")
    func requestGoesToTheConfiguredBaseURL() async throws {
        let recorder = stub(status: 200, body: "[]")
        try await withConfiguredClient(suite: "APIClientTests.configuredBaseURL", baseURL: "http://192.168.1.10:8080") {
            client, _ in
            let _: [ChatSummary] = try await client.get("/api/history")
        }
        let request = try #require(recorder.requests.first)
        #expect(recorder.requests.count == 1)
        #expect(request.url?.absoluteString == "http://192.168.1.10:8080/api/history")
        #expect(request.url?.host == "192.168.1.10")
        #expect(request.url?.port == 8080)
        #expect(request.url?.scheme == "http")
    }

    @Test("the address is read on every request: changing it between two calls changes where the second goes")
    func changingTheAddressRedirectsTheNextRequest() async throws {
        let recorder = stub(status: 200, body: "[]")
        try await withConfiguredClient(suite: "APIClientTests.changingBaseURL", baseURL: "http://192.168.1.10:8080") {
            client, serverConfig in
            let _: [ChatSummary] = try await client.get("/api/history")
            serverConfig.baseURLString = "http://192.168.1.20:9090"
            let _: [ChatSummary] = try await client.get("/api/history")
        }
        #expect(
            recorder.requests.map { $0.url?.absoluteString } == [
                "http://192.168.1.10:8080/api/history", "http://192.168.1.20:9090/api/history"
            ])
    }

    @Test("with nothing configured a request goes to the default desktop address")
    func unconfiguredRequestGoesToTheDefaultAddress() async throws {
        let recorder = stub(status: 200, body: "[]")
        try await withConfiguredClient(suite: "APIClientTests.defaultBaseURL", baseURL: nil) { client, _ in
            let _: [ChatSummary] = try await client.get("/api/history")
        }
        #expect(recorder.requests.first?.url?.absoluteString == "http://localhost:60223/api/history")
    }

    @Test("a non-2xx Anthropic-style error body throws HTTPError with the server's message")
    func throwsHTTPErrorOnFailure() async throws {
        MockURLProtocol.handler = { _ in
            let json = """
                {"type":"error","error":{"code":"VALIDATION_FAILED","message":"API key is required"}}
                """.data(using: .utf8)!
            return (400, json)
        }
        do {
            let _: ListModelsResponse = try await makeClient().post(
                "/api/settings/models", body: ListModelsRequest(provider: "Ollama", apiKey: nil, baseUrl: nil, apiVersion: nil))
            Issue.record("expected HTTPError to be thrown")
        } catch let error as HTTPError {
            #expect(error.statusCode == 400)
            #expect(error.code == "VALIDATION_FAILED")
            #expect(error.message == "API key is required")
        }
    }
}

/// Log of the requests that reached `MockURLProtocol`. The handler runs on
/// URLProtocol's loading thread while the test reads the log from its own task,
/// so the storage sits behind a `Mutex`; a bare captured `var` would be a data
/// race and a Swift 6 error.
private final class RequestRecorder: Sendable {
    struct RecordedRequest: Sendable {
        let method: String?
        let path: String?
        let url: URL?
        let body: Data
    }

    private let storage = Mutex<[RecordedRequest]>([])

    func record(_ request: URLRequest) throws {
        let body = try request.httpBodyStreamData()
        let entry = RecordedRequest(method: request.httpMethod, path: request.url?.path, url: request.url, body: body)
        storage.withLock { $0.append(entry) }
    }

    var requests: [RecordedRequest] { storage.withLock { $0 } }
}

extension URLRequest {
    /// `httpBody` is nil for requests dispatched through URLProtocol (the body
    /// travels as a stream instead) — read it back from `httpBodyStream` for
    /// assertions in tests.
    fileprivate func httpBodyStreamData() throws -> Data {
        guard let stream = httpBodyStream else { return Data() }
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
