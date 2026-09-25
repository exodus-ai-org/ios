import Foundation
import Models

public enum ChatStatus: String, Sendable, Equatable {
    case idle, submitted, streaming, error
}

/// A non-fatal heads-up a tool asked the server to relay (an expired key that only degraded a result).
/// `message` is the server's own text: data to show as it is, never a string to translate or parse.
public struct StreamNotice: Hashable, Sendable {
    public enum Level: Hashable, Sendable { case info, warning }

    public let level: Level
    public let message: String

    public init(level: Level, message: String) {
        self.level = level
        self.message = message
    }

    /// The server's own normaliser: `info` is info, and anything else is a warning.
    public init(level: String, message: String) {
        self.init(level: level == "info" ? .info : .warning, message: message)
    }
}

public enum ChatStreamUpdate: Sendable {
    case messages([ChatMessage])
    case status(ChatStatus)
    case title(String)
    case finished([ChatMessage])
    case failed(String)
    case notice(StreamNotice)
    /// A tool call paused for the user's answer, or how it was settled.
    case approval(ApprovalEvent)
    /// The memories a run read (`memories_used`).
    case memoriesUsed(runId: String, memories: [UsedMemory])
    /// An `update_memory` call just ended, done or failed: memory on the computer may read differently now.
    case memoryChanged
}

/// The approval frames of a run, in the order they arrived.
public enum ApprovalEvent: Equatable, Sendable {
    case required(ApprovalRequest)
    case resolved(runId: String, toolCallId: String, outcome: ApprovalOutcome)
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
        /// Notices already relayed this turn: a 12-stop itinerary that hits the same expired key
        /// reports it once, not per place (the desktop's `seenNotices`).
        var seenNotices: Set<StreamNotice> = []
        /// Event types this client does not know, reported once per turn rather than per frame.
        var seenUnknownTypes: Set<String> = []
        /// Every approval frame of this turn, replayed to an observer that attaches later (the chat reopened while a
        /// call waits): the card must still be there to answer.
        var approvals: [ApprovalEvent] = []
        /// The run's `memories_used`, replayed the same way: the used-memories line of the run in flight.
        var memoriesUsed: [(runId: String, memories: [UsedMemory])] = []
    }

    private let sseClient: SSEClient
    private let reporter: LogReporter?
    private var streams: [String: ActiveStream] = [:]

    public init(sseClient: SSEClient = SSEClient(), reporter: LogReporter? = nil) {
        self.sseClient = sseClient
        self.reporter = reporter ?? sseClient.reporter
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
        for approval in stream.approvals { continuation.yield(.approval(approval)) }
        for used in stream.memoriesUsed { continuation.yield(.memoriesUsed(runId: used.runId, memories: used.memories)) }
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
                await self?.fail(
                    chatId: chatId, generation: generation,
                    message: String(
                        localized: "ios:networking.error.invalidServerUrl", defaultValue: "Invalid server URL",
                        comment: "Short error when the stored server address cannot be parsed."))
                return
            }
            do {
                try await Self.stream(request: request, sseClient: sseClient, serverConfig: serverConfig) { event in
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
    ///
    /// Returns `true` only when an active stream was actually found and cancelled here, `false`
    /// when there was nothing to do. This matters to a caller that wants to know it truly stopped
    /// something: a turn's own `finish()`/`fail()` can run and remove this entry before the
    /// caller's `await` on this very method resumes (its update is only buffered, not yet drained
    /// by whatever `for await` loop owns the observer), so `isStreaming`/a locally cached "in
    /// flight" flag can be stale by the time this call actually lands. The `Bool` return is the
    /// only way to learn, atomically, whether this call itself did anything.
    @discardableResult
    public func cancel(_ chatId: String) -> Bool {
        guard let stream = streams[chatId] else { return false }
        stream.task?.cancel()
        stream.continuation?.yield(.status(.idle))
        stream.continuation?.yield(.finished(stream.messages))
        stream.continuation?.finish()
        streams[chatId] = nil
        return true
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
        case .notice(let level, let message):
            let notice = StreamNotice(level: level, message: message)
            if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, stream.seenNotices.insert(notice).inserted {
                stream.continuation?.yield(.notice(notice))
            }
        case .unknown(let type):
            if stream.seenUnknownTypes.insert(type).inserted {
                reporter.report(
                    .warn, scope: "sse", message: "Unknown SSE event type",
                    attributes: ["eventType": .string(String(type.prefix(40)))])
            }
        case .approvalRequired(let request):
            stream.approvals.append(.required(request))
            stream.continuation?.yield(.approval(.required(request)))
        case .approvalResolved(let runId, let toolCallId, let outcome):
            let event = ApprovalEvent.resolved(runId: runId, toolCallId: toolCallId, outcome: outcome)
            stream.approvals.append(event)
            stream.continuation?.yield(.approval(event))
        case .memoriesUsed(let runId, let memories):
            stream.memoriesUsed.append((runId, memories))
            stream.continuation?.yield(.memoriesUsed(runId: runId, memories: memories))
        case .toolCallEnd(_, let toolName, _) where toolName == "update_memory":
            stream.continuation?.yield(.memoryChanged)
        case .toolCallStart, .toolCallEnd:
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

    /// Runs the SSE request; on the computer's own lock (423, not this device's — see
    /// `ServerConnection.unlockComputer`) unlocks it and tries the same request once more. The
    /// status check inside `SSEClient.events` happens before it yields anything, so this can
    /// never retry mid-stream — only ever before the first event, real or not.
    private static func stream(
        request: URLRequest, sseClient: SSEClient, serverConfig: ServerConfigStore,
        onEvent: (ChatSseEvent) async -> Void
    ) async throws {
        do {
            for try await event in sseClient.events(for: request) {
                await onEvent(event)
            }
        } catch let error as HTTPError where error.code == "APP_LOCKED" {
            guard let connection = serverConfig.connection,
                await connection.unlockComputer(session: sseClient.session)
            else { throw error }
            for try await event in sseClient.events(for: request) {
                await onEvent(event)
            }
        }
    }

    private static func makeRequest(
        chatId: String,
        messages: [ChatMessage],
        serverConfig: ServerConfigStore
    ) -> URLRequest? {
        guard let base = URL(string: serverConfig.baseURLString) else { return nil }
        var request = URLRequest(url: base.appendingPathComponent("/api/v1/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization = serverConfig.authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
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
