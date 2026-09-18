import Models

extension ChatMessage {
    /// The text a reader sees for this message: `displayText` (`JSONValue.extractPlainText()`)
    /// without the model's `thinking` blocks. A reasoning model's raw chain-of-thought would
    /// otherwise land in the same bubble as its answer.
    ///
    /// Mirrors `extractPlainText()` otherwise: a plain string is returned as is, a block array
    /// contributes its `text` blocks joined with a newline, and every other block type (image,
    /// toolCall, unknown) and any other content shape contributes nothing.
    var answerText: String {
        switch content {
        case .string(let text):
            return text
        case .array(let blocks):
            return
                blocks
                .compactMap { block -> String? in
                    guard case .object(let object) = block,
                        case .string(let type)? = object["type"],
                        type == "text",
                        case .string(let text)? = object["text"]
                    else { return nil }
                    return text
                }
                .joined(separator: "\n")
        default:
            return ""
        }
    }
}
