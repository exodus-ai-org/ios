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
        let body: Data
    }

    private let storage = Mutex<[RecordedRequest]>([])

    func record(_ request: URLRequest) throws {
        let body = try request.httpBodyStreamData()
        let entry = RecordedRequest(method: request.httpMethod, path: request.url?.path, body: body)
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
