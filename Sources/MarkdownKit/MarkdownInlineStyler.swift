import SwiftUI
import UIKit

/// A block's base font as a Dynamic Type text style, so inline code can step down one style (≈ 0.9 em,
/// like the desktop's inline code) instead of being a fixed size.
struct MarkdownFontSpec: Hashable {
    var style: Font.TextStyle
    var weight: Font.Weight?

    static let body = MarkdownFontSpec(style: .body)

    init(style: Font.TextStyle, weight: Font.Weight? = nil) {
        self.style = style
        self.weight = weight
    }

    var font: Font { Self.font(style, weight: weight) }

    var codeFont: Font {
        let codeWeight = weight ?? (style == .headline ? .semibold : nil)
        return Self.font(Self.smaller(style), weight: codeWeight).monospaced()
    }

    private static func font(_ style: Font.TextStyle, weight: Font.Weight?) -> Font {
        weight.map { Font.system(style).weight($0) } ?? Font.system(style)
    }

    static func smaller(_ style: Font.TextStyle) -> Font.TextStyle {
        switch style {
        case .largeTitle: .title
        case .title: .title2
        case .title2: .title3
        case .title3, .headline: .callout
        case .body: .callout
        case .callout: .subheadline
        case .subheadline: .footnote
        case .footnote: .caption
        default: .caption2
        }
    }
}

/// Turns the parser's semantic runs (`inlinePresentationIntent`, `link`) into what `Text` draws: a font per
/// run, a tinted background for inline code and citation chips, a strikethrough.
enum MarkdownInlineStyler {
    struct Output: Equatable {
        var text: AttributedString
        /// The resolved citation numbers, in order, each once.
        var chips: [Int]
    }

    static let codeBackground = Color(uiColor: .tertiarySystemFill)
    static let chipBackground = Color.accentColor.opacity(0.1)
    static let chipFont = Font.caption2
    static let chipPadding = "\u{202F}"

    static func font(for intent: InlinePresentationIntent, spec: MarkdownFontSpec) -> Font {
        var font = intent.contains(.code) ? spec.codeFont : spec.font
        if intent.contains(.stronglyEmphasized) { font = font.bold() }
        if intent.contains(.emphasized) { font = font.italic() }
        return font
    }

    static func style(_ content: AttributedString, spec: MarkdownFontSpec, citations: [Int: MarkdownCitation]) -> Output {
        var result = AttributedString()
        var chips: [Int] = []
        var droppedMarker = false
        var lastWasChip = false

        for run in content.runs {
            var piece = AttributedString(content[run.range])
            if let link = run.link, let number = MarkdownPreprocessor.citationNumber(from: link) {
                guard let citation = citations[number] else {
                    droppedMarker = true
                    continue
                }
                if lastWasChip {
                    result.append(AttributedString(" ", attributes: container(spec.font)))
                } else if let last = result.characters.last, !last.isWhitespace {
                    result.append(AttributedString("\u{2009}", attributes: container(spec.font)))
                }
                result.append(chip(citation))
                if !chips.contains(number) { chips.append(number) }
                droppedMarker = false
                lastWasChip = true
                continue
            }
            if droppedMarker, result.characters.last?.isWhitespace ?? true, piece.characters.first == " " {
                piece.characters.removeFirst()
            }
            if lastWasChip, piece.characters.first?.isPunctuation == true {
                result.characters.removeLast()
            }
            droppedMarker = false
            lastWasChip = false

            let intent = run.inlinePresentationIntent ?? []
            piece.inlinePresentationIntent = nil
            piece.font = font(for: intent, spec: spec)
            if intent.contains(.code) { piece.backgroundColor = codeBackground }
            if intent.contains(.strikethrough) { piece.strikethroughStyle = .single }
            result.append(piece)
        }
        return Output(text: result, chips: chips)
    }

    private static func container(_ font: Font) -> AttributeContainer {
        var container = AttributeContainer()
        container.font = font
        return container
    }

    private static func chip(_ citation: MarkdownCitation) -> AttributedString {
        var chip = AttributedString("\(chipPadding)\(citation.chipLabel)\(chipPadding)")
        chip.font = chipFont
        chip.backgroundColor = chipBackground
        chip.link = MarkdownCitation.citeURL(citation.number)
        return chip
    }
}
