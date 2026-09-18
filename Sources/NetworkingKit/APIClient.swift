import Foundation
import Models

public struct APIClient: Sendable {
    private let session: URLSession
    private let serverConfig: ServerConfigStore

    public init(session: URLSession = .shared, serverConfig: ServerConfigStore) {
        self.session = session
        self.serverConfig = serverConfig
    }

    public func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(path: path, method: "GET", body: Optional<String>.none)
    }

    public func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        try await send(path: path, method: "POST", body: body)
    }

    public func post<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await send(path: path, method: "POST", body: body, decodeResponse: false)
    }

    public func delete(_ path: String) async throws {
        let _: EmptyResponse = try await send(
            path: path, method: "DELETE", body: Optional<String>.none, decodeResponse: false)
    }

    private func send<Body: Encodable, T: Decodable>(
        path: String,
        method: String,
        body: Body?,
        decodeResponse: Bool = true
    ) async throws -> T {
        guard let base = URL(string: serverConfig.baseURLString) else {
            throw HTTPError(statusCode: 0, code: "INVALID_BASE_URL", message: "Invalid server URL: \(serverConfig.baseURLString)")
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        try Self.throwIfError(data: data, response: response)

        if !decodeResponse {
            return EmptyResponse() as! T
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func throwIfError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data) {
            throw HTTPError(statusCode: http.statusCode, code: envelope.error.code, message: envelope.error.message)
        }
        let fallbackMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
        throw HTTPError(statusCode: http.statusCode, code: "UNKNOWN_ERROR", message: fallbackMessage)
    }
}

private struct EmptyResponse: Decodable {}
