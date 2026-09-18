import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .number(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    /// Best-effort plain-text extraction from a pi-ai message `content` value:
    /// a bare string, or an array of blocks where `{type:"text"|"thinking", text|thinking}`
    /// blocks contribute text and every other block type (image, toolCall, …) is skipped.
    public func extractPlainText() -> String {
        switch self {
        case .string(let s):
            return s
        case .array(let items):
            return
                items
                .compactMap { item -> String? in
                    guard case .object(let obj) = item,
                        case .string(let type)? = obj["type"]
                    else { return nil }
                    if type == "text", case .string(let t)? = obj["text"] { return t }
                    if type == "thinking", case .string(let t)? = obj["thinking"] { return t }
                    return nil
                }
                .joined(separator: "\n")
        default:
            return ""
        }
    }
}
