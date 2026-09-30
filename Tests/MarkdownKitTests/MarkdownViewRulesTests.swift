import Foundation
import SwiftUI
import Testing
import UIKit

@testable import MarkdownKit

@Suite("MarkdownInlineStyler")
struct MarkdownInlineStylerTests {
    private let citations: [Int: MarkdownCitation] = [
        1: MarkdownCitation(number: 1, title: "Swift", host: "www.swift.org"),
        2: MarkdownCitation(number: 2, title: "Docs", host: nil),
        3: MarkdownCitation(
            number: 3, title: "Markets", host: "Yahoo! Finance", iconURL: URL(string: "https://example.com/y.png")),
    ]

    private func paragraph(_ text: String) -> AttributedString {
        guard case .paragraph(let content) = MarkdownParser.parse(text).first?.kind else {
            Issue.record("expected a paragraph for \(text.debugDescription)")
            return AttributedString()
        }
        return content
    }

    private func styled(_ text: String) -> MarkdownInlineStyler.Output {
        MarkdownInlineStyler.style(paragraph(text), spec: .body, citations: citations)
    }

    /// The paragraph as it reads: text as it is, a chip as `⟦label⟧`.
    private func shape(_ output: MarkdownInlineStyler.Output) -> String {
        output.segments.map { segment in
            switch segment {
            case .text(let text): String(text.characters)
            case .chip(let chip): "\u{27E6}\(chip.title)\u{27E7}"
            }
        }.joined()
    }

    private func run(_ output: MarkdownInlineStyler.Output, containing needle: String) -> AttributedString.Runs.Run? {
        for case .text(let text) in output.segments {
            if let run = text.runs.first(where: { String(text[$0.range].characters).contains(needle) }) { return run }
        }
        return nil
    }

    private func chips(_ output: MarkdownInlineStyler.Output) -> [MarkdownChip] {
        output.segments.compactMap { if case .chip(let chip) = $0 { chip } else { nil } }
    }

    @Test("font per intent")
    func fonts() {
        let body = MarkdownFontSpec.body
        #expect(MarkdownInlineStyler.font(for: [], spec: body) == body.font)
        #expect(MarkdownInlineStyler.font(for: .stronglyEmphasized, spec: body) == body.font.bold())
        #expect(MarkdownInlineStyler.font(for: .emphasized, spec: body) == body.font.italic())
        let heading = MarkdownFontSpec(style: .title2, weight: .semibold)
        #expect(
            MarkdownInlineStyler.font(for: [.stronglyEmphasized, .emphasized], spec: heading)
                == heading.font.bold().italic())
    }

    @Test("bold, italic, code and strike become fonts and attributes; intents are cleared")
    func runsAreStyled() {
        let output = styled("a **b** *c* `d` ~~e~~")
        #expect(shape(output) == "a b c d e")
        #expect(run(output, containing: "b")?.font == MarkdownFontSpec.body.font.bold())
        #expect(run(output, containing: "c")?.font == MarkdownFontSpec.body.font.italic())
        let code = run(output, containing: "d")
        #expect(code?.font == MarkdownFontSpec.body.codeFont)
        #expect(code?.backgroundColor == MarkdownInlineStyler.codeBackground)
        #expect(run(output, containing: "e")?.strikethroughStyle == .single)
        for case .text(let text) in output.segments {
            #expect(text.runs.allSatisfy { $0.inlinePresentationIntent == nil })
        }
        #expect(output.chips.isEmpty)
    }

    @Test("links keep their URL")
    func links() {
        let output = styled("see [site](https://example.com) now")
        #expect(run(output, containing: "site")?.link == URL(string: "https://example.com"))
        #expect(run(output, containing: "site")?.underlineStyle == nil)
    }

    @Test("where the tint is black and white a link is underlined, and only the link")
    func underlinedLinks() {
        let output = MarkdownInlineStyler.style(
            paragraph("see [site](https://example.com) now \u{3010}1-source\u{3011}"), spec: .body,
            citations: citations, underlinesLinks: true)
        #expect(run(output, containing: "site")?.underlineStyle == .single)
        #expect(run(output, containing: "see")?.underlineStyle == nil)
        #expect(run(output, containing: "now")?.underlineStyle == nil)
        #expect(output.chips == [1])
    }

    @Test("a resolved marker becomes a chip of its own, between the text around it")
    func chip() {
        let output = styled("Fact \u{3010}1-source\u{3011}.")
        #expect(output.chips == [1])
        #expect(shape(output) == "Fact\u{2009}\u{27E6}swift.org\u{27E7}.")
        #expect(chips(output) == [MarkdownChip(numbers: [1], label: "swift.org", iconURL: nil)])
        #expect(chips(output).first?.link == URL(string: "exodus-cite://1"))
    }

    @Test("a chip keeps a thin space from the word before it and from the word after it")
    func chipSpacing() {
        #expect(shape(styled("Fact\u{3010}2-source\u{3011}")) == "Fact\u{2009}\u{27E6}Docs\u{27E7}")
        #expect(shape(styled("a\u{3010}2-source\u{3011}b")) == "a\u{2009}\u{27E6}Docs\u{27E7}\u{2009}b")
    }

    @Test("the space around a chip is the same thin space whatever was written there")
    func chipSpacingIsEven() {
        #expect(shape(styled("a \u{3010}2-source\u{3011} b")) == "a\u{2009}\u{27E6}Docs\u{27E7}\u{2009}b")
        #expect(shape(styled("a  \u{3010}2-source\u{3011}  b")) == "a\u{2009}\u{27E6}Docs\u{27E7}\u{2009}b")
        // Han text has no spaces; the chip gets its own.
        #expect(shape(styled("\u{4E0A}\u{6DA8}\u{3010}2-source\u{3011}\u{4E0D}\u{8FC7}")) == "\u{4E0A}\u{6DA8}\u{2009}\u{27E6}Docs\u{27E7}\u{2009}\u{4E0D}\u{8FC7}")
    }

    @Test("a chip that opens its paragraph has nothing before it: it sits on the text's edge")
    func chipAtTheStart() {
        let output = styled("\u{3010}2-source\u{3011} then text")
        #expect(shape(output) == "\u{27E6}Docs\u{27E7}\u{2009}then text")
        if case .chip = output.segments.first {} else { Issue.record("the chip is not first") }
    }

    @Test("a chip reads its name and, apart from it, how many more it stands for")
    func chipCount() {
        let several = chips(styled("x \u{3010}3-source\u{3011}\u{3010}1-source\u{3011}\u{3010}2-source\u{3011}")).first
        #expect(several?.label == "Yahoo!\u{00A0}Finance")
        #expect(several?.countText == "+2")
        #expect(chips(styled("x \u{3010}3-source\u{3011}")).first?.countText == nil)
    }

    @Test("an unresolved marker is stripped and the double space collapsed")
    func unresolved() {
        let output = styled("before \u{3010}9-source\u{3011} after")
        #expect(shape(output) == "before after")
        #expect(output.chips.isEmpty)
    }

    @Test("a multi-marker is one chip for what it resolves, and each citation is listed once")
    func multiMarker() {
        let output = styled("x \u{3010}1,9,2-source\u{3011} and again \u{3010}1-source\u{3011}")
        #expect(output.chips == [1, 2])
        #expect(shape(output) == "x\u{2009}\u{27E6}swift.org\u{00A0}+1\u{27E7}\u{2009}and again\u{2009}\u{27E6}swift.org\u{27E7}")
        #expect(chips(output).first?.numbers == [1, 2])
    }

    @Test("inline code steps down one text style (about 0.9 em)")
    func codeSize() {
        #expect(MarkdownFontSpec.body.codeFont == MarkdownFontSpec(style: .callout).font.monospaced())
        #expect(MarkdownFontSpec(style: .subheadline).codeFont == MarkdownFontSpec(style: .footnote).font.monospaced())
        #expect(
            MarkdownFontSpec(style: .headline).codeFont
                == MarkdownFontSpec(style: .callout, weight: .semibold).font.monospaced())
    }

    @Test("chips side by side, or with only a space between them, are one chip")
    func adjacentChips() {
        let tight = styled("x \u{3010}1-source\u{3011}\u{3010}2-source\u{3011} y")
        #expect(shape(tight) == "x\u{2009}\u{27E6}swift.org\u{00A0}+1\u{27E7}\u{2009}y")
        let spaced = styled("x \u{3010}1-source\u{3011} \u{3010}2-source\u{3011} \u{3010}1-source\u{3011} y")
        #expect(shape(spaced) == "x\u{2009}\u{27E6}swift.org\u{00A0}+1\u{27E7}\u{2009}y")
        #expect(chips(spaced).first?.numbers == [1, 2])
    }

    @Test("punctuation after a chip follows it directly")
    func chipThenPunctuation() {
        #expect(shape(styled("a \u{3010}2-source\u{3011}: b")) == "a\u{2009}\u{27E6}Docs\u{27E7}: b")
        #expect(shape(styled("a \u{3010}2-source\u{3011}\u{3002}b")) == "a\u{2009}\u{27E6}Docs\u{27E7}\u{3002}b")
        // Nothing stands between the chip and the mark, even where a space was written.
        #expect(shape(styled("a \u{3010}2-source\u{3011} .")) == "a\u{2009}\u{27E6}Docs\u{27E7}.")
        #expect(shape(styled("a \u{3010}2-source\u{3011} \u{3002}")) == "a\u{2009}\u{27E6}Docs\u{27E7}\u{3002}")
    }

    @Test("a chip holds no place a line may break at: not in its name, not before its count")
    func chipDoesNotBreak() {
        let several = chips(styled("x \u{3010}3-source\u{3011}\u{3010}1-source\u{3011}\u{3010}2-source\u{3011}")).first
        #expect(several?.title == "Yahoo!\u{00A0}Finance\u{00A0}+2")
        let awkward = MarkdownChip([
            MarkdownCitation(number: 1, host: "Lufkin\tDaily\u{200B} News-TX\u{00AD}"),
            MarkdownCitation(number: 2),
        ])
        #expect(awkward.title == "Lufkin\u{00A0}Daily\u{00A0}News\u{2011}TX\u{00A0}+1")
        for title in [several?.title ?? " ", awkward.title] {
            let breaks = title.unicodeScalars.filter { MarkdownChip.breakingScalars.contains($0) }
            #expect(breaks.isEmpty, "\(title.debugDescription) can break")
        }
        #expect(MarkdownChip.breakingScalars.isSuperset(of: [" ", "\t", "\n", "\u{200B}", "-", "\u{00AD}"]))
    }

    @Test("a chip is never broken across lines, and carries its icon")
    func chipLabel() {
        let chip = chips(styled("x \u{3010}3-source\u{3011}")).first
        #expect(chip?.label == "Yahoo!\u{00A0}Finance")
        #expect(chip?.iconURL == URL(string: "https://example.com/y.png"))
    }

    @Test("no citations strips every marker")
    func noCitations() {
        let output = MarkdownInlineStyler.style(
            paragraph("a \u{3010}1-source\u{3011} b"), spec: .body, citations: [:])
        #expect(shape(output) == "a b")
    }
}

@Suite("Citation chip: how it is set into a line")
struct MarkdownChipMetricsTests {
    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }

    @Test("at the default text size: a 9 pt label, an 11 pt icon, a 15 pt capsule, 2 / 3 / 5 pt of room inside")
    func defaultSize() {
        let chip = MarkdownChipMetrics(textSize: 16, scaledLabelSize: 9)
        #expect(chip.labelSize == 9)
        #expect(near(chip.iconSide, 11))
        #expect(near(chip.capsuleHeight, 15))
        #expect(near(chip.leading, 2))
        #expect(near(chip.gap, 3))
        #expect(near(chip.trailing, 5))
    }

    @Test("the capsule stands on the middle of the text, its icon and its label on the capsule's middle")
    func position() {
        let chip = MarkdownChipMetrics(textSize: 16, scaledLabelSize: 9)
        #expect(near(chip.centre, 16 * MarkdownChipMetrics.centreShare))
        #expect(near(chip.iconLift + chip.iconSide / 2, chip.centre))
        #expect(near(chip.labelLift + MarkdownChipMetrics.middle(ofLabel: 9), chip.centre))
        // Inside the line: under the text's ascent, over its descent.
        let text = UIFont.systemFont(ofSize: 16)
        #expect(chip.centre + chip.capsuleHeight / 2 <= text.ascender)
        #expect(chip.capsuleHeight / 2 - chip.centre <= -text.descender)
    }

    @Test("the label grows with the text size setting, and never past what its line can hold")
    func growsAndIsCapped() {
        let larger = MarkdownChipMetrics(textSize: 19, scaledLabelSize: 11)
        #expect(larger.labelSize == 11)
        #expect(near(larger.capsuleHeight, 15 * 11 / 9))
        let capped = MarkdownChipMetrics(textSize: 16, scaledLabelSize: 14)
        #expect(near(capped.labelSize, 16 * MarkdownChipMetrics.largestShare))
        for (text, label) in [(16.0, 9.0), (16, 14), (19, 11), (28, 18), (53, 40), (13, 9)] {
            let chip = MarkdownChipMetrics(textSize: text, scaledLabelSize: label)
            let font = UIFont.systemFont(ofSize: text)
            #expect(chip.capsuleHeight <= font.lineHeight, "\(text) / \(label)")
            #expect(chip.centre + chip.capsuleHeight / 2 <= font.ascender + 0.01, "\(text) / \(label)")
        }
    }

    @Test("a space is made as wide as asked, to the point: what the font gives and the rest as kerning")
    func exactSpaces() {
        let font = UIFont.systemFont(ofSize: 9, weight: .medium)
        for width in [2.0, 3, 5] {
            let kern = MarkdownChipMetrics.kern(toMake: MarkdownChipStyle.space, wide: width, in: font)
            let own = (MarkdownChipStyle.space as NSString).size(withAttributes: [.font: font]).width
            #expect(near(own + kern, width))
        }
    }

    @Test("a mark of punctuation after a chip is drawn up to it: the empty side of its glyph goes under the capsule")
    func punctuationIsDrawnUp() {
        let font = UIFont.systemFont(ofSize: 16)
        // Whatever the mark, what is left between the capsule and its ink is a point at most.
        for mark: Character in [".", ",", ":", ";", "!", "?", "\u{3002}", "\u{FF0C}", "\u{3001}", "\u{FF1A}", "\u{FF09}"] {
            let bearing = MarkdownChipMetrics.leadingBearing(of: mark, in: font)
            let overhang = MarkdownChipMetrics.overhang(before: mark, in: font)
            #expect(overhang >= 0)
            #expect(overhang <= 16 * MarkdownChipMetrics.largestOverhang)
            #expect(bearing - overhang <= 1 || overhang == 16 * MarkdownChipMetrics.largestOverhang, "\(mark)")
        }
        // A Latin stop stands a point and more from where it starts: it is drawn up.
        #expect(MarkdownChipMetrics.overhang(before: ".", in: font) > 0.5)
        // Only punctuation is drawn up: a word keeps its distance.
        #expect(MarkdownChipMetrics.overhang(before: "a", in: font) == 0)
        #expect(MarkdownChipMetrics.overhang(before: "\u{4E0A}", in: font) == 0)
        #expect(MarkdownChipMetrics.overhang(before: nil, in: font) == 0)
    }

    @Test("the chip is small print on a faint fill: secondary ink, the lightest of the system's fills")
    func quiet() {
        #expect(MarkdownChipStyle.ink == Color(uiColor: .secondaryLabel))
        #expect(MarkdownChipStyle.fill == Color(uiColor: .quaternarySystemFill))
        #expect(MarkdownChipMetrics.labelSize == 9)
    }
}

@Suite("Citation chip: its icon")
struct MarkdownChipIconTests {
    private let url = URL(string: "https://icons.example/x.png")!
    private let other = URL(string: "https://fallback.example/x.png")!

    @Test("a chip with no icon, or one not in hand yet, draws the default glyph; the site's own once it is")
    func resolve() {
        let image = UIImage()
        #expect(MarkdownChipIcon.resolve(url: nil, fallback: nil, loaded: [:], cached: { _ in nil }) == .standIn)
        #expect(MarkdownChipIcon.resolve(url: url, fallback: other, loaded: [:], cached: { _ in nil }) == .standIn)
        #expect(MarkdownChipIcon.resolve(url: url, fallback: nil, loaded: [url: image], cached: { _ in nil }) == .site(image))
        #expect(MarkdownChipIcon.resolve(url: url, fallback: nil, loaded: [:], cached: { _ in image }) == .site(image))
        // What the fallback gave is the chip's icon too.
        #expect(
            MarkdownChipIcon.resolve(url: url, fallback: other, loaded: [:], cached: { $0 == other ? image : nil })
                == .site(image))
        #expect(MarkdownChipStyle.standInSymbol == "globe")
    }

    @Test("an icon that does not load gives way to its fallback, and to nothing when that fails too")
    func load() async {
        let image = UIImage()
        let (url, other) = (url, other)
        let asked = Asked()
        func icons(_ answers: [URL: UIImage]) -> MarkdownCitationIcons {
            MarkdownCitationIcons(
                cached: { _ in nil },
                load: { url in
                    await asked.add(url)
                    return answers[url]
                })
        }
        #expect(await MarkdownChipIcon.load(url: url, fallback: other, with: icons([url: image])) === image)
        #expect(await asked.urls == [url])
        #expect(await MarkdownChipIcon.load(url: url, fallback: other, with: icons([other: image])) === image)
        #expect(await asked.urls == [url, url, other])
        #expect(await MarkdownChipIcon.load(url: url, fallback: other, with: icons([:])) == nil)
        #expect(await MarkdownChipIcon.load(url: url, fallback: nil, with: icons([:])) == nil)
    }

    private actor Asked {
        var urls: [URL] = []
        func add(_ url: URL) { urls.append(url) }
    }
}

@Suite("MarkdownFontSpec")
struct MarkdownFontSpecTests {
    @Test("the transcript reads a step smaller than the system's text styles, body at 16 for 17, at every text size")
    func scale() {
        let body = UIFont.preferredFont(forTextStyle: .body).pointSize
        #expect(MarkdownFontSpec.body.pointSize == body * MarkdownFontSpec.scale)
        #expect(abs(MarkdownFontSpec.scale - 16 / 17) < 1e-9)
        #expect(MarkdownFontSpec.scale < 1)
        #expect(MarkdownFontSpec(style: .title2).pointSize > MarkdownFontSpec(style: .title3).pointSize)
    }

    @Test("body is 16 pt at the default text size, and a larger text size gives larger text")
    func dynamicType() {
        let large = UITraitCollection(preferredContentSizeCategory: .large)
        let huge = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
        #expect(abs(MarkdownFontSpec.pointSize(.body, in: large) - 16) < 0.001)
        #expect(MarkdownFontSpec.bodySize == 16)
        #expect(MarkdownFontSpec.pointSize(.body, in: huge) > MarkdownFontSpec.pointSize(.body, in: large))
        #expect(MarkdownFontSpec.pointSize(.title2, in: huge) > MarkdownFontSpec.pointSize(.title2, in: large))
    }

    @Test("a headline is semibold without being told")
    func headline() {
        #expect(MarkdownFontSpec(style: .headline).font == MarkdownFontSpec(style: .headline, weight: .semibold).font)
    }

    @Test("lines of body text stand further apart than the lines of a heading")
    func leading() {
        #expect(MarkdownLayoutRules.lineGap(for: .body) > MarkdownLayoutRules.lineGap(for: MarkdownLayoutRules.headingFont(level: 1)))
        #expect(MarkdownLayoutRules.lineGap(for: .body) >= 0.4)
    }
}

@Suite("MarkdownCitation")
struct MarkdownCitationTests {
    @Test("label prefers host without www, then title, then number")
    func labels() {
        #expect(MarkdownCitation(number: 1, title: "T", host: "www.swift.org").chipLabel == "swift.org")
        #expect(MarkdownCitation(number: 1, title: "Title", host: nil).chipLabel == "Title")
        #expect(MarkdownCitation(number: 1, title: "  ", host: "").chipLabel == "1")
        #expect(MarkdownCitation(number: 7).chipLabel == "7")
    }

    @Test("long labels are truncated with an ellipsis")
    func truncation() {
        let label = MarkdownCitation(number: 1, title: String(repeating: "a", count: 40)).chipLabel
        #expect(label.count == MarkdownCitation.maximumLabelLength)
        #expect(label.hasSuffix("\u{2026}"))
    }

    @Test("cite URL round-trips through the preprocessor")
    func url() {
        #expect(MarkdownPreprocessor.citationNumber(from: MarkdownCitation.citeURL(12)) == 12)
    }
}

@Suite("MarkdownLayoutRules")
struct MarkdownLayoutRulesTests {
    private let paragraph = MarkdownBlock.Kind.paragraph(AttributedString("p"))
    private func heading(_ level: Int) -> MarkdownBlock.Kind { .heading(level: level, content: AttributedString("h")) }

    @Test("the first block has no gap")
    func first() {
        #expect(MarkdownLayoutRules.gap(after: nil, before: paragraph, inList: false) == 0)
        #expect(MarkdownLayoutRules.gap(after: nil, before: heading(1), inList: false) == 0)
    }

    @Test("paragraphs stand a full line apart")
    func paragraphGap() {
        #expect(MarkdownLayoutRules.blockGap >= 1)
        #expect(MarkdownLayoutRules.listGap < MarkdownLayoutRules.blockGap)
    }

    @Test("uniform gap between blocks, tighter in lists")
    func uniform() {
        #expect(MarkdownLayoutRules.gap(after: paragraph, before: paragraph, inList: false) == MarkdownLayoutRules.blockGap)
        #expect(MarkdownLayoutRules.gap(after: paragraph, before: paragraph, inList: true) == MarkdownLayoutRules.listGap)
    }

    @Test("headings: bigger lead-in by level, small gap after")
    func headings() {
        let leads = (1...6).map { MarkdownLayoutRules.gap(after: paragraph, before: heading($0), inList: false) }
        #expect(leads == leads.sorted(by: >))
        #expect(leads.allSatisfy { $0 > MarkdownLayoutRules.blockGap })
        #expect(
            MarkdownLayoutRules.gap(after: heading(2), before: paragraph, inList: false)
                == MarkdownLayoutRules.afterHeadingGap)
    }

    @Test("a thematic break gets room on both sides")
    func rule() {
        #expect(MarkdownLayoutRules.gap(after: paragraph, before: .thematicBreak, inList: false) == MarkdownLayoutRules.ruleGap)
        #expect(MarkdownLayoutRules.gap(after: .thematicBreak, before: paragraph, inList: false) == MarkdownLayoutRules.ruleGap)
    }

    @Test("list markers: numbers from startIndex, bullets by depth")
    func markers() {
        #expect(MarkdownLayoutRules.listMarker(isOrdered: true, number: 3, depth: 0) == "3.")
        let bullets = (0...3).map { MarkdownLayoutRules.listMarker(isOrdered: false, number: 1, depth: $0) }
        #expect(bullets[0] != bullets[1])
        #expect(bullets[1] != bullets[2])
        #expect(bullets[2] == bullets[3])
    }

    @Test("the widest marker covers the last number's digits")
    func widest() {
        func list(start: Int, count: Int) -> MarkdownList {
            MarkdownList(
                isOrdered: true, startIndex: start,
                items: (0..<count).map { MarkdownListItem(id: $0, checkbox: nil, blocks: []) })
        }
        #expect(MarkdownLayoutRules.widestMarker(list(start: 8, count: 4), depth: 0) == "00.")
        #expect(MarkdownLayoutRules.widestMarker(list(start: 1, count: 3), depth: 0) == "0.")
        #expect(MarkdownLayoutRules.widestMarker(list(start: 99, count: 1), depth: 0) == "00.")
    }

    @Test("heading fonts differ by level down to h5")
    func headingFonts() {
        let fonts = (1...5).map { MarkdownLayoutRules.headingFont(level: $0) }
        #expect(Set(fonts).count == 5)
        #expect(MarkdownLayoutRules.headingFont(level: 6) == MarkdownLayoutRules.headingFont(level: 5))
    }
}

@Suite("MarkdownTrailingFade")
struct MarkdownTrailingFadeTests {
    @Test("fades only while content remains to the right")
    func fade() {
        #expect(MarkdownTrailingFade.hasMoreToRight(contentWidth: 600, offset: 0, containerWidth: 360))
        #expect(!MarkdownTrailingFade.hasMoreToRight(contentWidth: 600, offset: 240, containerWidth: 360))
        #expect(!MarkdownTrailingFade.hasMoreToRight(contentWidth: 300, offset: 0, containerWidth: 360))
    }
}
