import Foundation
import Models

public struct SSEClient: Sendable {
    /// Not private: `ChatStreamManager` reads it to pass along to
    /// `ServerConnection.unlockComputer(session:)` on a 423, so the retry uses the same session
    /// (and so the same pin) this client's events came from.
    let session: URLSession
    let reporter: LogReporter?

    public init(session: URLSession = .shared, reporter: LogReporter? = nil) {
        self.session = session
        self.reporter = reporter
    }

    public func events(for request: URLRequest) -> AsyncThrowingStream<ChatSseEvent, Error> {
        AsyncThrowingStream { continuation in
            let reporter = self.reporter
            let path = request.url?.path ?? ""
            let task = Task {
                var issues = SSEFrameIssues()
                defer { issues.report(path: path, reporter: reporter) }
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: body) {
                            throw HTTPError(statusCode: http.statusCode, code: envelope.error.code, message: envelope.error.message)
                        }
                        throw HTTPError(
                            statusCode: http.statusCode, code: "UNKNOWN_ERROR",
                            message: String(
                                localized: "ios:networking.error.httpStatus", defaultValue: "HTTP \(http.statusCode)",
                                comment:
                                    "Fallback error text for a server response without a message. %lld is the HTTP status code."
                            ))
                    }
                    for try await line in bytes.lines {
                        switch SSEFrameParsing.frame(fromLine: line) {
                        case .event(let event):
                            continuation.yield(event)
                        case .undecodable(let type, let reason, let bytes):
                            issues.note(type: type, reason: reason, bytes: bytes)
                        case .ignored:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
