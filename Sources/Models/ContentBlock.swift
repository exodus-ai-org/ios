import Foundation

/// One block of a message's `content`; `unknown` keeps anything this client does not model, so nothing is dropped.
public enum ContentBlock: Equatable, Sendable {
    case text(String)
    case thinking(String)
    case toolCall(id: String, name: String, arguments: [String: JSONValue])
    case image(mimeType: String, dataURL: String)
    case unknown(JSONValue)

    public init(_ value: JSONValue) {
        guard case .object(let object) = value, case .string(let type)? = object["type"] else {
            self = .unknown(value)
            return
        }
        switch type {
        case "text":
            if let text = object["text"]?.stringValue {
                self = .text(text)
            } else {
                self = .unknown(value)
            }
        case "thinking":
            if let thinking = object["thinking"]?.stringValue {
                self = .thinking(thinking)
            } else {
                self = .unknown(value)
            }
        case "toolCall":
            if let id = object["id"]?.stringValue, let name = object["name"]?.stringValue {
                var arguments: [String: JSONValue] = [:]
                if case .object(let given)? = object["arguments"] { arguments = given }
                self = .toolCall(id: id, name: name, arguments: arguments)
            } else {
                self = .unknown(value)
            }
        case "image":
            if let data = object["data"]?.stringValue, let mimeType = object["mimeType"]?.stringValue {
                // The desktop stores the attachment's data URL in `data`; bare base64 gets its prefix here.
                let dataURL = data.hasPrefix("data:") ? data : "data:\(mimeType);base64,\(data)"
                self = .image(mimeType: mimeType, dataURL: dataURL)
            } else {
                self = .unknown(value)
            }
        default:
            self = .unknown(value)
        }
    }
}
