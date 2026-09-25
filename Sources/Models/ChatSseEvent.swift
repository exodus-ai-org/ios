import Foundation

public enum ChatSseEvent: Sendable {
    case messageUpdate(ChatMessage)
    case toolCallStart(toolCallId: String, toolName: String)
    case toolCallEnd(toolCallId: String, toolName: String, isError: Bool)
    case done(messages: [ChatMessage])
    case title(String)
    case error(String)
    case notice(level: String, message: String)
    /// A tool call paused until the user answers (`POST /api/v1/chat/approval`).
    case approvalRequired(ApprovalRequest)
    /// How that paused call was settled: by an answer here or on the computer, the timeout, or Stop.
    case approvalResolved(runId: String, toolCallId: String, outcome: ApprovalOutcome)
    /// The memories the run read, sent once before its first frame (none when it read none).
    case memoriesUsed(runId: String, memories: [UsedMemory])
    /// Forward-compat: an SSE frame whose `type` this client doesn't recognize
    /// yet. Consumers ignore it instead of the whole stream failing.
    case unknown(type: String)
}

extension ChatSseEvent: Decodable {
    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type = try typeContainer.decode(String.self, forKey: .type)

        struct MessagePayload: Decodable { let message: ChatMessage }
        struct ToolCallStartPayload: Decodable { let toolCallId: String; let toolName: String }
        struct ToolCallEndPayload: Decodable {
            let toolCallId: String
            let toolName: String
            let isError: Bool
        }
        struct DonePayload: Decodable { let messages: [ChatMessage] }
        struct TitlePayload: Decodable { let title: String }
        struct ErrorPayload: Decodable { let error: String }
        struct NoticePayload: Decodable { let level: String; let message: String }

        let single = try decoder.singleValueContainer()
        switch type {
        case "message_update":
            self = .messageUpdate(try single.decode(MessagePayload.self).message)
        case "tool_call_start":
            let p = try single.decode(ToolCallStartPayload.self)
            self = .toolCallStart(toolCallId: p.toolCallId, toolName: p.toolName)
        case "tool_call_end":
            let p = try single.decode(ToolCallEndPayload.self)
            self = .toolCallEnd(toolCallId: p.toolCallId, toolName: p.toolName, isError: p.isError)
        case "done":
            self = .done(messages: try single.decode(DonePayload.self).messages)
        case "title":
            self = .title(try single.decode(TitlePayload.self).title)
        case "error":
            self = .error(try single.decode(ErrorPayload.self).error)
        case "notice":
            let p = try single.decode(NoticePayload.self)
            self = .notice(level: p.level, message: p.message)
        case "approval_required":
            self = .approvalRequired(try single.decode(ApprovalRequest.self))
        case "approval_resolved":
            struct ResolvedPayload: Decodable { let runId: String; let toolCallId: String; let outcome: ApprovalOutcome }
            let p = try single.decode(ResolvedPayload.self)
            self = .approvalResolved(runId: p.runId, toolCallId: p.toolCallId, outcome: p.outcome)
        case "memories_used":
            // One unreadable entry costs only itself, not the rest of the line.
            struct UsedPayload: Decodable { let runId: String; let memories: [JSONValue] }
            let p = try single.decode(UsedPayload.self)
            self = .memoriesUsed(runId: p.runId, memories: p.memories.compactMap(UsedMemory.init(json:)))
        default:
            self = .unknown(type: type)
        }
    }
}

/// `approval_required` (exodus `ApprovalRequiredEvent`): a call that touches a secret outside Exodus, paused between
/// its start and its result. `summary` is the path or command, never contents; `expiresAt` is when the computer
/// declines it unanswered (epoch milliseconds, the computer's clock).
public struct ApprovalRequest: Decodable, Equatable, Sendable {
    public let runId: String
    public let toolCallId: String
    public let toolName: String
    public let summary: String
    public let expiresAt: Date
    /// The computer cut `summary` (at 8000 characters, desktop `capSummary`); `hiddenChars` were left out. Older
    /// computers send neither.
    public let truncated: Bool
    public let hiddenChars: Int?

    public init(
        runId: String, toolCallId: String, toolName: String, summary: String, expiresAt: Date, truncated: Bool = false,
        hiddenChars: Int? = nil
    ) {
        self.runId = runId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.summary = summary
        self.expiresAt = expiresAt
        self.truncated = truncated
        self.hiddenChars = hiddenChars
    }

    private enum CodingKeys: String, CodingKey { case runId, toolCallId, toolName, summary, expiresAt, truncated, hiddenChars }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runId = try container.decode(String.self, forKey: .runId)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        summary = try container.decode(String.self, forKey: .summary)
        expiresAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .expiresAt) / 1000)
        truncated = (try? container.decodeIfPresent(Bool.self, forKey: .truncated)) == true
        hiddenChars = (try? container.decodeIfPresent(Int.self, forKey: .hiddenChars)).flatMap { $0 }
    }
}

/// How a paused call ended (exodus `ApprovalOutcome`). Anything but `allowed` declines it.
public enum ApprovalOutcome: Equatable, Sendable, Decodable {
    case allowed, denied, timedOut, stopped
    /// A value this build does not know: a decline of some kind.
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "allowed": self = .allowed
        case "denied": self = .denied
        case "timed_out": self = .timedOut
        case "stopped": self = .stopped
        default: self = .other(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
}
