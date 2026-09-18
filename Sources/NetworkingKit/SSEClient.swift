import Foundation
import Models

public struct SSEClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func events(for request: URLRequest) -> AsyncThrowingStream<ChatSseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: body) {
                            throw HTTPError(statusCode: http.statusCode, code: envelope.error.code, message: envelope.error.message)
                        }
                        throw HTTPError(statusCode: http.statusCode, code: "UNKNOWN_ERROR", message: "HTTP \(http.statusCode)")
                    }
                    for try await line in bytes.lines {
                        if let event = SSEFrameParsing.decodeEvent(fromLine: line) {
                            continuation.yield(event)
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
