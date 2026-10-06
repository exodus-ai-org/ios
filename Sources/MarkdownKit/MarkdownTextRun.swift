import SwiftUI
import UIKit

extension NSAttributedString.Key {
    /// On a list item's marker and the tabs around it: Copy takes it as the marker and one space.
    static let markdownListMarker = NSAttributedString.Key("app.exodus.markdown.listMarker")
}

/// Settled text blocks side by side stand in one text view, so a selection runs from one into the next and Select
/// All takes them all: paragraphs, headings, lists and quotes made only of these. A code block, a table, an image, a
/// rule or a list with tasks stands by itself, and a selection stops at it.
enum MarkdownTextRuns {
    enum Segment: Equatable, Identifiable {
        /// Consecutive text blocks, drawn in one text view.
        case run([MarkdownBlock])
        /// A block drawn by itself: not text, or still being written.
        case block(MarkdownBlock)

        var id: MarkdownBlock.ID {
            switch self {
            case .run(let blocks): blocks[0].id
            case .block(let block): block.id
            }
        }

        /// The kind of its last block, what the gap after it is decided by.
        var lastKind: MarkdownBlock.Kind {
            switch self {
            case .run(let blocks): blocks[blocks.count - 1].kind
            case .block(let block): block.kind
            }
        }

        var firstKind: MarkdownBlock.Kind {
            switch self {
            case .run(let blocks): blocks[0].kind
            case .block(let block): block.kind
            }
        }
    }

    /// Whether a block is text all through, to be set in a run's text view.
    static func joins(_ kind: MarkdownBlock.Kind) -> Bool {
        switch kind {
        case .paragraph, .heading: true
        case .list(let list): list.items.allSatisfy { $0.checkbox == nil && $0.blocks.allSatisfy { joins($0.kind) } }
        case .blockquote(let blocks): !blocks.isEmpty && blocks.allSatisfy { joins($0.kind) }
        case .codeBlock, .table, .thematicBreak, .image, .html: false
        }
    }

    /// `arriving`: the block still being written, which `Text` draws by itself until it settles.
    static func segments(_ blocks: [MarkdownBlock], arriving: MarkdownBlock.ID?) -> [Segment] {
        var segments: [Segment] = []
        var run: [MarkdownBlock] = []
        func close() {
            if !run.isEmpty { segments.append(.run(run)) }
            run = []
        }
        for block in blocks {
            if block.id != arriving, joins(block.kind) {
                run.append(block)
            } else {
                close()
                segments.append(.block(block))
            }
        }
        close()
        return segments
    }
}

/// A quote's rule beside its text: the characters it stands beside, and how far in from the text's edge it stands.
struct MarkdownQuoteRule: Equatable {
    let range: NSRange
    let x: CGFloat
    static let width: CGFloat = 3
    /// What the rule stops short of the quote's first and last lines by.
    static let inset: CGFloat = 2
}

/// A run's text for its text view: its blocks one after another, each a paragraph (or more) of it, spaced and
/// indented as `MarkdownBlockStack` stands them.
struct MarkdownRunText {
    let text: NSAttributedString
    let quotes: [MarkdownQuoteRule]
}

/// Builds a run's text. Each block keeps the text `MarkdownSelectableText` gives it; between two, the gap the stack
/// would leave, as the room before the second's paragraph. A text view sets a line's spacing above it — the first
/// line of a paragraph too, by that paragraph's own spacing — so that much less is asked for.
@MainActor
struct MarkdownRunBuilder {
    /// The run's base style: what every block's own is made from, with its font and colour.
    let style: MarkdownTextStyle
    let citations: [Int: MarkdownCitation]
    let underlinesLinks: Bool
    /// The layout's `em`, as `MarkdownBlockStack` scales it.
    let em: CGFloat
    let icon: (MarkdownChip) -> MarkdownChipIcon

    private var result = NSMutableAttributedString()
    private var quotes: [MarkdownQuoteRule] = []

    init(
        style: MarkdownTextStyle, citations: [Int: MarkdownCitation], underlinesLinks: Bool, em: CGFloat,
        icon: @escaping (MarkdownChip) -> MarkdownChipIcon = { _ in .standIn }
    ) {
        self.style = style
        self.citations = citations
        self.underlinesLinks = underlinesLinks
        self.em = em
        self.icon = icon
    }

    /// The inline content a run's blocks hold, in order, for the icons of their chips and VoiceOver's actions.
    static func inlineContents(of blocks: [MarkdownBlock]) -> [(AttributedString, MarkdownFontSpec)] {
        blocks.flatMap { block -> [(AttributedString, MarkdownFontSpec)] in
            switch block.kind {
            case .paragraph(let content): [(content, .body)]
            case .heading(let level, let content): [(content, MarkdownLayoutRules.headingFont(level: level))]
            case .list(let list): list.items.flatMap { inlineContents(of: $0.blocks) }
            case .blockquote(let blocks): inlineContents(of: blocks)
            default: []
            }
        }
    }

    mutating func build(_ blocks: [MarkdownBlock]) -> MarkdownRunText {
        result = NSMutableAttributedString()
        quotes = []
        stack(blocks, inList: false, depth: 0, indent: 0, gap: 0, marker: nil)
        return MarkdownRunText(text: result, quotes: quotes)
    }

    /// A list item's marker, set on its first line before its text.
    private struct Marker {
        let text: String
        let font: UIFont
        /// Where the marker's column starts: where its list stands.
        let lead: CGFloat
        /// Where the marker ends, from the text's edge: the widest of its list's markers ends there too.
        let end: CGFloat
        /// Where the item's text starts.
        let start: CGFloat
    }

    /// `gap`: the room before the first of `blocks`, in em, as the stack around them leaves it.
    private mutating func stack(
        _ blocks: [MarkdownBlock], inList: Bool, depth: Int, indent: CGFloat, gap: CGFloat, marker: Marker?
    ) {
        var marker = marker
        for (index, block) in blocks.enumerated() {
            let gap = index == 0 ? gap : MarkdownLayoutRules.gap(after: blocks[index - 1].kind, before: block.kind, inList: inList)
            self.block(block, inList: inList, depth: depth, indent: indent, gap: gap, marker: marker)
            marker = nil
        }
    }

    private mutating func block(
        _ block: MarkdownBlock, inList: Bool, depth: Int, indent: CGFloat, gap: CGFloat, marker: Marker?
    ) {
        switch block.kind {
        case .paragraph(let content):
            paragraph(content, spec: .body, isSecondary: false, heading: nil, indent: indent, gap: gap, marker: marker)
        case .heading(let level, let content):
            paragraph(
                content, spec: MarkdownLayoutRules.headingFont(level: level), isSecondary: level >= 6, heading: level,
                indent: indent, gap: gap, marker: marker)
        case .list(let list):
            self.list(list, depth: depth, indent: indent, gap: gap, marker: marker)
        case .blockquote(let blocks):
            // Past the line break before it, which stands at the end of the line above.
            let start = result.length + (result.length > 0 ? 1 : 0)
            let inner = indent + MarkdownQuoteRule.width + em * 0.75
            stack(blocks, inList: inList, depth: depth, indent: inner, gap: gap, marker: marker)
            quotes.append(MarkdownQuoteRule(range: NSRange(location: start, length: result.length - start), x: indent))
        case .codeBlock, .table, .thematicBreak, .image, .html:
            assertionFailure("only text joins a run")
        }
    }

    private mutating func list(_ list: MarkdownList, depth: Int, indent: CGFloat, gap: CGFloat, marker: Marker?) {
        let fonts = style.fonts
        let font = list.isOrdered
            ? MarkdownFontSpec.body.font.monospacedDigit().resolve(in: fonts).ctFont as UIFont
            : MarkdownFontSpec.body.font.weight(.semibold).resolve(in: fonts).ctFont as UIFont
        let widest = MarkdownLayoutRules.widestMarker(list, depth: depth)
        let end = indent + (widest as NSString).size(withAttributes: [.font: font]).width
        var outer = marker
        for (index, item) in list.items.enumerated() {
            let own = Marker(
                text: MarkdownLayoutRules.listMarker(isOrdered: list.isOrdered, number: list.startIndex + index, depth: depth),
                font: font, lead: indent, end: end, start: end + em * 0.4)
            // A list that opens an item stands on the item's first line: the outer marker comes first.
            if let first = outer {
                // Past the line break before it, which stands at the end of the line above.
                let start = result.length + (result.length > 0 ? 1 : 0)
                stack(item.blocks, inList: true, depth: depth + 1, indent: own.start, gap: gap, marker: own)
                prefix(first, at: start)
                outer = nil
            } else {
                stack(
                    item.blocks, inList: true, depth: depth + 1, indent: own.start,
                    gap: index == 0 ? gap : MarkdownLayoutRules.listGap, marker: own)
            }
        }
    }

    /// Puts an outer list's marker before the text an inner list's item opened at `location` with: two markers on
    /// one line, as the stack sets a list that opens an item.
    private mutating func prefix(_ marker: Marker, at location: Int) {
        guard location < result.length,
            let paragraph = result.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
            let style = paragraph.mutableCopy() as? NSMutableParagraphStyle
        else { return }
        style.firstLineHeadIndent = marker.lead
        style.tabStops = [NSTextTab(textAlignment: .right, location: marker.end), NSTextTab(textAlignment: .left, location: marker.start)]
            + style.tabStops
        let piece = markerText(marker, paragraph: style)
        let paragraphRange = (result.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        result.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
        result.insert(piece, at: location)
        quotes = quotes.map { rule in
            rule.range.location >= location
                ? MarkdownQuoteRule(range: NSRange(location: rule.range.location + piece.length, length: rule.range.length), x: rule.x)
                : rule
        }
    }

    private func markerText(_ marker: Marker, paragraph: NSParagraphStyle) -> NSAttributedString {
        NSAttributedString(
            string: "\t\(marker.text)\t",
            attributes: [
                .font: marker.font, .foregroundColor: UIColor.secondaryLabel, .paragraphStyle: paragraph,
                .markdownListMarker: marker.text,
            ])
    }

    private mutating func paragraph(
        _ content: AttributedString, spec: MarkdownFontSpec, isSecondary: Bool, heading: Int?, indent: CGFloat,
        gap: CGFloat, marker: Marker?
    ) {
        var own = style
        own.spec = spec
        own.color = isSecondary ? .secondaryLabel : style.color
        let styled = MarkdownInlineStyler.style(content, spec: spec, citations: citations, underlinesLinks: underlinesLinks)
        let built = NSMutableAttributedString(attributedString: MarkdownAttributedText.build(styled, style: own, icon: icon))
        guard built.length > 0 || marker != nil else { return }

        let base = own.paragraph
        guard let paragraph = base.mutableCopy() as? NSMutableParagraphStyle else { return }
        paragraph.headIndent = indent
        paragraph.firstLineHeadIndent = indent
        if result.length > 0 { paragraph.paragraphSpacingBefore = max(em * gap - paragraph.lineSpacing, 0) }
        if let marker {
            // The marker's own column, ending where the list's widest marker ends; the text after it.
            paragraph.firstLineHeadIndent = marker.lead
            paragraph.tabStops = [
                NSTextTab(textAlignment: .right, location: marker.end), NSTextTab(textAlignment: .left, location: marker.start),
            ]
            built.insert(markerText(marker, paragraph: paragraph), at: 0)
        }
        built.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: built.length))
        if let heading { built.addAttribute(.accessibilityTextHeadingLevel, value: heading, range: NSRange(location: 0, length: built.length)) }

        if result.length > 0 {
            // The break belongs to the paragraph before: it is set in that paragraph's last font and style.
            let last = result.attributes(at: result.length - 1, effectiveRange: nil)
                .filter { [.font, .paragraphStyle, .foregroundColor].contains($0.key) }
            result.append(NSAttributedString(string: "\n", attributes: last))
        }
        result.append(built)
    }
}

/// Keeps the text made for a run until what it is made from changes: a text made again is another text to a text
/// view, and a selection in it would be lost.
@MainActor
final class MarkdownRunMemo {
    struct Key: Equatable {
        let blocks: [MarkdownBlock]
        let citations: [Int: MarkdownCitation]
        let style: MarkdownTextStyle
        let underlinesLinks: Bool
        let em: CGFloat
        let icons: [URL: ObjectIdentifier]
    }

    private var key: Key?
    private var run = MarkdownRunText(text: NSAttributedString(), quotes: [])

    func run(for key: Key, make: () -> MarkdownRunText) -> MarkdownRunText {
        if key != self.key {
            self.key = key
            run = make()
        }
        return run
    }
}

/// A run of settled text blocks in one text view (`MarkdownTextRuns`): a selection can be drawn from one block into
/// the next, and Select All takes them all.
struct MarkdownRunView: View, Equatable {
    let blocks: [MarkdownBlock]
    let citations: [Int: MarkdownCitation]

    @State private var icons: [URL: UIImage] = [:]
    @State private var memo = MarkdownRunMemo()
    @State private var baselines = MarkdownTextBaselines()
    @Environment(\.markdownCitationIcons) private var loader
    @Environment(\.markdownUnderlinesLinks) private var underlinesLinks
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.multilineTextAlignment) private var alignment
    @Environment(\.layoutDirection) private var direction
    @Environment(\.fontResolutionContext) private var fonts
    @Environment(\.markdownLineSpacingScale) private var lineSpacingScale
    @ScaledMetric(relativeTo: .caption2) private var scaledLabelSize = MarkdownChipMetrics.labelSize
    @ScaledMetric(relativeTo: .body) private var em: CGFloat = MarkdownFontSpec.bodySize

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.blocks == rhs.blocks && lhs.citations == rhs.citations
    }

    private var styled: [MarkdownInlineStyler.Output] {
        MarkdownRunBuilder.inlineContents(of: blocks).map { content, spec in
            MarkdownInlineStyler.style(content, spec: spec, citations: citations, underlinesLinks: underlinesLinks)
        }
    }

    var body: some View {
        // The read is the point: the fonts below are the system's at this text size.
        _ = dynamicTypeSize
        let styled = styled
        var seen: Set<URL> = []
        let requests = styled.flatMap(\.iconRequests).filter { seen.insert($0.url).inserted }
        var seenChips: Set<Int> = []
        let chips = styled.flatMap(\.chips).filter { seenChips.insert($0).inserted }
        let run = run(requests: requests)
        let baselines = baselines
        return SelectableText(text: run.text, baselines: baselines, quotes: run.quotes, fillsWidth: true, snapsBlocks: true)
            .alignmentGuide(.firstTextBaseline) { dimensions in baselines.first ?? dimensions[.bottom] }
            .alignmentGuide(.lastTextBaseline) { dimensions in baselines.last ?? dimensions[.bottom] }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityActions {
                ForEach(chips, id: \.self) { number in
                    if let citation = citations[number] {
                        let label = citation.chipLabel
                        Button {
                            openURL(MarkdownCitation.citeURL(number))
                        } label: {
                            Text(
                                String(
                                    localized: "ios:chat.markdown.openSource", defaultValue: "Open citation: \(label)",
                                    comment: "VoiceOver action on a citation chip in an answer. %@ is the site or title."))
                        }
                    }
                }
            }
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

    private func run(requests: [MarkdownIconRequest]) -> MarkdownRunText {
        var style = MarkdownTextStyle(
            spec: .body, color: .label, alignment: MarkdownTextStyle.alignment(alignment, in: direction),
            scaledLabelSize: scaledLabelSize, displayScale: displayScale,
            interfaceStyle: colorScheme == .dark ? .dark : .light, fonts: fonts)
        style.lineSpacingScale = lineSpacingScale
        var shown: [URL: UIImage] = [:]
        for request in requests {
            if case .site(let image) = MarkdownChipIcon.resolve(
                url: request.url, fallback: request.fallback, loaded: icons, cached: loader.cached)
            {
                shown[request.url] = image
            }
        }
        let key = MarkdownRunMemo.Key(
            blocks: blocks, citations: citations, style: style, underlinesLinks: underlinesLinks, em: em,
            icons: shown.mapValues { ObjectIdentifier($0) })
        return memo.run(for: key) {
            var builder = MarkdownRunBuilder(
                style: style, citations: citations, underlinesLinks: underlinesLinks, em: em
            ) { chip in
                chip.iconURL.flatMap { shown[$0] }.map { .site($0) } ?? .standIn
            }
            return builder.build(blocks)
        }
    }
}

/// Where a run's blocks stand at one width. One under another, each block was as tall as its text up to a whole
/// pixel, stood on the pixel nearest its place, and had its first baseline on the pixel nearest it; in a run's text
/// view nothing rounds them. Each block's first baseline is moved to that pixel, so a block that settles into a run
/// stands where it stood by itself.
@MainActor
enum MarkdownRunSnap {
    static func snapped(_ text: NSAttributedString, width: CGFloat, scale: CGFloat) -> NSAttributedString {
        // Every paragraph break in a run is between two blocks: a break inside one is a line separator.
        let string = text.string as NSString
        var paragraphs: [NSRange] = []
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]
        ) { _, range, _, _ in
            paragraphs.append(range)
        }
        guard paragraphs.count > 1 else { return text }
        let lines = MarkdownTextMeasure.lines(of: text, width: width)
        let blocks = paragraphs.compactMap { paragraph -> Block? in
            let own = lines.filter { NSIntersectionRange($0.range, paragraph).length > 0 || $0.range.location == paragraph.location }
            guard let first = own.first, let bottom = own.map(\.bottom).max() else { return nil }
            return Block(range: paragraph, top: first.top, bottom: bottom, baseline: first.baseline)
        }
        guard let first = blocks.first else { return text }
        func up(_ value: CGFloat) -> CGFloat { MarkdownTextMeasure.pixels(value, scale: scale, .up) }
        func nearest(_ value: CGFloat) -> CGFloat { MarkdownTextMeasure.pixels(value, scale: scale, .toNearestOrAwayFromZero) }

        let snapped = NSMutableAttributedString(attributedString: text)
        // What the text view's first baseline is raised by (`MarkdownTextMeasurement.lift`): every other baseline
        // is set that much lower, to stand where it should once raised.
        let lift = up(first.baseline - first.top) - nearest(first.baseline - first.top)
        var stack = first.top
        var moved: CGFloat = 0
        for (previous, block) in zip(blocks, blocks.dropFirst()) {
            stack = nearest(stack) + up(previous.bottom - previous.top) + (block.top - previous.bottom)
            let wanted = nearest(stack) + nearest(block.baseline - block.top) + lift
            let move = wanted - (block.baseline + moved)
            moved += move
            guard move != 0,
                let style = snapped.attribute(.paragraphStyle, at: block.range.location, effectiveRange: nil) as? NSParagraphStyle,
                let own = style.mutableCopy() as? NSMutableParagraphStyle
            else { continue }
            own.paragraphSpacingBefore = max(own.paragraphSpacingBefore + move, 0)
            snapped.addAttribute(.paragraphStyle, value: own, range: block.range)
        }
        return snapped
    }

    private struct Block {
        let range: NSRange
        let top: CGFloat
        let bottom: CGFloat
        let baseline: CGFloat
    }
}
