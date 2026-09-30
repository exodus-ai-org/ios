import Foundation
import Markdown

/// A text that may hold markdown or HTML, as the words it says: markup taken off, what it wraps kept, white space
/// collapsed to single spaces. For a line that shows someone else's text small and plain — a search result's
/// snippet — where `**`, `#` and `<strong>` would be noise. The desktop uses `remove-markdown` for the same.
public enum MarkdownPlainText {
    public static func strip(_ text: String) -> String {
        var walker = PlainTextWalker()
        walker.visit(Document(parsing: text))
        return collapse(walker.text)
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private struct PlainTextWalker: MarkupWalker {
    var text = ""

    mutating func defaultVisit(_ markup: any Markup) {
        descendInto(markup)
        // The end of a block is the end of a word.
        if markup is any BlockMarkup { text += " " }
    }

    mutating func visitText(_ text: Text) { self.text += text.string }

    mutating func visitInlineCode(_ inlineCode: InlineCode) { text += inlineCode.code }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) { text += codeBlock.code + " " }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) { text += " " }

    mutating func visitLineBreak(_ lineBreak: LineBreak) { text += " " }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        descendInto(tableCell)
        text += " "
    }

    // A tag is markup; what stands between two of them is text of its own and is visited as such.
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {}

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        text += Self.withoutTags(html.rawHTML) + " "
    }

    private static func withoutTags(_ html: String) -> String {
        var result = ""
        var inTag = false
        for character in html {
            switch character {
            case "<": inTag = true
            case ">" where inTag: inTag = false
            default: if !inTag { result.append(character) }
            }
        }
        return result
    }
}
