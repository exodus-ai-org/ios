import Foundation

/// The Health workspace's "ask about this": a question typed there travels to Chat with the day's numbers as a
/// leading fenced block — ```` ```exodus-health ````, the JSON, ```` ``` ````, a blank line, the question. Plain text, like
/// `QuotedText`, so the computer and every provider read it as what it is; the transcript reads it back with `split`
/// to draw the numbers as a card. Only a block that opens the message counts.
public enum HealthContext {
    public static let infoString = "exodus-health"
    private static var opening: String { "```" + infoString + "\n" }  // l10n:ignore: markdown syntax
    private static let closing = "\n```"  // l10n:ignore: markdown syntax

    public static func block(json: String) -> String { opening + json + closing }

    public static func compose(json: String, question: String) -> String {
        block(json: json) + "\n\n" + question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func compose<T: Encodable>(_ value: T, question: String) throws -> String {
        let data = try HealthWire.encoder().encode(value)
        return compose(json: String(decoding: data, as: UTF8.self), question: question)
    }

    public static func split(_ text: String) -> (json: String?, body: String) {
        guard text.hasPrefix(opening) else { return (nil, text) }
        let rest = text.dropFirst(opening.count)
        // The block ends at the first line that is exactly the closing fence.
        var end = rest.range(of: closing + "\n")
        if end == nil, rest.hasSuffix(closing) { end = rest.range(of: closing, options: .backwards) }
        guard let end else { return (nil, text) }
        let json = String(rest[..<end.lowerBound])
        let body = rest[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (json, body)
    }
}
