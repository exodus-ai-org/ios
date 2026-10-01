import CoreText
import SwiftUI
import UIKit

extension NSAttributedString.Key {
    /// On the thin space that keeps a chip off the word beside it; the value says whether white space was written
    /// there (`MarkdownChipGapAttribute`).
    static let markdownChipGap = NSAttributedString.Key(MarkdownChipGapAttribute.name)
    /// On what holds a chip to the mark that follows it: nothing that was written.
    static let markdownChipJoint = NSAttributedString.Key("app.exodus.markdown.chipJoint")
}

/// How a block's text is set in a text view: what `MarkdownStyledText` takes from its modifiers and environment.
struct MarkdownTextStyle: Equatable {
    var spec: MarkdownFontSpec
    var color: UIColor
    var alignment: NSTextAlignment
    /// The room between two lines; the block's own (`MarkdownLayoutRules.lineGap`) when nil.
    var lineSpacing: CGFloat?
    /// `MarkdownChipMetrics.labelSize` as the text size setting scales it.
    var scaledLabelSize: CGFloat
    var displayScale: CGFloat
    /// The appearance a chip is drawn for: it is a picture, and does not change with the appearance by itself.
    var interfaceStyle: UIUserInterfaceStyle
    /// What a `Font` is resolved in: where the text stands, the environment's.
    var fonts: Font.Context

    init(
        spec: MarkdownFontSpec, color: UIColor = .label, alignment: NSTextAlignment = .natural,
        lineSpacing: CGFloat? = nil, scaledLabelSize: CGFloat = MarkdownChipMetrics.labelSize,
        displayScale: CGFloat = 3, interfaceStyle: UIUserInterfaceStyle = .unspecified,
        fonts: Font.Context = EnvironmentValues().fontResolutionContext
    ) {
        self.spec = spec
        self.color = color
        self.alignment = alignment
        self.lineSpacing = lineSpacing
        self.scaledLabelSize = scaledLabelSize
        self.displayScale = displayScale
        self.interfaceStyle = interfaceStyle
        self.fonts = fonts
    }

    /// The block's own font, as a text view takes it.
    var font: UIFont { MarkdownInlineStyler.uiFont(for: [], spec: spec, in: fonts) }

    /// The room a chip takes on its line, above and below the baseline. `Text` sets a chip's icon in the font of
    /// where the text stands — body, whatever the block's own — lifted as the icon is, and the line is as tall
    /// as that asks: a line with a chip is a little taller than one without. A text view's line has to be the
    /// same, or the text under a chip moves when its block settles.
    var chipLine: (ascent: CGFloat, descent: CGFloat) {
        let metrics = metrics
        let standing = Font.body.resolve(in: fonts).ctFont
        return (
            max(CTFontGetAscent(standing) + max(metrics.iconLift, 0), metrics.centre + metrics.capsuleHeight / 2),
            max(CTFontGetDescent(standing) + max(-metrics.iconLift, 0), metrics.capsuleHeight / 2 - metrics.centre)
        )
    }

    var metrics: MarkdownChipMetrics {
        MarkdownChipMetrics(textSize: spec.pointSize, scaledLabelSize: scaledLabelSize)
    }

    var paragraph: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing ?? spec.pointSize * MarkdownLayoutRules.lineGap(for: spec)
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineBreakStrategy = MarkdownAttributedText.lineBreakStrategy
        return paragraph
    }
}

/// A citation chip in a text view: one character of the text, drawn as the chip.
final class MarkdownChipAttachment: NSTextAttachment {
    let chip: MarkdownChip
    /// Where the capsule stands in the attachment's box, from the baseline up: the box is as tall as the chip's
    /// line, the capsule as tall as the chip.
    let capsule: CGRect

    init(chip: MarkdownChip, capsule: CGRect) {
        self.chip = chip
        self.capsule = capsule
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("a chip is made from its citations")
    }
}

/// A block's inline content as an attributed string for a text view: the text and chips `MarkdownStyledText`
/// draws, with the same fonts, in the same places — and what Copy takes of a selection in it.
@MainActor
enum MarkdownAttributedText {
    /// How SwiftUI's `Text` breaks lines: a text view that breaks them otherwise would move the text when a block
    /// settles.
    nonisolated static let lineBreakStrategy: NSParagraphStyle.LineBreakStrategy = .standard
    /// A line break that was written, in a text view: a line's end, not a paragraph's. A text view sets every
    /// paragraph by itself, and the next one a pixel off where `Text` has its next line.
    nonisolated static let lineBreak = "\u{2028}"
    /// Holds a chip to the mark that follows it: a line may break after an object, and does not between a word
    /// and the mark beside it. A narrow space nothing breaks at, kerned to no width — not a word joiner: with
    /// one between a chip and a full-width mark, a text view sets the line as if the chip had no height.
    nonisolated static let joint = "\u{202F}"

    static func build(
        _ styled: MarkdownInlineStyler.Output, style: MarkdownTextStyle,
        icon: (MarkdownChip) -> MarkdownChipIcon = { _ in .standIn }
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = style.paragraph
        let textFont = UIFont.systemFont(ofSize: style.spec.pointSize)
        for (index, segment) in styled.segments.enumerated() {
            switch segment {
            case .text(let text):
                for run in text.runs {
                    let string = String(text[run.range].characters).replacingOccurrences(of: "\n", with: lineBreak)
                    result.append(NSAttributedString(string: string, attributes: attributes(of: run, style: style, paragraph: paragraph)))
                }
            case .chip(let chip):
                let next = character(after: index, in: styled)
                let metrics = style.metrics
                // A mark that closes the sentence is drawn up to the chip by what its own square leaves empty.
                // Nothing in a text view overlaps an attachment, and an attachment takes no kerning: the chip
                // is that much narrower at its end instead, and the mark stands where the renderer puts it.
                let overhang = MarkdownChipMetrics.overhang(before: next, in: textFont)
                let width = MarkdownChipImage.width(of: chip, style: style) - overhang
                let line = style.chipLine
                let attachment = MarkdownChipAttachment(
                    chip: chip,
                    capsule: CGRect(
                        x: 0, y: metrics.centre - metrics.capsuleHeight / 2, width: width, height: metrics.capsuleHeight))
                attachment.image = MarkdownChipImage.image(
                    of: chip, icon: icon(chip), style: style, overhang: overhang)
                attachment.bounds = CGRect(x: 0, y: -line.descent, width: width, height: line.ascent + line.descent)
                attachment.accessibilityLabel = chip.title
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: style.font, .foregroundColor: style.color, .paragraphStyle: paragraph, .link: chip.link,
                ]
                let placed = NSMutableAttributedString(attachment: attachment)
                placed.addAttributes(attributes, range: NSRange(location: 0, length: placed.length))
                result.append(placed)
                // What follows a chip with no room between them stays on the chip's line.
                if let next, !next.isWhitespace {
                    attributes[.link] = nil
                    attributes[.markdownChipJoint] = true
                    attributes[.kern] = MarkdownChipMetrics.kern(toMake: joint, wide: 0, in: style.font)
                    result.append(NSAttributedString(string: joint, attributes: attributes))
                }
            }
        }
        return result
    }

    /// Text that is not markdown — what the user wrote — as typed.
    static func plain(_ text: String, style: MarkdownTextStyle) -> NSAttributedString {
        NSAttributedString(
            string: text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: lineBreak),
            attributes: [.font: style.font, .foregroundColor: style.color, .paragraphStyle: style.paragraph])
    }

    private static func attributes(
        of run: AttributedString.Runs.Run, style: MarkdownTextStyle, paragraph: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        let intent = run[MarkdownIntentAttribute.self] ?? []
        var attributes: [NSAttributedString.Key: Any] = [
            .font: MarkdownInlineStyler.uiFont(for: intent, spec: style.spec, in: style.fonts),
            .foregroundColor: style.color,
            .paragraphStyle: paragraph,
        ]
        if intent.contains(.code) { attributes[.backgroundColor] = UIColor.tertiarySystemFill }
        if run[AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute.self] != nil
            || run[AttributeScopes.UIKitAttributes.StrikethroughStyleAttribute.self] != nil
        {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if run[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] != nil
            || run[AttributeScopes.UIKitAttributes.UnderlineStyleAttribute.self] != nil
        {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        // Only what a tap may open is a link: anything else in model-written text is text.
        if let link = run.link, case .open(let url) = MarkdownLinkPolicy.action(for: link) { attributes[.link] = url }
        if let spaced = run[MarkdownChipGapAttribute.self] { attributes[.markdownChipGap] = spaced }
        return attributes
    }

    /// What stands right after a segment, when it is text.
    private static func character(after index: Int, in styled: MarkdownInlineStyler.Output) -> Character? {
        guard styled.segments.indices.contains(index + 1), case .text(let next) = styled.segments[index + 1] else {
            return nil
        }
        return next.characters.first
    }

    /// What Copy takes of `range`: the words, without the chips among them. Where a chip stood between two words
    /// that white space kept apart, one space does; a mark that followed a chip follows the word before it. A list
    /// item's marker is copied as itself and a space.
    static func copied(from text: NSAttributedString, in range: NSRange) -> String {
        let whole = NSRange(location: 0, length: text.length)
        let range = NSIntersectionRange(range, whole)
        guard range.length > 0 else { return "" }
        var copied = ""
        /// A chip's room stood for white space: a space is owed once words follow.
        var owesSpace = false
        /// The last thing seen was a chip, with no room after it yet.
        var afterChip = false
        text.enumerateAttributes(in: range) { attributes, piece, _ in
            if let spaced = attributes[.markdownChipGap] as? Bool {
                owesSpace = owesSpace || spaced
                afterChip = false
                return
            }
            if attributes[.attachment] != nil {
                afterChip = true
                return
            }
            if attributes[.markdownChipJoint] != nil { return }
            if let marker = attributes[.markdownListMarker] as? String {
                copied += marker + " "
                owesSpace = false
                afterChip = false
                return
            }
            let words = (text.string as NSString).substring(with: piece)
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .replacingOccurrences(of: lineBreak, with: "\n")
            guard let first = words.first else { return }
            if afterChip { owesSpace = false }
            if owesSpace, let last = copied.last, !last.isWhitespace, !first.isWhitespace { copied += " " }
            owesSpace = false
            afterChip = false
            copied += words
        }
        return copied
    }
}

/// A chip as a picture: its capsule, its icon, its name and count, as `MarkdownStyledText` sets them.
@MainActor
enum MarkdownChipImage {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    private static func name(of chip: MarkdownChip, metrics: MarkdownChipMetrics) -> NSAttributedString {
        let ink = UIColor.secondaryLabel
        let name = NSMutableAttributedString(
            string: chip.label,
            attributes: [.font: MarkdownChipMetrics.font(ofSize: metrics.labelSize), .foregroundColor: ink])
        if let count = chip.countText {
            name.append(
                NSAttributedString(
                    string: "\u{00A0}" + count,
                    attributes: [.font: UIFont.systemFont(ofSize: metrics.labelSize, weight: .regular), .foregroundColor: ink]))
        }
        return name
    }

    /// The icon's side as it is drawn: a picture is whole pixels, and `Text` sets it as wide as it is.
    static func iconSide(_ style: MarkdownTextStyle) -> CGFloat {
        let scale = max(style.displayScale, 1)
        return (style.metrics.iconSide * scale).rounded(.up) / scale
    }

    /// As wide as the chip's runs are in running text: the room inside the capsule, the icon, the name.
    static func width(of chip: MarkdownChip, style: MarkdownTextStyle) -> CGFloat {
        let metrics = style.metrics
        let name = name(of: chip, metrics: metrics)
        let line = CTLineCreateWithAttributedString(name)
        let written = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return metrics.leading + iconSide(style) + metrics.gap + written + metrics.trailing
    }

    /// `overhang`: what the chip is narrower by at its end, for the mark that follows it.
    static func image(
        of chip: MarkdownChip, icon: MarkdownChipIcon, style: MarkdownTextStyle, overhang: CGFloat = 0
    ) -> UIImage {
        let metrics = style.metrics
        let key = key(of: chip, icon: icon, style: style, metrics: metrics, overhang: overhang)
        if let drawn = cache.object(forKey: key) { return drawn }

        // The picture is the chip's whole box on its line; the capsule stands in it where the metrics put it.
        let line = style.chipLine
        let side = iconSide(style)
        let size = CGSize(width: width(of: chip, style: style) - overhang, height: line.ascent + line.descent)
        let middle = line.ascent - metrics.centre
        let capsule = CGRect(
            x: 0, y: middle - metrics.capsuleHeight / 2, width: size.width, height: metrics.capsuleHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = style.displayScale
        format.opaque = false
        let traits = UITraitCollection(userInterfaceStyle: style.interfaceStyle)
        var image = UIImage()
        traits.performAsCurrent {
            image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIColor.quaternarySystemFill.setFill()
                UIBezierPath(roundedRect: capsule, cornerRadius: capsule.height / 2).fill()
                icon.draw(
                    in: CGRect(x: metrics.leading, y: middle - side / 2, width: side, height: side),
                    scale: style.displayScale)
                // The name's middle, as the eye has it, on the capsule's middle.
                let font = MarkdownChipMetrics.font(ofSize: metrics.labelSize)
                let baseline = middle + MarkdownChipMetrics.middle(ofLabel: metrics.labelSize)
                name(of: chip, metrics: metrics)
                    .draw(at: CGPoint(x: metrics.leading + side + metrics.gap, y: baseline - font.ascender))
            }
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func key(
        of chip: MarkdownChip, icon: MarkdownChipIcon, style: MarkdownTextStyle, metrics: MarkdownChipMetrics,
        overhang: CGFloat
    ) -> NSString {
        let face: String
        switch icon {
        case .site(let image): face = "site:\(chip.iconURL?.absoluteString ?? ""):\(image.size.width)x\(image.size.height)"
        case .standIn: face = "standIn"
        }
        return [
            chip.title, face, "\(metrics.labelSize)", "\(style.spec.pointSize)", "\(style.displayScale)",
            "\(style.interfaceStyle.rawValue)", "\(overhang)",
        ].joined(separator: "\u{1F}") as NSString
    }
}
