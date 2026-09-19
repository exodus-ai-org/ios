import Foundation
import Models

public enum ChatStatus: String, Sendable, Equatable {
    case idle, submitted, streaming, error
}

public enum ChatStreamUpdate: Sendable {
    case messages([ChatMessage])
    case status(ChatStatus)
    case title(String)
    case finished([ChatMessage])
    case failed(String)
}

public actor ChatStreamManager {
    private struct ActiveStream {
        /// Identifies one `send`. The stream's task carries it back into
        /// `apply`/`finish`/`fail`, which no-op when the entry under `chatId` now
        /// belongs to a newer `send` (the old, cancelled task must not touch it).
        var generation: UUID
        var task: Task<Void, Never>?
        var messages: [ChatMessage]
        var status: ChatStatus
        var continuation: AsyncStream<ChatStreamUpdate>.Continuation?
    }

    private let sseClient: SSEClient
    private var streams: [String: ActiveStream] = [:]

    public init(sseClient: SSEClient = SSEClient()) {
        self.sseClient = sseClient
    }

    public func isStreaming(_ chatId: String) -> Bool {
        guard let stream = streams[chatId] else { return false }
        return stream.status == .submitted || stream.status == .streaming
    }

    /// Replays the current snapshot (messages + status) then live-updates.
    /// Returns `nil` if nothing is in flight for this chat.
    public func attach(_ chatId: String) -> AsyncStream<ChatStreamUpdate>? {
        guard var stream = streams[chatId] else { return nil }
        // Single observer, latest wins: end the previous observer's stream so its
        // consumer's `for await` finishes instead of suspending forever.
        stream.continuation?.finish()
        let (output, continuation) = AsyncStream<ChatStreamUpdate>.makeStream()
        continuation.yield(.messages(stream.messages))
        continuation.yield(.status(stream.status))
        stream.continuation = continuation
        streams[chatId] = stream
        return output
    }

    public func send(
        chatId: String,
        messages: [ChatMessage],
        serverConfig: ServerConfigStore
    ) -> AsyncStream<ChatStreamUpdate> {
        // Retire the previous turn for this chat: stop its task and end its
        // observer's stream so that consumer doesn't stay suspended forever.
        if let previous = streams[chatId] {
            previous.task?.cancel()
            previous.continuation?.finish()
        }

        let generation = UUID()
        let (output, continuation) = AsyncStream<ChatStreamUpdate>.makeStream()
        streams[chatId] = ActiveStream(
            generation: generation, task: nil, messages: messages, status: .submitted, continuation: continuation)
        continuation.yield(.status(.submitted))

        let request = Self.makeRequest(chatId: chatId, messages: messages, serverConfig: serverConfig)
        let sseClient = self.sseClient

        let task = Task { [weak self] in
            guard let request else {
                await self?.fail(chatId: chatId, generation: generation, message: "Invalid server URL")
                return
            }
            do {
                for try await event in sseClient.events(for: request) {
                    await self?.apply(chatId: chatId, generation: generation, event: event)
                }
                await self?.finish(chatId: chatId, generation: generation)
            } catch {
                await self?.fail(
                    chatId: chatId, generation: generation,
                    message: error.localizedDescription)
            }
        }
        streams[chatId]?.task = task
        return output
    }

    /// Ends the turn for `chatId` at the user's request (Stop). It is the only way out of a stream
    /// whose connection went half-open (the request allows an hour of silence, see `makeRequest`).
    ///
    /// The observer is told the turn is idle and handed the messages accumulated so far, then its
    /// stream ends and the entry is removed. A stop is not an error, so nothing is yielded as
    /// `.failed`. Removing the entry here is what makes the cancelled task's own late
    /// `finish`/`fail` no-ops (their generation no longer matches anything): there is deliberately
    /// no second cleanup path that could finish the continuation twice. Does nothing when no
    /// turn is in flight for this chat.
    public func cancel(_ chatId: String) {
        guard let stream = streams[chatId] else { return }
        stream.task?.cancel()
        stream.continuation?.yield(.status(.idle))
        stream.continuation?.yield(.finished(stream.messages))
        stream.continuation?.finish()
        streams[chatId] = nil
    }

    private func apply(chatId: String, generation: UUID, event: ChatSseEvent) {
        guard var stream = streams[chatId], stream.generation == generation else { return }
        switch event {
        case .messageUpdate(let message):
            if let index = stream.messages.firstIndex(where: { $0.id == message.id }) {
                stream.messages[index] = message
            } else {
                stream.messages.append(message)
            }
            stream.status = .streaming
            stream.continuation?.yield(.messages(stream.messages))
        case .done(let messages):
            stream.messages = messages
            stream.continuation?.yield(.messages(stream.messages))
        case .title(let title):
            stream.continuation?.yield(.title(title))
        case .error(let message):
            // A server-sent `error` frame is terminal, like a transport error (the
            // desktop's `consumeStream` throws on it): fail the turn and stop
            // reading. Return before the write-back below so the entry `fail`
            // removes isn't resurrected.
            stream.task?.cancel()
            fail(chatId: chatId, generation: generation, message: message)
            return
        case .toolCallStart, .toolCallEnd, .notice, .unknown:
            break
        }
        streams[chatId] = stream
    }

    private func finish(chatId: String, generation: UUID) {
        guard let stream = streams[chatId], stream.generation == generation else { return }
        stream.continuation?.yield(.status(.idle))
        stream.continuation?.yield(.finished(stream.messages))
        stream.continuation?.finish()
        streams[chatId] = nil
    }

    private func fail(chatId: String, generation: UUID, message: String) {
        guard let stream = streams[chatId], stream.generation == generation else { return }
        stream.continuation?.yield(.status(.error))
        stream.continuation?.yield(.failed(message))
        stream.continuation?.finish()
        streams[chatId] = nil
    }

    private static func makeRequest(
        chatId: String,
        messages: [ChatMessage],
        serverConfig: ServerConfigStore
    ) -> URLRequest? {
        guard let base = URL(string: serverConfig.baseURLString) else { return nil }
        var request = URLRequest(url: base.appendingPathComponent("/api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The server sends no keep-alive frames, and URLSession's default 60 s
        // *inactivity* timeout would kill a turn during a long silent stretch (a
        // reasoning model thinking before its first token, a slow tool call) that
        // the desktop's `fetch` simply waits out. Allow up to an hour of silence.
        request.timeoutInterval = 3600
        struct Body: Encodable {
            let id: String
            let messages: [ChatMessage]
            let advancedTools: [String]
        }
        request.httpBody = try? JSONEncoder().encode(Body(id: chatId, messages: messages, advancedTools: []))
        return request
    }
}
