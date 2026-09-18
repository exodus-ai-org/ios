import Foundation
import Models
import Testing

@testable import NetworkingKit

@Suite("APIClient", .serialized)
struct APIClientTests {
    private func makeClient() -> APIClient {
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        return APIClient(session: MockURLProtocol.makeSession(), serverConfig: config)
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

    @Test("POST with no expected response body just checks status")
    func postWithoutDecoding() async throws {
        MockURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        let patch = SettingsPatch(id: "global", providerConfig: nil, providers: nil)
        try await makeClient().post("/api/settings", body: patch)
    }

    @Test("DELETE succeeds on 2xx")
    func deleteSucceeds() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/chat/c1")
            return (200, Data("{\"success\":true}".utf8))
        }
        try await makeClient().delete("/api/chat/c1")
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
