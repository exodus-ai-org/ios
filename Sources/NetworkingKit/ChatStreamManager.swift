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
        streams[chatId]?.task?.cancel()

        let (output, continuation) = AsyncStream<ChatStreamUpdate>.makeStream()
        streams[chatId] = ActiveStream(task: nil, messages: messages, status: .submitted, continuation: continuation)
        continuation.yield(.status(.submitted))

        let request = Self.makeRequest(chatId: chatId, messages: messages, serverConfig: serverConfig)
        let sseClient = self.sseClient

        let task = Task { [weak self] in
            guard let request else {
                await self?.fail(chatId: chatId, message: "Invalid server URL")
                return
            }
            do {
                for try await event in sseClient.events(for: request) {
                    await self?.apply(chatId: chatId, event: event)
                }
                await self?.finish(chatId: chatId)
            } catch {
                await self?.fail(chatId: chatId, message: (error as? LocalizedError)?.errorDescription ?? String(describing: error))
            }
        }
        streams[chatId]?.task = task
        return output
    }

    private func apply(chatId: String, event: ChatSseEvent) {
        guard var stream = streams[chatId] else { return }
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
            stream.continuation?.yield(.failed(message))
        case .toolCallStart, .toolCallEnd, .notice, .unknown:
            break
        }
        streams[chatId] = stream
    }

    private func finish(chatId: String) {
        guard let stream = streams[chatId] else { return }
        stream.continuation?.yield(.status(.idle))
        stream.continuation?.yield(.finished(stream.messages))
        stream.continuation?.finish()
        streams[chatId] = nil
    }

    private func fail(chatId: String, message: String) {
        guard let stream = streams[chatId] else { return }
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
