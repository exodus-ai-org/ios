import Foundation
import Models

public enum SSEFrameParsing {
    public enum Frame: Sendable {
        case event(ChatSseEvent)
        /// A `data:` frame this app could not read: what may be reported about it, never its payload.
        case undecodable(type: String?, reason: String, bytes: Int)
        case ignored
    }

    public static func decodeEvent(fromLine line: String, decoder: JSONDecoder = JSONDecoder()) -> ChatSseEvent? {
        if case .event(let event) = frame(fromLine: line, decoder: decoder) { return event }
        return nil
    }

    public static func frame(fromLine line: String, decoder: JSONDecoder = JSONDecoder()) -> Frame {
        guard line.hasPrefix("data: ") else { return .ignored }
        let jsonPart = line.dropFirst("data: ".count).trimmingCharacters(in: .whitespaces)
        guard !jsonPart.isEmpty, let data = jsonPart.data(using: .utf8) else { return .ignored }
        do {
            return .event(try decoder.decode(ChatSseEvent.self, from: data))
        } catch {
            struct TypeOnly: Decodable { let type: String }
            let type = (try? decoder.decode(TypeOnly.self, from: data))?.type
            let reason =
                if let decoding = error as? DecodingError {
                    LogRedaction.describe(decoding)
                } else {
                    String(describing: Swift.type(of: error))
                }
            return .undecodable(type: type.map { String($0.prefix(40)) }, reason: reason, bytes: data.count)
        }
    }
}

/// A stream's unreadable frames, reported once when the stream ends: the first one's details and the total.
struct SSEFrameIssues {
    private(set) var count = 0
    private var first: (type: String?, reason: String, bytes: Int)?

    mutating func note(type: String?, reason: String, bytes: Int) {
        count += 1
        if first == nil { first = (type, reason, bytes) }
    }

    func report(path: String, reporter: LogReporter?) {
        guard let first else { return }
        var attributes: [String: LogReporter.Value] = [
            "path": .string(path), "decoding": .string(first.reason), "bytes": .int(first.bytes),
            "frames": .int(count),
        ]
        if let type = first.type { attributes["eventType"] = .string(type) }
        reporter.report(.error, scope: "sse", message: "Undecodable SSE frames", attributes: attributes)
    }
}
