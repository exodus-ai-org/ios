import Foundation
import Markdown

public struct MarkdownParseResult: Equatable, Sendable {
    public let blocks: [MarkdownBlock]
    public let citations: [Int]
    /// Markup types this renderer has no view for, shown as their plain text instead.
    public var unhandledKinds: [String] = []

    public init(blocks: [MarkdownBlock], citations: [Int], unhandledKinds: [String] = []) {
        self.blocks = blocks
        self.citations = citations
        self.unhandledKinds = unhandledKinds
    }
}

public enum MarkdownParser {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        parse(text, source: 0).blocks
    }

    public static func parse(_ text: String, source: Int) -> MarkdownParseResult {
        let (rewritten, citations) = MarkdownPreprocessor.rewriteCitations(text)
        var document = MarkdownPreprocessor.parseDocument(rewritten)
        if rewritten.contains("~"), let escaped = MarkdownPreprocessor.escapeLoneTilde(rewritten, document: document),
            escaped != rewritten
        {
            document = MarkdownPreprocessor.parseDocument(escaped)
        }
        var unhandled: [String] = []
        let parsed = blocks(document.children, source: source, unhandled: &unhandled)
        return MarkdownParseResult(blocks: parsed, citations: citations, unhandledKinds: unhandled)
    }

    static func blocks(_ children: MarkupChildren, source: Int, unhandled: inout [String]) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        for child in children {
            guard let kind = kind(of: child, unhandled: &unhandled) else { continue }
            result.append(MarkdownBlock(id: .init(source: source, index: result.count), kind: kind))
        }
        return result
    }

    // Nested blocks are numbered within their container, so a container's value never depends on its position.
    private static func kind(of markup: Markup, unhandled: inout [String]) -> MarkdownBlock.Kind? {
        switch markup {
        case let paragraph as Paragraph:
            if let image = soleImage(paragraph) { return .image(image) }
            // What is left of a paragraph that was nothing but `<br>` is nothing: it is not drawn.
            let content = HTMLBreak.trimming(inline(paragraph.children))
            return content.characters.allSatisfy(\.isWhitespace) ? nil : .paragraph(content)
        case let heading as Heading:
            return .heading(level: heading.level, content: inline(heading.children))
        case let list as UnorderedList:
            return .list(
                MarkdownList(isOrdered: false, startIndex: 1, items: items(list.listItems, unhandled: &unhandled)))
        case let list as OrderedList:
            return .list(
                MarkdownList(
                    isOrdered: true, startIndex: Int(list.startIndex), items: items(list.listItems, unhandled: &unhandled))
            )
        case let quote as BlockQuote:
            return .blockquote(blocks(quote.children, source: 0, unhandled: &unhandled))
        case let code as CodeBlock:
            return .codeBlock(language: code.language?.nilIfEmpty, code: trimmingFinalNewline(code.code))
        case let table as Table:
            return .table(self.table(table))
        case is ThematicBreak:
            return .thematicBreak
        case let html as HTMLBlock:
            let text = HTMLBreak.replacing(in: trimmingFinalNewline(html.rawHTML))
            return text.allSatisfy(\.isWhitespace) ? nil : .html(text)
        default:
            let name = String(describing: type(of: markup))
            if !unhandled.contains(name) { unhandled.append(name) }
            let text = markup.format()
            return text.isEmpty ? nil : .paragraph(AttributedString(text))
        }
    }

    private static func items(_ items: some Sequence<ListItem>, unhandled: inout [String]) -> [MarkdownListItem] {
        items.enumerated().map { index, item in
            let checkbox: MarkdownListItem.Checkbox? =
                switch item.checkbox {
                case .checked: .checked
                case .unchecked: .unchecked
                case nil: nil
                }
            return MarkdownListItem(
                id: index, checkbox: checkbox, blocks: blocks(item.children, source: 0, unhandled: &unhandled))
        }
    }

    private static func table(_ table: Table) -> MarkdownTable {
        let alignments: [MarkdownTable.Alignment?] = table.columnAlignments.map {
            switch $0 {
            case .left: .leading
            case .center: .center
            case .right: .trailing
            case nil: nil
            }
        }
        let header = table.head.cells.map { inline($0.children) }
        let rows = table.body.rows.map { row in Array(row.cells.map { inline($0.children) }) }
        return MarkdownTable(alignments: alignments, header: Array(header), rows: Array(rows))
    }

    private static func soleImage(_ paragraph: Paragraph) -> MarkdownImage? {
        var image: Image?
        for child in paragraph.children {
            if let found = child as? Image, image == nil {
                image = found
            } else if let text = child as? Text, text.string.allSatisfy(\.isWhitespace) {
                continue
            } else if child is SoftBreak {
                continue
            } else {
                return nil
            }
        }
        guard let image, let source = image.source, !source.isEmpty else { return nil }
        return MarkdownImage(alt: image.plainText, source: source, title: image.title?.nilIfEmpty)
    }

    private static func trimmingFinalNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    static func inline(_ children: MarkupChildren) -> AttributedString {
        var builder = InlineBuilder()
        for child in children { builder.visit(child) }
        builder.flush()
        return builder.build()
    }
}

/// `<br>`, `<br/>`, `<br />`, in any case: the one piece of HTML a model writes into markdown as a matter of
/// course, and it means a line break. Every other tag is shown as the text it is.
enum HTMLBreak {
    nonisolated(unsafe) private static let tag = #/<br\s*/?>/#.ignoresCase()

    static func matches(_ html: String) -> Bool {
        html.trimmingCharacters(in: .whitespaces).wholeMatch(of: tag) != nil
    }

    /// An HTML block's text with its breaks as line breaks, and none of them left at its start or its end.
    static func replacing(in html: String) -> String {
        guard html.contains("<") else { return html }
        let replaced = html.replacing(tag, with: "\n")
        guard replaced != html else { return html }
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A break at the start or the end of a paragraph would draw an empty line there.
    static func trimming(_ content: AttributedString) -> AttributedString {
        guard content.characters.first?.isNewline == true || content.characters.last?.isNewline == true else {
            return content
        }
        var content = content
        while content.characters.first?.isNewline == true { content.characters.removeFirst() }
        while content.characters.last?.isNewline == true { content.characters.removeLast() }
        return content
    }
}

// Appending many small AttributedStrings is slow; collect plain text and styled scalar ranges, then style once.
private struct InlineBuilder {
    struct Run {
        let scalars: Int
        let intent: InlinePresentationIntent
        let link: URL?
    }

    var text = ""
    var runs: [Run] = []
    var intent: InlinePresentationIntent = []
    var link: URL?
    // cmark splits text at unmatched delimiters; autolinking needs the whole run.
    var pending = ""

    func build() -> AttributedString {
        var result = AttributedString(text)
        let scalars = result.unicodeScalars
        var index = scalars.startIndex
        for run in runs {
            let end = scalars.index(index, offsetBy: run.scalars)
            if !run.intent.isEmpty { result[index..<end].inlinePresentationIntent = run.intent }
            if let link = run.link { result[index..<end].link = link }
            index = end
        }
        return result
    }

    mutating func visit(_ markup: Markup) {
        if let node = markup as? Text {
            pending += node.string
            return
        }
        flush()
        switch markup {
        case is SoftBreak:
            append(" ")
        case is LineBreak:
            append("\n")
        case let code as InlineCode:
            with(.code) { $0.append(code.code) }
        case is Emphasis:
            with(.emphasized) { $0.visitChildren(markup) }
        case is Strong:
            with(.stronglyEmphasized) { $0.visitChildren(markup) }
        case is Strikethrough:
            with(.strikethrough) { $0.visitChildren(markup) }
        case let anchor as Link:
            withLink(anchor.destination.flatMap(URL.init(string:))) { $0.visitChildren(markup) }
        case let image as Image:
            withLink(image.source.flatMap(URL.init(string:))) { $0.append(image.plainText) }
        case let html as InlineHTML:
            append(HTMLBreak.matches(html.rawHTML) ? "\n" : html.rawHTML)
        default:
            if markup.childCount > 0 {
                visitChildren(markup)
            } else {
                append(markup.format())
            }
        }
    }

    mutating func visitChildren(_ markup: Markup) {
        for child in markup.children { visit(child) }
        flush()
    }

    mutating func flush() {
        guard !pending.isEmpty else { return }
        let text = pending
        pending = ""
        appendText(text)
    }

    mutating func with(_ added: InlinePresentationIntent, _ body: (inout InlineBuilder) -> Void) {
        let saved = intent
        intent.insert(added)
        body(&self)
        intent = saved
    }

    mutating func withLink(_ url: URL?, _ body: (inout InlineBuilder) -> Void) {
        let saved = link
        if let url { link = url }
        body(&self)
        link = saved
    }

    mutating func append(_ string: String) {
        guard !string.isEmpty else { return }
        text += string
        let count = string.unicodeScalars.count
        if let last = runs.last, last.intent == intent, last.link == link {
            runs[runs.count - 1] = Run(scalars: last.scalars + count, intent: intent, link: link)
        } else {
            runs.append(Run(scalars: count, intent: intent, link: link))
        }
    }

    mutating func appendText(_ string: String) {
        guard link == nil, !intent.contains(.code) else { return append(string) }
        for (piece, url) in Autolink.split(string) {
            let saved = link
            link = url
            append(piece)
            link = saved
        }
    }
}

// GFM's extended autolinks: swift-markdown does not enable cmark-gfm's autolink extension.
enum Autolink {
    private static let prefixes = [Array("https://"), Array("http://"), Array("www.")]

    static func split(_ text: String) -> [(String, URL?)] {
        guard text.contains("://") || text.localizedCaseInsensitiveContains("www.") else { return [(text, nil)] }
        let chars = Array(text)
        var pieces: [(String, URL?)] = []
        var plainStart = 0
        var index = 0
        while index < chars.count {
            let boundary = index == 0 || chars[index - 1].isWhitespace || "*_~(".contains(chars[index - 1])
            if boundary, let prefix = prefixLength(chars, at: index) {
                var end = index
                while end < chars.count, !chars[end].isWhitespace, chars[end] != "<" { end += 1 }
                end = trimmedEnd(chars, from: index, to: end)
                let token = String(chars[index..<end])
                let host = token.dropFirst(prefix)
                if host.contains("."), !host.hasPrefix("."),
                    let url = URL(string: prefix == 4 ? "http://" + token : token)
                {
                    if plainStart < index { pieces.append((String(chars[plainStart..<index]), nil)) }
                    pieces.append((token, url))
                    plainStart = end
                    index = end
                    continue
                }
            }
            index += 1
        }
        if plainStart < chars.count { pieces.append((String(chars[plainStart...]), nil)) }
        return pieces
    }

    private static func prefixLength(_ chars: [Character], at index: Int) -> Int? {
        for prefix in prefixes where index + prefix.count <= chars.count {
            if zip(chars[index..<(index + prefix.count)], prefix).allSatisfy({ $0.lowercased() == String($1) }) {
                return prefix.count
            }
        }
        return nil
    }

    private static func trimmedEnd(_ chars: [Character], from start: Int, to end: Int) -> Int {
        var end = end
        while end > start {
            let last = chars[end - 1]
            if "?!.,:*_~".contains(last) {
                end -= 1
            } else if last == ")",
                chars[start..<end].filter({ $0 == ")" }).count > chars[start..<end].filter({ $0 == "(" }).count
            {
                end -= 1
            } else {
                break
            }
        }
        return end
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
