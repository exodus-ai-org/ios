import Foundation

public enum ChatSseEvent: Sendable {
    case messageUpdate(ChatMessage)
    case toolCallStart(toolCallId: String, toolName: String)
    case toolCallEnd(toolCallId: String, toolName: String, isError: Bool)
    case done(messages: [ChatMessage])
    case title(String)
    case error(String)
    case notice(level: String, message: String)
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
        default:
            self = .unknown(type: type)
        }
    }
}
