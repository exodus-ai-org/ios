import SwiftUI
import UIKit

/// A block's base font as a Dynamic Type text style, so inline code can step down one style (≈ 0.9 em,
/// like the desktop's inline code) instead of being a fixed size.
///
/// The transcript reads a step smaller than the system's styles — 16 pt where body is 17 — at every Dynamic
/// Type size: the size is the style's own, as the system scales it, times `scale`.
struct MarkdownFontSpec: Hashable {
    var style: Font.TextStyle
    var weight: Font.Weight?

    static let body = MarkdownFontSpec(style: .body)
    /// Body text at the default text size, in points; what the layout's `em` is at that size. The owner's choice:
    /// 18 and then 17 (the system's own) read as too large beside the rest of the app.
    static let bodySize: CGFloat = 16
    /// What every style's size is multiplied by: `bodySize` over the system's body, 17.
    static let scale: CGFloat = bodySize / 17

    init(style: Font.TextStyle, weight: Font.Weight? = nil) {
        self.style = style
        self.weight = weight
    }

    var pointSize: CGFloat { Self.pointSize(style, in: .current) }

    /// A style's size at a text size setting: the system's, scaled.
    static func pointSize(_ style: Font.TextStyle, in traits: UITraitCollection) -> CGFloat {
        UIFont.preferredFont(forTextStyle: uiStyle(style), compatibleWith: traits).pointSize * scale
    }

    var font: Font { Self.font(style, weight: weight) }

    var codeFont: Font {
        let codeWeight = weight ?? (style == .headline ? .semibold : nil)
        return Self.font(Self.smaller(style), weight: codeWeight).monospaced()
    }

    private static func font(_ style: Font.TextStyle, weight: Font.Weight?) -> Font {
        let size = pointSize(style, in: .current)
        // A headline is semibold by itself, as the system's is.
        return Font.system(size: size, weight: weight ?? (style == .headline ? .semibold : .regular))
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

    static func uiStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

/// The transcript's running text, for what stands beside an answer and is not markdown: the user's own message.
public enum MarkdownTypography {
    public static var body: Font { MarkdownFontSpec.body.font }
    /// The room between two lines of `body`, in points at the current text size.
    public static var bodyLineSpacing: CGFloat {
        MarkdownFontSpec.body.pointSize * MarkdownLayoutRules.lineGap(for: .body)
    }
}

/// One citation chip: a site's icon and name in a capsule, standing for one citation or for several that
/// came side by side ("swift.org +2"). A tap opens the first.
struct MarkdownChip: Equatable {
    /// The citations it stands for, in order, each once.
    let numbers: [Int]
    /// The first citation's label, with no place in it a line may break at: a chip is never split across two
    /// lines, it goes to the next line whole.
    let label: String
    let iconURL: URL?
    /// Tried when `iconURL` does not load.
    let iconFallbackURL: URL?

    /// How many more citations it stands for than the one it names: "+2"; nothing for a chip of one.
    var countText: String? { numbers.count > 1 ? "+\(numbers.count - 1)" : nil }
    /// What the chip reads: its label and its count, which holds on to the label.
    var title: String { countText.map { "\(label)\u{00A0}\($0)" } ?? label }
    var link: URL { MarkdownCitation.citeURL(numbers[0]) }

    /// Where a line may break: white space, a zero-width space, a hyphen, a soft hyphen.
    static let breakingScalars: Set<Unicode.Scalar> = [
        " ", "\t", "\n", "\r", "\u{2009}", "\u{200A}", "\u{200B}", "\u{2028}", "\u{2029}", "\u{3000}", "-", "\u{2010}",
        "\u{00AD}",
    ]

    /// A label as a chip carries it: its spaces do not break, its hyphens neither, and what only marks a place to
    /// break at is gone.
    static func unbreakable(_ label: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in label.unicodeScalars {
            switch scalar {
            case "\u{200B}", "\u{00AD}": continue
            case "-", "\u{2010}": out.append("\u{2011}")
            default: out.append(breakingScalars.contains(scalar) ? "\u{00A0}" : scalar)
            }
        }
        return String(out)
    }

    init(numbers: [Int], label: String, iconURL: URL?, iconFallbackURL: URL? = nil) {
        self.numbers = numbers
        self.label = label
        self.iconURL = iconURL
        self.iconFallbackURL = iconFallbackURL
    }

    init(_ citations: [MarkdownCitation]) {
        self.init(
            numbers: citations.map(\.number),
            label: Self.unbreakable(citations[0].chipLabel),
            iconURL: citations[0].iconURL, iconFallbackURL: citations[0].iconFallbackURL)
    }
}

/// What a run was written as — strong, emphasised, code — kept beside the `Font` it was given: a text view needs
/// the same font as a `UIFont`, and a `Font` cannot be read back.
enum MarkdownIntentAttribute: AttributedStringKey {
    typealias Value = InlinePresentationIntent
    static let name = "app.exodus.markdown.intent"
}

/// On the thin space that keeps a chip off the word beside it. Its value: whether white space was written there,
/// which is what a copied selection puts back in the chip's place.
enum MarkdownChipGapAttribute: AttributedStringKey {
    typealias Value = Bool
    static let name = "app.exodus.markdown.chipGap"
}

/// Turns the parser's semantic runs (`inlinePresentationIntent`, `link`) into what is drawn: text with a
/// font per run, a tinted background for inline code and a strikethrough — and, between the text, the
/// citation chips, which `MarkdownStyledText` draws as capsules.
enum MarkdownInlineStyler {
    enum Segment: Equatable {
        case text(AttributedString)
        case chip(MarkdownChip)
    }

    struct Output: Equatable {
        var segments: [Segment]
        /// The resolved citation numbers, in order, each once.
        var chips: [Int]
    }

    static let codeBackground = Color(uiColor: .tertiarySystemFill)
    /// What keeps a chip off the word next to it.
    static let chipGap: Character = "\u{2009}"

    static func font(for intent: InlinePresentationIntent, spec: MarkdownFontSpec) -> Font {
        var font = intent.contains(.code) ? spec.codeFont : spec.font
        if intent.contains(.stronglyEmphasized) { font = font.bold() }
        if intent.contains(.emphasized) { font = font.italic() }
        return font
    }

    /// `font(for:spec:)` as a text view takes it: the very font `Text` draws with, not one made to look like it
    /// — a face a hair wider moves every word after it.
    static func uiFont(for intent: InlinePresentationIntent, spec: MarkdownFontSpec, in fonts: Font.Context) -> UIFont {
        font(for: intent, spec: spec).resolve(in: fonts).ctFont as UIFont
    }

    /// `underlinesLinks`: where the tint is black and white (the neutral tone) a link's colour is the text's, so
    /// it is underlined to read as one. A phone has no hover to show it on, as the desktop does.
    static func style(
        _ content: AttributedString, spec: MarkdownFontSpec, citations: [Int: MarkdownCitation],
        underlinesLinks: Bool = false
    ) -> Output {
        var builder = Builder(spec: spec)
        for run in content.runs {
            if let link = run.link, let number = MarkdownPreprocessor.citationNumber(from: link) {
                builder.marker(citations[number])
                continue
            }
            var piece = AttributedString(content[run.range])
            let intent = run.inlinePresentationIntent ?? []
            piece.inlinePresentationIntent = nil
            if !intent.isEmpty { piece[MarkdownIntentAttribute.self] = intent }
            piece.font = font(for: intent, spec: spec)
            if intent.contains(.code) { piece.backgroundColor = codeBackground }
            if intent.contains(.strikethrough) { piece.strikethroughStyle = .single }
            if underlinesLinks, run.link != nil { piece.underlineStyle = .single }
            builder.text(piece)
        }
        return builder.finish()
    }

    /// Lays text and chips out in order. A chip stays open while citations keep coming, with nothing but
    /// white space between them; the text that ends it decides what stands between the two.
    private struct Builder {
        let spec: MarkdownFontSpec
        var segments: [Segment] = []
        var chips: [Int] = []
        var text = AttributedString()
        /// The citations of the chip being built.
        var open: [MarkdownCitation] = []
        /// White space seen after the open chip: the chip's own if another citation follows, the text's if not.
        var held = AttributedString()
        /// A marker that resolved to nothing was dropped just before: the space after it is one too many.
        var dropped = false

        mutating func marker(_ citation: MarkdownCitation?) {
            guard let citation else {
                if open.isEmpty { dropped = true }
                return
            }
            if open.isEmpty {
                // One thin space before a chip, whatever was written there; none before a chip that opens its
                // block, which sits on the text's edge.
                var spaced = false
                while text.characters.last?.isWhitespace == true {
                    text.characters.removeLast()
                    spaced = true
                }
                if !text.characters.isEmpty || !segments.isEmpty { text.append(gap(spaced: spaced)) }
                flushText()
            }
            held = AttributedString()
            dropped = false
            if !open.contains(where: { $0.number == citation.number }) { open.append(citation) }
            if !chips.contains(citation.number) { chips.append(citation.number) }
        }

        mutating func text(_ piece: AttributedString) {
            var piece = piece
            if !open.isEmpty {
                if piece.characters.allSatisfy(\.isWhitespace) {
                    held.append(piece)
                    return
                }
                segments.append(.chip(MarkdownChip(open)))
                open = []
                // The same thin space after it — and nothing before a mark of punctuation, which follows the
                // chip as it would follow a word.
                var spaced = !held.characters.isEmpty
                while piece.characters.first?.isWhitespace == true {
                    piece.characters.removeFirst()
                    spaced = true
                }
                if piece.characters.first?.isPunctuation != true { text.append(gap(spaced: spaced)) }
                held = AttributedString()
            } else if dropped, text.characters.last?.isWhitespace ?? segments.isEmpty, piece.characters.first == " " {
                piece.characters.removeFirst()
            }
            dropped = false
            text.append(piece)
        }

        mutating func finish() -> Output {
            if !open.isEmpty { segments.append(.chip(MarkdownChip(open))) }
            flushText()
            return Output(segments: segments, chips: chips)
        }

        private mutating func flushText() {
            guard !text.characters.isEmpty else { return }
            segments.append(.text(text))
            text = AttributedString()
        }

        /// `spaced`: white space was written where the gap stands.
        private func gap(spaced: Bool) -> AttributedString {
            var container = AttributeContainer()
            container.font = spec.font
            container[MarkdownChipGapAttribute.self] = spaced
            return AttributedString(String(MarkdownInlineStyler.chipGap), attributes: container)
        }
    }
}
