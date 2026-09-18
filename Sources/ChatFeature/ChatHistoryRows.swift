import Foundation
import Models

/// Rows from `GET /api/chat/:id` are database rows (`createdAt`, `chatId`, `searchText`,
/// per-column `toolName` / `isError` / `details`, …), not the `ChatMessage` shape the SSE
/// stream sends (`timestamp`, no row bookkeeping). The desktop converts them with
/// `convertToUIMessages` (`src/renderer/lib/utils.ts`) before showing them or sending them
/// back as the prior turns of the next `POST /api/chat`; this is the same conversion.
enum ChatHistoryRows {
    static func uiMessages(from rows: [ChatMessage]) -> [ChatMessage] {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return rows.map { uiMessage(from: $0) { withFraction.date(from: $0) ?? plain.date(from: $0) } }
    }

    static func uiMessage(from row: ChatMessage, parseDate: (String) -> Date?) -> ChatMessage {
        var out: [String: JSONValue] = [
            "id": .string(row.id),
            "content": row.raw["content"] ?? .null,
        ]
        if let created = row.raw["createdAt"]?.stringValue, let date = parseDate(created) {
            out["timestamp"] = .number(date.timeIntervalSince1970 * 1000)
        } else if let timestamp = row.raw["timestamp"] {
            out["timestamp"] = timestamp
        }

        let role: String
        switch row.role {
        case "user":
            role = "user"
        case "assistant":
            role = "assistant"
            out["usage"] = row.raw["usage"] ?? .null
            out["api"] = present(row.raw["api"]) ?? .string("")
            out["provider"] = present(row.raw["provider"]) ?? .string("")
            out["model"] = present(row.raw["model"]) ?? .string("")
            out["stopReason"] = present(row.raw["stopReason"]) ?? .string("stop")
            out["errorMessage"] = present(row.raw["errorMessage"])
            out["durationMs"] = present(row.raw["durationMs"])
        default:
            role = "toolResult"
            out["toolCallId"] = present(row.raw["toolCallId"]) ?? .string("")
            out["toolName"] = present(row.raw["toolName"]) ?? .string("")
            out["details"] = row.raw["details"] ?? .null
            out["isError"] = .bool(row.raw["isError"]?.boolValue ?? false)
        }
        out["role"] = .string(role)
        return ChatMessage(id: row.id, role: role, raw: out)
    }

    /// A database NULL (and a missing column) is "absent", like `?? undefined` on the desktop.
    private static func present(_ value: JSONValue?) -> JSONValue? {
        if case .null? = value { return nil }
        return value
    }
}
