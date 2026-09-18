import Foundation

/// A chat message as sent by the server. Decodes into a raw `[String: JSONValue]`
/// dictionary rather than a narrow struct — the server's own schema comment
/// (`messageSchema` in `schemas/chat.ts`) explains why: prior turns carry
/// provider-specific fields (`details`, `toolCallId`, `toolName`, `isError`, `usage`,
/// `cost`, …) that must round-trip unmodified when this message is echoed back
/// inside the next `POST /api/chat` request body, or the server loses tool-call
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

    /// Builds a freshly-composed outgoing user message — the shape the composer
    /// hands to `ChatStreamManager.send`. Every other `ChatMessage` in a
    /// conversation was decoded from the server and must never be constructed
    /// this way (it would drop fields the server needs on round-trip).
    public static func userMessage(id: String, text: String, timestampMs: Double) -> ChatMessage {
        ChatMessage(
            id: id,
            role: "user",
            raw: [
                "id": .string(id),
                "role": .string("user"),
                "content": .string(text),
                "timestamp": .number(timestampMs)
            ]
        )
    }
}
