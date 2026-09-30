import CoreText
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import MarkdownKit

/// What a settled block hands its text view: the same text, fonts and chips the SwiftUI renderer draws, as an
/// attributed string a word can be selected in.
@Suite("MarkdownAttributedText: a block's text for a text view")
@MainActor
struct MarkdownAttributedTextTests {
    private let citations: [Int: MarkdownCitation] = [
        1: MarkdownCitation(number: 1, title: "Swift", host: "www.swift.org"),
        2: MarkdownCitation(number: 2, title: "Docs", host: "Apple Developer"),
        3: MarkdownCitation(number: 3, title: "Markets", host: "Yahoo! Finance"),
    ]

    private func styled(
        _ text: String, spec: MarkdownFontSpec = .body, underlinesLinks: Bool = false
    ) -> MarkdownInlineStyler.Output {
        guard let kind = MarkdownParser.parse(text).first?.kind else { return .init(segments: [], chips: []) }
        switch kind {
        case .paragraph(let content), .heading(_, let content):
            return MarkdownInlineStyler.style(
                content, spec: spec, citations: citations, underlinesLinks: underlinesLinks)
        default:
            Issue.record("expected inline content for \(text.debugDescription)")
            return .init(segments: [], chips: [])
        }
    }

    private func built(
        _ text: String, style: MarkdownTextStyle = MarkdownTextStyle(spec: .body), underlinesLinks: Bool = false
    ) -> NSAttributedString {
        MarkdownAttributedText.build(styled(text, spec: style.spec, underlinesLinks: underlinesLinks), style: style)
    }

    private func attributes(of needle: String, in text: NSAttributedString) -> [NSAttributedString.Key: Any] {
        let range = (text.string as NSString).range(of: needle)
        guard range.location != NSNotFound else {
            Issue.record("\(needle.debugDescription) is not in \(text.string.debugDescription)")
            return [:]
        }
        return text.attributes(at: range.location, effectiveRange: nil)
    }

    private func font(of needle: String, in text: NSAttributedString) -> UIFont? {
        attributes(of: needle, in: text)[.font] as? UIFont
    }

    private func chips(in text: NSAttributedString) -> [(attachment: MarkdownChipAttachment, range: NSRange)] {
        var found: [(MarkdownChipAttachment, NSRange)] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let chip = value as? MarkdownChipAttachment { found.append((chip, range)) }
        }
        return found
    }

    @Test("a run's font is the SwiftUI renderer's, as a UIFont: size, weight, slant, and the code face")
    func fonts() {
        let text = built("a **b** *c* ***d*** `e` **`f`**")
        let size = MarkdownFontSpec.body.pointSize
        let code = MarkdownFontSpec.pointSize(.callout, in: .current)

        #expect(font(of: "a", in: text)?.pointSize == size)
        #expect(font(of: "a", in: text)?.familyName == UIFont.systemFont(ofSize: size).familyName)
        #expect(font(of: "a", in: text)?.fontDescriptor.symbolicTraits.isDisjoint(with: [.traitBold, .traitItalic, .traitMonoSpace]) == true)
        #expect(font(of: "b", in: text)?.pointSize == size)
        #expect(font(of: "b", in: text)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(font(of: "c", in: text)?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        #expect(font(of: "c", in: text)?.fontDescriptor.symbolicTraits.contains(.traitBold) == false)
        #expect(font(of: "d", in: text)?.fontDescriptor.symbolicTraits.isSuperset(of: [.traitBold, .traitItalic]) == true)
        #expect(font(of: "e", in: text)?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)
        #expect(abs((font(of: "e", in: text)?.pointSize ?? 0) - code) < 0.001)
        #expect(font(of: "f", in: text)?.fontDescriptor.symbolicTraits.isSuperset(of: [.traitBold, .traitMonoSpace]) == true)
    }

    @Test("a heading's text is its style's size, semibold")
    func headingFont() {
        let spec = MarkdownLayoutRules.headingFont(level: 1)
        let text = built("# Title", style: MarkdownTextStyle(spec: spec))
        #expect(font(of: "Title", in: text)?.pointSize == spec.pointSize)
        #expect(weight(of: font(of: "Title", in: text)) == weight(of: .systemFont(ofSize: spec.pointSize, weight: .semibold)))
        let third = MarkdownLayoutRules.headingFont(level: 3)
        let headline = built("### Title", style: MarkdownTextStyle(spec: third))
        #expect(font(of: "Title", in: headline)?.pointSize == third.pointSize)
        #expect(weight(of: font(of: "Title", in: headline)) == weight(of: .systemFont(ofSize: 12, weight: .semibold)))
    }

    @Test("the fonts are the ones `Text` draws with: a run is as wide in a text view as it was while it streamed")
    func sameFontsAsText() {
        let fonts = EnvironmentValues().fontResolutionContext
        for intent: InlinePresentationIntent in [[], .stronglyEmphasized, .emphasized, .code, [.stronglyEmphasized, .emphasized]] {
            let drawn = MarkdownInlineStyler.font(for: intent, spec: .body).resolve(in: fonts).ctFont
            let set = MarkdownInlineStyler.uiFont(for: intent, spec: .body, in: fonts)
            #expect(CFEqual(drawn, set as CTFont))
        }
    }

    private func weight(of font: UIFont?) -> CGFloat? {
        let traits = font?.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        return (traits?[.weight] as? CGFloat).map { ($0 * 100).rounded() / 100 }
    }

    @Test("text is the style's colour; inline code has its ground, struck text its line")
    func colours() {
        let text = built("plain `code` ~~old~~", style: MarkdownTextStyle(spec: .body, color: .secondaryLabel))
        #expect(attributes(of: "plain", in: text)[.foregroundColor] as? UIColor == .secondaryLabel)
        #expect(attributes(of: "plain", in: text)[.backgroundColor] == nil)
        #expect(attributes(of: "code", in: text)[.backgroundColor] as? UIColor == .tertiarySystemFill)
        #expect(attributes(of: "old", in: text)[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attributes(of: "plain", in: text)[.strikethroughStyle] == nil)
    }

    @Test("the paragraph has the block's line spacing and alignment, and breaks lines as running text does")
    func paragraph() {
        let spec = MarkdownFontSpec.body
        let text = built("one", style: MarkdownTextStyle(spec: spec, alignment: .center))
        let paragraph = attributes(of: "one", in: text)[.paragraphStyle] as? NSParagraphStyle
        #expect(abs((paragraph?.lineSpacing ?? 0) - spec.pointSize * MarkdownLayoutRules.lineGap(for: spec)) < 0.001)
        #expect(paragraph?.alignment == .center)
        #expect(paragraph?.lineBreakMode == .byWordWrapping)

        let bubble = built("one", style: MarkdownTextStyle(spec: spec, lineSpacing: 4))
        #expect((attributes(of: "one", in: bubble)[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing == 4)
    }

    @Test("a link keeps its address, and is underlined only where the host asks for it")
    func links() {
        let plain = built("see [the site](https://www.swift.org) now")
        #expect(attributes(of: "the site", in: plain)[.link] as? URL == URL(string: "https://www.swift.org"))
        #expect(attributes(of: "the site", in: plain)[.underlineStyle] == nil)
        #expect(attributes(of: "see", in: plain)[.link] == nil)

        let underlined = built("see [the site](https://www.swift.org) now", underlinesLinks: true)
        #expect(attributes(of: "the site", in: underlined)[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attributes(of: "see", in: underlined)[.underlineStyle] == nil)
    }

    @Test("a link model-written text may not open is text, not a link")
    func forbiddenLinks() {
        let text = built("call [me](tel:123) or [run](shortcuts://x)")
        #expect(attributes(of: "me", in: text)[.link] == nil)
        #expect(attributes(of: "run", in: text)[.link] == nil)
    }

    @Test("every chip is one attachment, tapped through its citation's link")
    func oneAttachmentPerChip() {
        let text = built("First \u{3010}1-source\u{3011} and both \u{3010}2,3-source\u{3011}. End \u{3010}9-source\u{3011}")
        let found = chips(in: text)
        #expect(found.count == 2)
        #expect(found.map(\.attachment.chip.numbers) == [[1], [2, 3]])
        #expect(found.allSatisfy { $0.range.length == 1 })
        for chip in found {
            let attributes = text.attributes(at: chip.range.location, effectiveRange: nil)
            #expect(attributes[.link] as? URL == MarkdownCitation.citeURL(chip.attachment.chip.numbers[0]))
            #expect(chip.attachment.image != nil)
            #expect(chip.attachment.accessibilityLabel == chip.attachment.chip.title)
        }
        #expect(!text.string.contains("source"))
    }

    @Test("a chip stands on the line where the metrics put it: its middle, its height, its width")
    func chipBounds() throws {
        let style = MarkdownTextStyle(spec: .body)
        let text = built("First \u{3010}1-source\u{3011} end", style: style)
        let chip = try #require(chips(in: text).first?.attachment)
        let metrics = style.metrics
        #expect(abs(chip.capsule.midY - metrics.centre) < 0.001)
        #expect(abs(chip.capsule.height - metrics.capsuleHeight) < 0.001)

        let label = MarkdownChipMetrics.font(ofSize: metrics.labelSize)
        let name = (chip.chip.label as NSString).size(withAttributes: [.font: label]).width
        let width = metrics.leading + metrics.iconSide + metrics.gap + name + metrics.trailing
        #expect(abs(chip.bounds.width - width) < 0.01)
        #expect(chip.capsule.width == chip.bounds.width)
        #expect(chip.bounds.minX == 0)
        // The box is the chip's room on its line: the capsule is inside it, and the picture is the box.
        #expect(chip.bounds.minY <= chip.capsule.minY)
        #expect(chip.bounds.maxY >= chip.capsule.maxY)
        #expect(abs((chip.image?.size.height ?? 0) - chip.bounds.height) < 0.34)
    }

    @Test(
        "text with chips is as tall in a text view as `Text` draws it, line for line",
        arguments: [
            ("Storms crossed East Texas late on Sunday \u{3010}1-source\u{3011} and the power was out by morning.", 0),
            ("本周美股经历了一波债券收益率驱动的抛售，10 年期美债收益率一度触及 2007 年以来最高水平\u{3010}1-source\u{3011}。但周五三大指数收高，道指涨 0.93%，标普 500 涨 0.51%\u{3010}1,2-source\u{3011}。芯片股在周五普涨提振了市场情绪\u{3010}3-source\u{3011}。", 0),
            ("Plain, **bold**, *italic*, `inline code` and a second line that has no chip at all in it, only words.", 0),
            ("A cell \u{3010}2-source\u{3011} of a table", 1),
            ("A heading \u{3010}2-source\u{3011} that cites", 2),
        ]
    )
    func asTallAsText(sample: String, kind: Int) throws {
        let spec = [MarkdownFontSpec.body, MarkdownFontSpec(style: .subheadline), MarkdownLayoutRules.headingFont(level: 1)][kind]
        let output = styled(sample, spec: spec)
        let renderer = ImageRenderer(
            content: MarkdownStyledText(styled: output, spec: spec)
                .lineSpacing(spec.pointSize * MarkdownLayoutRules.lineGap(for: spec))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 370, alignment: .leading))
        renderer.scale = 3
        let drawn = try #require(renderer.uiImage)

        let view = MarkdownTextView(usingTextLayoutManager: true)
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = MarkdownAttributedText.build(output, style: MarkdownTextStyle(spec: spec))
        let set = view.sizeThatFits(CGSize(width: 370, height: CGFloat.greatestFiniteMagnitude))
        #expect(abs(set.height - drawn.size.height) < 0.01)
    }

    @Test("a chip of several is wider by its count")
    func chipWithCount() throws {
        let one = try #require(chips(in: built("a \u{3010}2-source\u{3011} b")).first?.attachment)
        let three = try #require(chips(in: built("a \u{3010}2,1,3-source\u{3011} b")).first?.attachment)
        #expect(three.chip.countText == "+2")
        #expect(three.bounds.width > one.bounds.width)
    }

    @Test("a mark of punctuation after a chip stands where the renderer puts it: the chip ends that much sooner")
    func overhang() throws {
        let style = MarkdownTextStyle(spec: .body)
        let stop = built("水平\u{3010}1-source\u{3011}。但", style: style)
        let word = built("level \u{3010}1-source\u{3011} but", style: style)
        let closed = try #require(chips(in: stop).first)
        let open = try #require(chips(in: word).first)
        let font = UIFont.systemFont(ofSize: style.spec.pointSize)
        let expected = MarkdownChipMetrics.overhang(before: "。", in: font)
        #expect(expected > 0)
        #expect(abs(open.attachment.bounds.width - closed.attachment.bounds.width - expected) < 0.001)
        #expect(abs((closed.attachment.image?.size.width ?? 0) - closed.attachment.bounds.width) < 0.5)

    }

    @Test(
        "a line is as wide in a text view as `Text` draws it: chips, the room beside them, the marks after them",
        arguments: [
            "level \u{3010}1-source\u{3011} but", "水平\u{3010}1-source\u{3011}。但周五", "水平\u{3010}1-source\u{3011}，但周五",
            "Sunday \u{3010}1-source\u{3011}. And then", "both \u{3010}2,3-source\u{3011}; end", "\u{3010}1-source\u{3011} opens the line",
            "quoted \u{3010}1-source\u{3011}(aside)", "Plain, **bold**, *italic*, `code`, ~~struck~~.",
        ]
    )
    func asWideAsText(sample: String) throws {
        let output = styled(sample)
        let renderer = ImageRenderer(
            content: MarkdownStyledText(styled: output, spec: .body).fixedSize())
        renderer.scale = 3
        let drawn = try #require(renderer.uiImage)

        let view = MarkdownTextView(usingTextLayoutManager: true)
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = MarkdownAttributedText.build(output, style: MarkdownTextStyle(spec: .body))
        let set = view.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        #expect(abs(set.width - drawn.size.width) < 0.01)
        #expect(abs(set.height - drawn.size.height) < 0.01)
    }

    @Test("a chip is drawn again when its icon arrives, and not for the same icon")
    func chipImages() throws {
        let style = MarkdownTextStyle(spec: .body)
        let output = styled("a \u{3010}1-source\u{3011} b")
        let icon = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let standIn = try #require(chips(in: MarkdownAttributedText.build(output, style: style)).first?.attachment.image)
        let again = try #require(chips(in: MarkdownAttributedText.build(output, style: style)).first?.attachment.image)
        let site = try #require(
            chips(in: MarkdownAttributedText.build(output, style: style) { _ in .site(icon) }).first?.attachment.image)
        #expect(standIn === again)
        #expect(standIn !== site)
        #expect(standIn.size == site.size)

        var dark = style
        dark.interfaceStyle = .dark
        let night = try #require(chips(in: MarkdownAttributedText.build(output, style: dark)).first?.attachment.image)
        #expect(night !== standIn)
    }

    @Test(
        "a text is measured as a text view sets it, and told to the layout as `Text` tells it",
        arguments: [
            "One line.", "Storms crossed East Texas late on Sunday \u{3010}1-source\u{3011} and the power was out by morning.",
            "早上好。要给你一份贴合持仓的简报，我先拉几组最新数据：美股大盘走势、日元汇率与美联储利率路径，以及半导体供应链的最新动态。",
            "A hard break follows\\\nthis line, which is long enough to wrap onto one more line of the phone again.",
        ]
    )
    func measured(sample: String) throws {
        let text = built(sample)
        let view = MarkdownTextView(usingTextLayoutManager: true)
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = text
        for width: CGFloat in [370, 200, CGFloat.greatestFiniteMagnitude] {
            let set = view.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            let measured = try #require(MarkdownTextMeasure.measure(text, width: width)).reported(scale: 3, within: width)
            #expect(abs(measured.size.height - set.height) < 0.01)
            #expect(abs(measured.size.width - set.width) < 0.01)
            #expect(measured.firstBaseline > 0 && measured.firstBaseline <= measured.lastBaseline)
            #expect(measured.lastBaseline < measured.size.height)
        }
    }

    @Test("text set to the right or the middle is as wide as its widest line, not as the room it was given")
    func alignedWidth() throws {
        let natural = try #require(MarkdownTextMeasure.measure(built("13.75"), width: 260))
        for alignment: NSTextAlignment in [.right, .center] {
            let text = built("13.75", style: MarkdownTextStyle(spec: .body, alignment: alignment))
            for width: CGFloat in [260, CGFloat.greatestFiniteMagnitude] {
                let measured = try #require(MarkdownTextMeasure.measure(text, width: width))
                #expect(abs(measured.size.width - natural.size.width) < 0.01)
                #expect(abs(measured.size.height - natural.size.height) < 0.01)
            }
        }
    }

    @Test("a written line break is a line of the same paragraph: as tall as `Text` sets it")
    func hardBreak() throws {
        let output = styled("A hard break follows\\\nthis line.")
        let text = MarkdownAttributedText.build(output, style: MarkdownTextStyle(spec: .body))
        #expect(text.string == "A hard break follows\u{2028}this line.")
        #expect(MarkdownAttributedText.copied(from: text, in: NSRange(location: 0, length: text.length)) == "A hard break follows\nthis line.")
        let renderer = ImageRenderer(
            content: MarkdownStyledText(styled: output, spec: .body)
                .lineSpacing(MarkdownFontSpec.body.pointSize * MarkdownLayoutRules.lineGap(for: .body))
                .fixedSize())
        renderer.scale = 3
        let drawn = try #require(renderer.uiImage)
        let measured = try #require(MarkdownTextMeasure.measure(text, width: 370)).reported(scale: 3, within: 370)
        #expect(abs(measured.size.height - drawn.size.height) < 0.01)
        #expect(abs(measured.size.width - drawn.size.width) < 0.01)
    }

    @Test("the baselines are told to the nearest pixel, the size up to the next: what `Text` does")
    func rounding() {
        let measured = MarkdownTextMeasurement(
            size: CGSize(width: 63.73, height: 44.91), firstBaseline: 19.72, lastBaseline: 41.05)
        let told = measured.reported(scale: 3, within: 370)
        #expect(abs(told.size.width - 64) < 0.001)
        #expect(abs(told.size.height - 45) < 0.001)
        #expect(abs(told.firstBaseline - 59.0 / 3) < 0.001)
        #expect(abs(told.lastBaseline - 41) < 0.001)
        #expect(abs(measured.lift(scale: 3) - 1.0 / 3) < 0.001)
        #expect(MarkdownTextMeasurement(size: .zero, firstBaseline: 15.234, lastBaseline: 15.234).lift(scale: 3) == 0)
        #expect(measured.reported(scale: 3, within: 50).size.width == 50)
    }

    @Test("plain text, for what the user wrote: as typed, in the style's font, with nothing read as markup")
    func plainText() {
        let style = MarkdownTextStyle(spec: .body, lineSpacing: 4)
        let text = MarkdownAttributedText.plain("**not bold** \u{3010}1-source\u{3011}\nsecond line", style: style)
        // A line's end, not a paragraph's: a text view sets one paragraph as `Text` sets the whole.
        #expect(text.string == "**not bold** \u{3010}1-source\u{3011}\u{2028}second line")
        #expect(
            MarkdownAttributedText.copied(from: text, in: NSRange(location: 0, length: text.length))
                == "**not bold** \u{3010}1-source\u{3011}\nsecond line")
        #expect(font(of: "not bold", in: text)?.pointSize == style.spec.pointSize)
        #expect(font(of: "not bold", in: text)?.fontDescriptor.symbolicTraits.contains(.traitBold) == false)
        #expect(chips(in: text).isEmpty)
    }
}

@Suite("MarkdownAttributedText: what Copy takes of a selection")
@MainActor
struct MarkdownCopiedSelectionTests {
    private let citations: [Int: MarkdownCitation] = [
        1: MarkdownCitation(number: 1, title: "Swift", host: "www.swift.org"),
        2: MarkdownCitation(number: 2, title: "Docs", host: "Apple Developer"),
    ]

    private func built(_ text: String) -> NSAttributedString {
        guard case .paragraph(let content) = MarkdownParser.parse(text).first?.kind else {
            Issue.record("expected a paragraph for \(text.debugDescription)")
            return NSAttributedString()
        }
        let styled = MarkdownInlineStyler.style(content, spec: .body, citations: citations)
        return MarkdownAttributedText.build(styled, style: MarkdownTextStyle(spec: .body))
    }

    private func copied(_ text: NSAttributedString, from start: String? = nil, through end: String? = nil) -> String {
        let string = text.string as NSString
        let lower = start.map { string.range(of: $0).location } ?? 0
        let upper = end.map { NSMaxRange(string.range(of: $0)) } ?? string.length
        return MarkdownAttributedText.copied(from: text, in: NSRange(location: lower, length: upper - lower))
    }

    @Test("a range with a chip in it is copied without the chip: no object character, the words one space apart")
    func chipBetweenWords() {
        let text = built("checking by default \u{3010}1-source\u{3011} and the documentation")
        #expect(copied(text) == "checking by default and the documentation")
        #expect(copied(text, from: "default", through: "and") == "default and")
        #expect(!copied(text).contains("\u{FFFC}"))
        #expect(!copied(text).contains("\u{2009}"))
    }

    @Test("the mark that closes a sentence follows its last word, as it was written")
    func chipBeforePunctuation() {
        let text = built("checking by default \u{3010}1-source\u{3011}. The documentation\u{3010}2-source\u{3011}, too.")
        #expect(copied(text) == "checking by default. The documentation, too.")
    }

    @Test("Han text has no spaces, and gets none where a chip stood")
    func chipInHanText() {
        let text = built("最高水平\u{3010}1-source\u{3011}\u{3010}2-source\u{3011}。但周五\u{3010}1-source\u{3011}收高")
        #expect(copied(text) == "最高水平。但周五收高")
    }

    @Test("a selection that starts or ends at a chip has no space where nothing stands beside it")
    func chipAtAnEdge() {
        let text = built("one \u{3010}1-source\u{3011} two \u{3010}2-source\u{3011}")
        let string = text.string as NSString
        let first = string.range(of: "\u{FFFC}")
        #expect(copied(text) == "one two")
        #expect(
            MarkdownAttributedText.copied(from: text, in: NSRange(location: first.location, length: string.length - first.location))
                == "two")
        #expect(MarkdownAttributedText.copied(from: text, in: first) == "")
    }

    @Test("text without chips is copied as it reads, and a range outside the text copies nothing")
    func plainRange() {
        let text = built("Plain **bold** and `code`.")
        #expect(copied(text) == "Plain bold and code.")
        #expect(copied(text, from: "bold", through: "and") == "bold and")
        #expect(MarkdownAttributedText.copied(from: text, in: NSRange(location: 400, length: 5)) == "")
        #expect(MarkdownAttributedText.copied(from: text, in: NSRange(location: 15, length: 500)) == "code.")
    }

    @Test("a thin space the answer itself wrote is kept: only a chip's own room is left out")
    func writtenThinSpace() {
        let text = built("10\u{2009}km \u{3010}1-source\u{3011} away")
        #expect(copied(text) == "10\u{2009}km away")
    }
}
