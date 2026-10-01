import Foundation
import Models

public struct APIClient: Sendable {
    private let session: URLSession
    private let serverConfig: ServerConfigStore
    /// Where this app's own errors go; also told of every answered request, so waiting reports flush.
    public let reporter: LogReporter?

    public init(session: URLSession = .shared, serverConfig: ServerConfigStore, reporter: LogReporter? = nil) {
        self.session = session
        self.serverConfig = serverConfig
        self.reporter = reporter
    }

    public func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(path: path, query: query, method: "GET", body: Optional<String>.none)
    }

    /// A GET whose answer is bytes, not JSON (a generated image from `/api/v1/media/…`): the same addresses, token,
    /// unlock-and-retry and reporting as every other request.
    public func data(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await send(path: path, query: query, method: "GET", body: Optional<String>.none)
    }

    /// A GET whose answer is a file served as it is (the artifact sandbox's page and assets), with the type the
    /// server gave it.
    public func file(_ path: String, query: [URLQueryItem] = []) async throws -> FetchedFile {
        try await send(path: path, query: query, method: "GET", body: Optional<String>.none)
    }

    public func post<Body: Encodable, T: Decodable>(
        _ path: String, body: Body, timeout: TimeInterval? = nil
    ) async throws -> T {
        try await send(path: path, method: "POST", body: body, timeout: timeout)
    }

    public func post<Body: Encodable>(_ path: String, body: Body, timeout: TimeInterval? = nil) async throws {
        let _: EmptyResponse = try await send(
            path: path, method: "POST", body: body, decodeResponse: false, timeout: timeout)
    }

    public func put<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await send(path: path, method: "PUT", body: body, decodeResponse: false)
    }

    public func patch<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await send(path: path, method: "PATCH", body: body, decodeResponse: false)
    }

    public func delete(_ path: String, query: [URLQueryItem] = []) async throws {
        let _: EmptyResponse = try await send(
            path: path, query: query, method: "DELETE", body: Optional<String>.none, decodeResponse: false)
    }

    private func send<Body: Encodable, T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Body?,
        decodeResponse: Bool = true,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        do {
            let result: T = try await sendTryingEachBase(
                path: path, query: query, method: method, body: body, decodeResponse: decodeResponse,
                timeout: timeout)
            reporter?.noteReachable()
            return result
        } catch {
            reportFailure(error, path: path)
            throw error
        }
    }

    /// Status and path only: never the query, a body, or the server's message (it can echo what was sent).
    private func reportFailure(_ error: Error, path: String) {
        guard let reporter, path != LogReporter.path else { return }
        if error is CancellationError { return }
        switch error {
        case let http as HTTPError where http.statusCode > 0:
            reporter.noteReachable()
            reporter.report(
                http.statusCode >= 500 ? .error : .warn, scope: "api", message: "HTTP \(http.statusCode) \(path)",
                attributes: ["status": .int(http.statusCode), "path": .string(path)])
        case let url as URLError:
            if url.code == .cancelled { return }
            reporter.report(
                .warn, scope: "api", message: "No response \(path)",
                attributes: ["path": .string(path), "urlError": .int(url.code.rawValue)])
        case let decoding as DecodingError:
            reporter.report(
                .error, scope: "api", message: "Undecodable response \(path)",
                attributes: ["path": .string(path), "decoding": .string(LogRedaction.describe(decoding))])
        default:
            break
        }
    }

    private func sendTryingEachBase<Body: Encodable, T: Decodable>(
        path: String,
        query: [URLQueryItem],
        method: String,
        body: Body?,
        decodeResponse: Bool,
        timeout: TimeInterval?
    ) async throws -> T {
        let bases = serverConfig.baseURLCandidates
        let idempotent = ["GET", "HEAD", "PUT", "DELETE"].contains(method)
        var unreachable: Error?
        for (index, base) in bases.enumerated() {
            let url = try makeURL(base: base, path: path, query: query)
            do {
                return try await attempt(
                    url: url, method: method, body: body, bases: bases, decodeResponse: decodeResponse,
                    timeout: timeout)
            } catch let error as URLError
                where index < bases.count - 1
                && (idempotent ? error.worthRetryingIdempotent : error.requestNeverSent)
            {
                // A POST or PATCH that may have reached the computer is never sent again elsewhere.
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
                    timeout: timeout, original: error)
            }
        }
        throw unreachable ?? invalidBaseURL()
    }

    private func attempt<Body: Encodable, T: Decodable>(
        url: URL, method: String, body: Body?, bases: [String], decodeResponse: Bool, timeout: TimeInterval?
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
        if let timeout {
            request.timeoutInterval = timeout
        } else if bases.count > 1 {
            request.timeoutInterval = 15
        }

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
        if let raw = data as? T, T.self == Data.self { return raw }
        if T.self == FetchedFile.self {
            let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
            return FetchedFile(data: data, contentType: type) as! T
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// `ServerConnection.unlockComputer()` does the work (and is `ChatStreamManager`'s way in
    /// too, for the same 423 on `POST /api/v1/chat`): normally no fresh Face ID, since by the
    /// time a request can even reach `lockGate` to be told "locked", it already carried the
    /// token that released. One retry, on the same base that just answered (it is reachable,
    /// just locked); any failure along the way surfaces this original error, not a new one.
    private func unlockAndRetry<Body: Encodable, T: Decodable>(
        url: URL, method: String, body: Body?, bases: [String], decodeResponse: Bool, timeout: TimeInterval?,
        original: HTTPError
    ) async throws -> T {
        guard let connection = serverConfig.connection, await connection.unlockComputer(session: session)
        else { throw original }
        return try await attempt(
            url: url, method: method, body: body, bases: bases, decodeResponse: decodeResponse, timeout: timeout)
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
            message: String(
                localized: "ios:networking.error.invalidServerUrlWithAddress",
                defaultValue: "Invalid server URL: \(serverConfig.baseURLString)",
                comment: "Error. %@ is the address the user typed."))
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
            throw HTTPError(
                statusCode: http.statusCode, code: envelope.error.code, message: envelope.error.message,
                params: envelope.error.params)
        }
        // `String(data: Data(), encoding: .utf8)` is `""`, not nil, so an empty body (a proxy's bare
        // 502) must be caught explicitly or the user gets a blank alert. Text that has content is
        // kept exactly as the server sent it.
        let text = String(data: data, encoding: .utf8) ?? ""
        let message =
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(
                localized: "ios:networking.error.httpStatus", defaultValue: "HTTP \(http.statusCode)",
                comment: "Fallback error text for a server response without a message. %lld is the HTTP status code.")
            : text
        throw HTTPError(statusCode: http.statusCode, code: "UNKNOWN_ERROR", message: message)
    }
}

private struct EmptyResponse: Decodable {}

/// A file's bytes and its `Content-Type`, as `APIClient.file` read them. Never decoded from JSON: `Decodable` only so
/// it can travel the same request path as every other answer.
public struct FetchedFile: Decodable, Sendable, Equatable {
    public let data: Data
    public let contentType: String?

    public init(data: Data, contentType: String?) {
        self.data = data
        self.contentType = contentType
    }

    public init(from decoder: Decoder) throws {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A file is not JSON"))
    }
}

extension URLError {
    /// No byte of the request reached the computer at this address: safe to send it anywhere else, whatever it does.
    var requestNeverSent: Bool {
        switch code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
            .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return true
        default:
            return false
        }
    }

    /// The request may have reached the computer, but an idempotent one can be repeated.
    var worthRetryingIdempotent: Bool { requestNeverSent || code == .timedOut || code == .networkConnectionLost }
}
