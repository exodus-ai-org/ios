import Foundation

/// A chat message as sent by the server. Decodes into a raw `[String: JSONValue]`
/// dictionary rather than a narrow struct — the server's own schema comment
/// (`messageSchema` in `schemas/chat.ts`) explains why: prior turns carry
/// provider-specific fields (`details`, `toolCallId`, `toolName`, `isError`, `usage`,
/// `cost`, …) that must round-trip unmodified when this message is echoed back
/// inside the next `POST /api/v1/chat` request body, or the server loses tool-call
/// pairing information it needs to talk to the LLM provider.
public struct ChatMessage: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var role: String
    public var raw: [String: JSONValue]

    public init(id: String, role: String, raw: [String: JSONValue]) {
        self.id = id
        self.role = role
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: JSONValue].self)
        guard case .string(let id)? = object["id"] else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "ChatMessage missing string 'id'")
        }
        guard case .string(let role)? = object["role"] else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "ChatMessage missing string 'role'")
        }
        self.id = id
        self.role = role
        self.raw = object
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public var content: JSONValue { raw["content"] ?? .null }
    public var displayText: String { content.extractPlainText() }
    public var isError: Bool { raw["isError"]?.boolValue ?? false }
    public var toolName: String? { raw["toolName"]?.stringValue }
    public var timestampMs: Double? { raw["timestamp"]?.numberValue }

    /// The id of the run this message belongs to (a run's user message is its own run); `nil` on rows from before runs.
    public var runId: String? { raw["runId"]?.stringValue }
    public var toolCallId: String? { raw["toolCallId"]?.stringValue }
    public var details: JSONValue? {
        if case .null? = raw["details"] { return nil }
        return raw["details"]
    }
    public var durationMs: Double? { raw["durationMs"]?.numberValue }
    public var stopReason: String? { raw["stopReason"]?.stringValue }
    public var errorMessage: String? { raw["errorMessage"]?.stringValue }

    /// `content` as typed blocks: a string is one text block, and a shape the wire never sends is one `.unknown`.
    public var contentBlocks: [ContentBlock] {
        switch raw["content"] {
        case .string(let text)?: [.text(text)]
        case .array(let blocks)?: blocks.map(ContentBlock.init)
        case .null?, nil: []
        case let other?: [.unknown(other)]
        }
    }

    /// Builds a freshly-composed outgoing user message — the shape the composer
    /// hands to `ChatStreamManager.send`. Every other `ChatMessage` in a
    /// conversation was decoded from the server and must never be constructed
    /// this way (it would drop fields the server needs on round-trip).
    public static func userMessage(id: String, text: String, timestampMs: Double) -> ChatMessage {
        userMessage(id: id, content: .string(text), timestampMs: timestampMs)
    }

    /// The same, for content that is already wire-shaped — a string, or an array of text and image blocks —
    /// as when a question is asked again (Regenerate) and must keep its attachments.
    public static func userMessage(id: String, content: JSONValue, timestampMs: Double) -> ChatMessage {
        ChatMessage(
            id: id,
            role: "user",
            raw: [
                "id": .string(id),
                "runId": .string(id),  // a user message opens its own run, stamped locally like the desktop client does
                "role": .string("user"),
                "content": content,
                "timestamp": .number(timestampMs)
            ]
        )
    }
}
