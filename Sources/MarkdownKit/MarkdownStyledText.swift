import CoreText
import SwiftUI
import UIKit

/// Where citation chips get their sites' icons. MarkdownKit fetches nothing by itself: whoever shows an answer
/// hands in a loader that applies its own rules for what may be fetched, and how.
public struct MarkdownCitationIcons: Sendable {
    /// An icon already in memory, so a chip that was drawn before is drawn whole at once.
    public var cached: @Sendable (URL) -> UIImage?
    /// Fetches an icon; `nil` when it cannot be had, and the chip draws the default glyph.
    public var load: @Sendable (URL) async -> UIImage?

    public init(cached: @escaping @Sendable (URL) -> UIImage?, load: @escaping @Sendable (URL) async -> UIImage?) {
        self.cached = cached
        self.load = load
    }

    /// No icons: every chip draws the default glyph.
    public static let none = MarkdownCitationIcons(cached: { _ in nil }, load: { _ in nil })

    /// The icon from its own address, else from the fallback; nil when neither answers.
    public func image(url: URL, fallback: URL?) async -> UIImage? {
        if let image = await load(url) { return image }
        guard let fallback, fallback != url else { return nil }
        return await load(fallback)
    }
}

extension EnvironmentValues {
    @Entry public var markdownCitationIcons: MarkdownCitationIcons = .none
    /// Whether a link is underlined. A host whose tint is the text's own colour (a black and white tone) turns
    /// it on, since the colour no longer says what is a link; elsewhere the tint does.
    @Entry public var markdownUnderlinesLinks = false
    /// "Ask about this": offered first in the edit menu of a selection, handed the selected words. Nil: not offered.
    @Entry public var markdownAskAbout: MarkdownAskAction?
}

/// Marks the runs of one chip, so the renderer can put one capsule behind them.
struct MarkdownChipAttribute: TextAttribute {
    let id: Int
    /// How far the capsule reaches past its runs at the end: what the mark after it was drawn up by.
    var overhang: CGFloat = 0
}

/// How a chip is drawn: small print on a faint fill, set into running text without taking over from it. The
/// owner's rule: a citation says where a sentence comes from, it is not what the sentence says.
enum MarkdownChipStyle {
    static let fill = Color(uiColor: .quaternarySystemFill)
    static let ink = Color(uiColor: .secondaryLabel)
    static let weight = Font.Weight.medium
    /// The count after the name ("+2") is lighter than the name.
    static let countWeight = Font.Weight.regular
    /// Drawn where a site's icon would be, for a source that has none or whose icon has not come.
    static let standInSymbol = "globe"
    /// What the room inside the capsule is made of: a narrow space that a line does not break at, made as wide
    /// as it should be by kerning.
    static let space = "\u{202F}"
    /// Holds what stands on either side of it to one line: an image in text is a word by itself.
    static let joiner = "\u{2060}"
}

/// How a chip is set into a line of text of a given size: its sizes, the room inside its capsule, and where it
/// stands on the line. All of it follows the label's size, which follows the text size setting.
struct MarkdownChipMetrics: Equatable {
    /// The label at the default text size, in points.
    static let labelSize: CGFloat = 9
    /// The largest a label gets, as a share of the text it stands in: the capsule stays inside the line.
    static let largestShare: CGFloat = 0.6
    /// The capsule's middle over the baseline, as a share of the text's size. Latin text has its middle at about
    /// 0.31 (between the x-height's and the capitals'), Han text at about 0.38 (its square's): this is between.
    static let centreShare: CGFloat = 0.35

    let labelSize: CGFloat
    let iconSide: CGFloat
    let capsuleHeight: CGFloat
    /// From the capsule's edge to the icon, from the icon to the label, from the label to the capsule's edge.
    let leading: CGFloat
    let gap: CGFloat
    let trailing: CGFloat
    /// The capsule's middle, above the baseline of the text.
    let centre: CGFloat
    /// How far the label's baseline and the icon's foot are raised off the text's baseline.
    let labelLift: CGFloat
    let iconLift: CGFloat

    /// `scaledLabelSize` is `labelSize` as the text size setting scales it.
    init(textSize: CGFloat, scaledLabelSize: CGFloat) {
        let label = min(scaledLabelSize, textSize * Self.largestShare)
        let unit = label / Self.labelSize
        labelSize = label
        iconSide = 11 * unit
        capsuleHeight = 15 * unit
        leading = 2 * unit
        gap = 3 * unit
        trailing = 5 * unit
        centre = textSize * Self.centreShare
        labelLift = centre - Self.middle(ofLabel: label)
        iconLift = centre - iconSide / 2
    }

    static func font(ofSize size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .medium) }

    /// The middle of a label as the eye has it, above its baseline: between the middle of its small letters and
    /// that of its capitals.
    static func middle(ofLabel size: CGFloat) -> CGFloat {
        let font = font(ofSize: size)
        return (font.xHeight + font.capHeight) / 4
    }

    /// The most a mark is drawn up by, as a share of the text's size.
    static let largestOverhang: CGFloat = 0.2
    /// What is left between the capsule and the mark's ink.
    static let punctuationGap: CGFloat = 0.5

    /// From where a character starts to where its ink does, in `font` (or in the font that has it).
    static func leadingBearing(of character: Character, in font: UIFont) -> CGFloat {
        let text = NSAttributedString(string: String(character), attributes: [.font: font])
        let ink = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(text), .useGlyphPathBounds)
        return ink.isNull ? 0 : max(ink.minX, 0)
    }

    /// How far a mark of punctuation that follows a chip is drawn up to it. A full-width stop has its ink in a
    /// corner of its square: as it is, it would stand a fifth of a character away from the chip it closes.
    static func overhang(before next: Character?, in font: UIFont) -> CGFloat {
        guard let next, next.isPunctuation else { return 0 }
        let bearing = leadingBearing(of: next, in: font)
        return min(max(bearing - punctuationGap, 0), font.pointSize * largestOverhang)
    }

    /// What to kern `character` by for it to be `width` wide in `font`.
    static func kern(toMake character: String, wide width: CGFloat, in font: UIFont) -> CGFloat {
        width - (character as NSString).size(withAttributes: [.font: font]).width
    }
}

/// What stands at the head of a chip: the site's own icon once it is in hand, the default glyph until then and
/// when none can be had. A chip always has one or the other, in the same square, so it keeps its width when its
/// icon arrives and chips in one line look alike.
enum MarkdownChipIcon: Equatable {
    case site(UIImage)
    case standIn

    /// `loaded` is keyed by the chip's first address, whichever address gave the image.
    static func resolve(
        url: URL?, fallback: URL?, loaded: [URL: UIImage], cached: (URL) -> UIImage?
    ) -> MarkdownChipIcon {
        guard let url, let image = loaded[url] ?? cached(url) ?? fallback.flatMap(cached) else { return .standIn }
        return .site(image)
    }

    static func load(url: URL, fallback: URL?, with icons: MarkdownCitationIcons) async -> UIImage? {
        await icons.image(url: url, fallback: fallback)
    }
}

/// Draws a capsule behind every chip, then the text. A chip is several runs — its icon, its name — and one
/// capsule: the runs of one chip on one line are taken together. The capsule is as wide as its runs, which carry
/// the room inside it, and stands on the line where the metrics put it, whatever the runs' own heights.
struct MarkdownChipRenderer: TextRenderer {
    let metrics: MarkdownChipMetrics

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            var spans: [Int: ClosedRange<CGFloat>] = [:]
            var overhangs: [Int: CGFloat] = [:]
            for run in line {
                guard let chip = run[MarkdownChipAttribute.self] else { continue }
                overhangs[chip.id] = chip.overhang
                let bounds = run.typographicBounds.rect
                let span = spans[chip.id].map { min($0.lowerBound, bounds.minX)...max($0.upperBound, bounds.maxX) }
                spans[chip.id] = span ?? bounds.minX...bounds.maxX
            }
            let middle = line.typographicBounds.origin.y - metrics.centre
            for (id, span) in spans {
                let capsule = CGRect(
                    x: span.lowerBound, y: middle - metrics.capsuleHeight / 2,
                    width: span.upperBound - span.lowerBound + (overhangs[id] ?? 0), height: metrics.capsuleHeight)
                context.fill(Capsule().path(in: capsule), with: .color(MarkdownChipStyle.fill))
            }
            context.draw(line)
        }
    }
}

/// A block's inline content as drawn while it is still being written: its text, and its citation chips as
/// capsules with their sites' icons. A frame changes a `Text` and nothing else; once the block is settled,
/// `MarkdownSelectableText` stands where this stood, and a word of it can be selected.
struct MarkdownStyledText: View {
    let styled: MarkdownInlineStyler.Output
    let spec: MarkdownFontSpec

    @State private var icons: [URL: UIImage] = [:]
    @Environment(\.markdownCitationIcons) private var loader
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .caption2) private var scaledLabelSize = MarkdownChipMetrics.labelSize

    private var metrics: MarkdownChipMetrics {
        MarkdownChipMetrics(textSize: spec.pointSize, scaledLabelSize: scaledLabelSize)
    }

    var body: some View {
        let requests = styled.iconRequests
        let metrics = metrics
        text(metrics)
            .textRenderer(MarkdownChipRenderer(metrics: metrics))
            .task(id: requests) {
                for request in requests where icons[request.url] == nil {
                    guard
                        let image = await MarkdownChipIcon.load(
                            url: request.url, fallback: request.fallback, with: loader)
                    else { continue }
                    icons[request.url] = image
                }
            }
    }

    private func text(_ metrics: MarkdownChipMetrics) -> Text {
        var result = Text(verbatim: "")
        let textFont = UIFont.systemFont(ofSize: spec.pointSize)
        for (index, segment) in styled.segments.enumerated() {
            switch segment {
            case .text(let attributed):
                result = Text("\(result)\(Text(attributed))")
            case .chip(let chip):
                let overhang = MarkdownChipMetrics.overhang(before: character(after: index), in: textFont)
                result = Text("\(result)\(chipText(chip, id: index, metrics: metrics, overhang: overhang))")
            }
        }
        return result
    }

    /// What stands right after a segment, when it is text.
    private func character(after index: Int) -> Character? {
        guard styled.segments.indices.contains(index + 1), case .text(let next) = styled.segments[index + 1] else {
            return nil
        }
        return next.characters.first
    }

    /// The chip as text: room, icon, room, name, count, room — every piece held to the next, so the chip goes
    /// to the next line whole. The room is inside the chip's runs, so the capsule is exactly as wide as they are
    /// and a chip that opens a line sits on the text's edge.
    private func chipText(_ chip: MarkdownChip, id: Int, metrics: MarkdownChipMetrics, overhang: CGFloat) -> Text {
        let font = MarkdownChipMetrics.font(ofSize: metrics.labelSize)
        func label(_ string: String, weight: Font.Weight = MarkdownChipStyle.weight, kern: CGFloat = 0) -> AttributedString {
            var text = AttributedString(string)
            text.font = .system(size: metrics.labelSize, weight: weight)
            text.foregroundColor = MarkdownChipStyle.ink
            text.baselineOffset = metrics.labelLift
            text.link = chip.link
            if kern != 0 { text.kern = kern }
            return text
        }
        func room(_ width: CGFloat) -> AttributedString {
            label(
                MarkdownChipStyle.space,
                kern: MarkdownChipMetrics.kern(toMake: MarkdownChipStyle.space, wide: width, in: font))
        }
        let joiner = label(MarkdownChipStyle.joiner)

        var head = room(metrics.leading)
        head.append(joiner)
        var tail = joiner
        tail.append(room(metrics.gap))
        tail.append(joiner)
        tail.append(label(chip.label))
        if let count = chip.countText {
            tail.append(label("\u{00A0}" + count, weight: MarkdownChipStyle.countWeight))
        }
        // The mark after the chip starts that much sooner; the capsule is drawn as wide as ever.
        tail.append(room(metrics.trailing - overhang))

        let image = iconText(for: chip, side: metrics.iconSide).baselineOffset(metrics.iconLift)
        return Text("\(Text(head))\(image)\(Text(tail))")
            .customAttribute(MarkdownChipAttribute(id: id, overhang: overhang))
    }

    private func iconText(for chip: MarkdownChip, side: CGFloat) -> Text {
        let icon = MarkdownChipIcon.resolve(
            url: chip.iconURL, fallback: chip.iconFallbackURL, loaded: icons, cached: loader.cached)
        return Text(Image(uiImage: icon.image(side: side, scale: displayScale)))
    }
}

extension MarkdownChipIcon {
    /// The icon as a chip carries it: at the size it is drawn, clipped to a circle on a faint ground, with a
    /// hairline ring — text draws an image as it is.
    func image(side: CGFloat, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            draw(in: CGRect(x: 0, y: 0, width: side, height: side), scale: scale)
        }
    }

    /// Draws the icon's circle into `rect` of the current context.
    func draw(in rect: CGRect, scale: CGFloat) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let hairline = 1 / max(scale, 1)
        context.saveGState()
        defer { context.restoreGState() }
        UIBezierPath(ovalIn: rect).addClip()
        UIColor.tertiarySystemFill.setFill()
        UIBezierPath(ovalIn: rect).fill()
        switch self {
        case .site(let image): image.draw(in: rect)
        case .standIn: Self.drawStandIn(in: rect)
        }
        UIColor.separator.setStroke()
        let ring = UIBezierPath(ovalIn: rect.insetBy(dx: hairline / 2, dy: hairline / 2))
        ring.lineWidth = hairline
        ring.stroke()
    }

    /// The default glyph, in the same circle as a site's icon.
    private static func drawStandIn(in rect: CGRect) {
        let side = rect.width
        let symbol = UIImage(
            systemName: MarkdownChipStyle.standInSymbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: side * 0.8, weight: .medium))
        guard let symbol else { return }
        let fit = min(side / symbol.size.width, side / symbol.size.height, 1)
        let size = CGSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
        symbol.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
            .draw(
                in: CGRect(
                    x: rect.minX + (side - size.width) / 2, y: rect.minY + (side - size.height) / 2,
                    width: size.width, height: size.height))
    }
}

/// What "Ask about this" does with a selection; `Equatable` by identity so a view holding one is not redrawn for it.
public struct MarkdownAskAction: Sendable {
    public let perform: @MainActor @Sendable (String) -> Void
    public init(_ perform: @escaping @MainActor @Sendable (String) -> Void) { self.perform = perform }
}
