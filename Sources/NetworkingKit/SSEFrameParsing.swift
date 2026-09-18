import Foundation
import Models

public enum SSEFrameParsing {
    public static func decodeEvent(fromLine line: String, decoder: JSONDecoder = JSONDecoder()) -> ChatSseEvent? {
        guard line.hasPrefix("data: ") else { return nil }
        let jsonPart = line.dropFirst("data: ".count).trimmingCharacters(in: .whitespaces)
        guard !jsonPart.isEmpty, let data = jsonPart.data(using: .utf8) else { return nil }
        return try? decoder.decode(ChatSseEvent.self, from: data)
    }
}
