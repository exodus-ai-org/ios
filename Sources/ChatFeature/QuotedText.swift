import Foundation

/// "Ask about this": a piece of a message the user selected travels with their next message as a markdown quote — a
/// block of `> ` lines, a blank line, the question. Plain text, so the computer and every provider read it as what it
/// is and nothing about a message's shape changes; the transcript reads it back with `split` to draw the quote as
/// one. The desktop's `packages/shared/src/utils/quoted-text.ts`, held to the same vectors.
enum QuotedText {
    /// A selection longer than this is cut: it is a pointer, not an upload.
    static let maxLength = 2000

    /// The selection as the lines of a markdown quote.
    static func block(_ selection: String) -> String {
        var text = selection.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .map { $0.replacing(/\s+$/, with: "") }
            .joined(separator: "\n")
        if text.count > maxLength { text = String(text.prefix(maxLength)) + "…" }
        return text.components(separatedBy: "\n")
            .map { line in
                if line.isEmpty { return ">" }  // l10n:ignore: markdown syntax
                return "> " + line  // l10n:ignore: markdown syntax
            }
            .joined(separator: "\n")
    }

    /// What is sent: the quote, then what the user typed about it.
    static func compose(quote: String, text: String) -> String {
        block(quote) + "\n\n" + text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A message's text as its quote and the rest. The quote is the run of lines that open the message with `>`;
    /// blank lines after it belong to neither.
    static func split(_ text: String) -> (quote: String?, body: String) {
        let lines = text.components(separatedBy: "\n")
        var end = 0
        while end < lines.count, lines[end].hasPrefix(">") { end += 1 }
        guard end > 0 else { return (nil, text) }
        let quote = lines[..<end].map { line in
            String(line.dropFirst(line.hasPrefix("> ") ? 2 : 1))
        }.joined(separator: "\n")
        var from = end
        while from < lines.count, lines[from].trimmingCharacters(in: .whitespaces).isEmpty { from += 1 }
        return (quote, lines[from...].joined(separator: "\n"))
    }
}
