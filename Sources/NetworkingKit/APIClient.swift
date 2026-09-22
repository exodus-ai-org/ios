import Foundation
import Models

public struct APIClient: Sendable {
    private let session: URLSession
    private let serverConfig: ServerConfigStore

    public init(session: URLSession = .shared, serverConfig: ServerConfigStore) {
        self.session = session
        self.serverConfig = serverConfig
    }

    public func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(path: path, query: query, method: "GET", body: Optional<String>.none)
    }

    public func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        try await send(path: path, method: "POST", body: body)
    }

    public func post<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await send(path: path, method: "POST", body: body, decodeResponse: false)
    }

    public func put<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await send(path: path, method: "PUT", body: body, decodeResponse: false)
    }

    public func delete(_ path: String) async throws {
        let _: EmptyResponse = try await send(
            path: path, method: "DELETE", body: Optional<String>.none, decodeResponse: false)
    }

    private func send<Body: Encodable, T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Body?,
        decodeResponse: Bool = true
    ) async throws -> T {
        let bases = serverConfig.baseURLCandidates
        var unreachable: Error?
        for (index, base) in bases.enumerated() {
            let url = try makeURL(base: base, path: path, query: query)
            do {
                return try await attempt(
                    url: url, method: method, body: body, bases: bases, decodeResponse: decodeResponse)
            } catch let error as URLError where error.isUnreachableHost && index < bases.count - 1 {
                unreachable = error
                continue
            } catch let error as HTTPError where error.code == "APP_LOCKED" {
                // The computer's own lock, not ours: our token already proves who this device
                // is, so no PIN is needed to lift it — see `POST /api/v1/lock/unlock` (exodus's
                // `src/main/lib/server/routes/lock.ts`). One retry, on the same base that just
                // answered (it is reachable, just locked); any failure along the way — no paired
                // connection, Face ID declined, the unlock call itself failing — surfaces this
                // original "locked" error, not a new one.
                return try await unlockAndRetry(
                    url: url, method: method, body: body, bases: bases, decodeResponse: decodeResponse,
                    original: error)
            }
        }
        throw unreachable ?? invalidBaseURL()
    }

    private func attempt<Body: Encodable, T: Decodable>(
        url: URL, method: String, body: Body?, bases: [String], decodeResponse: Bool
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let authorization = serverConfig.authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        // With somewhere else to try, don't wait the default minute for an
        // address that is not on this network.
        if bases.count > 1 { request.timeoutInterval = 15 }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401, request.value(forHTTPHeaderField: "Authorization") != nil {
                // Our token was refused: this device was revoked on the computer.
                // Forget the pairing so the app returns to the pairing screen.
                serverConfig.connection?.unpair()
            } else if let host = url.host {
                serverConfig.connection?.noteReachable(host: host)
            }
        }
        try Self.throwIfError(data: data, response: response)

        if !decodeResponse {
            return EmptyResponse() as! T
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// `ServerConnection.unlockComputer()` does the work (and is `ChatStreamManager`'s way in
    /// too, for the same 423 on `POST /api/v1/chat`): normally no fresh Face ID, since by the
    /// time a request can even reach `lockGate` to be told "locked", it already carried the
    /// token that released. One retry, on the same base that just answered (it is reachable,
    /// just locked); any failure along the way surfaces this original error, not a new one.
    private func unlockAndRetry<Body: Encodable, T: Decodable>(
        url: URL, method: String, body: Body?, bases: [String], decodeResponse: Bool, original: HTTPError
    ) async throws -> T {
        guard let connection = serverConfig.connection, await connection.unlockComputer(session: session)
        else { throw original }
        return try await attempt(url: url, method: method, body: body, bases: bases, decodeResponse: decodeResponse)
    }

    private func makeURL(base: String, path: String, query: [URLQueryItem]) throws -> URL {
        guard let baseURL = URL(string: base) else { throw invalidBaseURL() }
        var url = baseURL.appendingPathComponent(path)
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw invalidBaseURL()
            }
            components.percentEncodedQuery = query
                .map { "\(Self.encodeQueryComponent($0.name))=\(Self.encodeQueryComponent($0.value ?? ""))" }
                .joined(separator: "&")
            guard let withQuery = components.url else { throw invalidBaseURL() }
            url = withQuery
        }
        return url
    }

    /// The error for a server address, or a URL built from it, that cannot be used.
    private func invalidBaseURL() -> HTTPError {
        HTTPError(
            statusCode: 0, code: "INVALID_BASE_URL",
            message: String(localized: "Invalid server URL: \(serverConfig.baseURLString)"))
    }

    /// Percent-encodes one query name or value. `+ & = # ? ;` are encoded too (unlike
    /// `urlQueryAllowed`), so a value such as `c++ & 100%` reaches the server as typed.
    private static func encodeQueryComponent(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#?;")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    private static func throwIfError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data) {
            throw HTTPError(statusCode: http.statusCode, code: envelope.error.code, message: envelope.error.message)
        }
        // `String(data: Data(), encoding: .utf8)` is `""`, not nil, so an empty body (a proxy's bare
        // 502) must be caught explicitly or the user gets a blank alert. Text that has content is
        // kept exactly as the server sent it.
        let text = String(data: data, encoding: .utf8) ?? ""
        let message =
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "HTTP \(http.statusCode)") : text
        throw HTTPError(statusCode: http.statusCode, code: "UNKNOWN_ERROR", message: message)
    }
}

private struct EmptyResponse: Decodable {}

extension URLError {
    /// The address, not the request, is the problem: worth trying the next one.
    var isUnreachableHost: Bool {
        switch code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut,
            .networkConnectionLost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }
}
