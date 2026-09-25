import Foundation

public struct MarkdownBlock: Identifiable, Equatable, Sendable {
    public struct ID: Hashable, Sendable {
        public let source: Int
        public let index: Int

        public init(source: Int, index: Int) {
            self.source = source
            self.index = index
        }
    }

    public indirect enum Kind: Equatable, Sendable {
        case paragraph(AttributedString)
        case heading(level: Int, content: AttributedString)
        case list(MarkdownList)
        case blockquote([MarkdownBlock])
        case codeBlock(language: String?, code: String)
        case table(MarkdownTable)
        case thematicBreak
        case image(MarkdownImage)
        case html(String)
    }

    public let id: ID
    public let kind: Kind

    public init(id: ID, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

public struct MarkdownList: Equatable, Sendable {
    public let isOrdered: Bool
    public let startIndex: Int
    public let items: [MarkdownListItem]

    public init(isOrdered: Bool, startIndex: Int, items: [MarkdownListItem]) {
        self.isOrdered = isOrdered
        self.startIndex = startIndex
        self.items = items
    }
}

public struct MarkdownListItem: Identifiable, Equatable, Sendable {
    public enum Checkbox: Equatable, Sendable {
        case checked
        case unchecked
    }

    public let id: Int
    public let checkbox: Checkbox?
    public let blocks: [MarkdownBlock]

    public init(id: Int, checkbox: Checkbox?, blocks: [MarkdownBlock]) {
        self.id = id
        self.checkbox = checkbox
        self.blocks = blocks
    }
}

public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable {
        case leading
        case center
        case trailing
    }

    public let alignments: [Alignment?]
    public let header: [AttributedString]
    public let rows: [[AttributedString]]

    public init(alignments: [Alignment?], header: [AttributedString], rows: [[AttributedString]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }
}

public struct MarkdownImage: Equatable, Sendable {
    public let alt: String
    public let source: String
    public let title: String?

    public init(alt: String, source: String, title: String?) {
        self.alt = alt
        self.source = source
        self.title = title
    }
}
