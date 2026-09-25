import Foundation
import SwiftUI
import Testing

@testable import MarkdownKit

@Suite("MarkdownInlineStyler")
struct MarkdownInlineStylerTests {
    private let citations: [Int: MarkdownCitation] = [
        1: MarkdownCitation(number: 1, title: "Swift", host: "www.swift.org"),
        2: MarkdownCitation(number: 2, title: "Docs", host: nil),
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

    private func run(_ output: MarkdownInlineStyler.Output, containing needle: String) -> AttributedString.Runs.Run? {
        output.text.runs.first { String(output.text[$0.range].characters).contains(needle) }
    }

    @Test("font per intent")
    func fonts() {
        let body = MarkdownFontSpec.body
        #expect(MarkdownInlineStyler.font(for: [], spec: body) == Font.system(.body))
        #expect(MarkdownInlineStyler.font(for: .stronglyEmphasized, spec: body) == Font.system(.body).bold())
        #expect(MarkdownInlineStyler.font(for: .emphasized, spec: body) == Font.system(.body).italic())
        let heading = MarkdownFontSpec(style: .title2, weight: .semibold)
        #expect(
            MarkdownInlineStyler.font(for: [.stronglyEmphasized, .emphasized], spec: heading)
                == Font.system(.title2).weight(.semibold).bold().italic())
    }

    @Test("bold, italic, code and strike become fonts and attributes; intents are cleared")
    func runsAreStyled() {
        let output = styled("a **b** *c* `d` ~~e~~")
        #expect(String(output.text.characters) == "a b c d e")
        #expect(run(output, containing: "b")?.font == Font.system(.body).bold())
        #expect(run(output, containing: "c")?.font == Font.system(.body).italic())
        let code = run(output, containing: "d")
        #expect(code?.font == Font.system(.callout).monospaced())
        #expect(code?.backgroundColor == MarkdownInlineStyler.codeBackground)
        #expect(run(output, containing: "e")?.strikethroughStyle == .single)
        #expect(output.text.runs.allSatisfy { $0.inlinePresentationIntent == nil })
        #expect(output.chips.isEmpty)
    }

    @Test("links keep their URL")
    func links() {
        let output = styled("see [site](https://example.com) now")
        #expect(run(output, containing: "site")?.link == URL(string: "https://example.com"))
    }

    @Test("a resolved marker becomes a chip linking exodus-cite://N")
    func chip() {
        let output = styled("Fact \u{3010}1-source\u{3011}.")
        #expect(output.chips == [1])
        let chip = run(output, containing: "swift.org")
        #expect(chip?.link == URL(string: "exodus-cite://1"))
        #expect(chip?.font == MarkdownInlineStyler.chipFont)
        #expect(chip?.backgroundColor == MarkdownInlineStyler.chipBackground)
        #expect(String(output.text.characters) == "Fact \u{202F}swift.org.")
    }

    @Test("a chip right after a word gets a thin space")
    func chipSpacing() {
        let output = styled("Fact\u{3010}2-source\u{3011}")
        #expect(String(output.text.characters) == "Fact\u{2009}\u{202F}Docs\u{202F}")
    }

    @Test("an unresolved marker is stripped and the double space collapsed")
    func unresolved() {
        let output = styled("before \u{3010}9-source\u{3011} after")
        #expect(String(output.text.characters) == "before after")
        #expect(output.chips.isEmpty)
    }

    @Test("a multi-marker resolves what it can, each chip once")
    func multiMarker() {
        let output = styled("x \u{3010}1,9,2-source\u{3011} and again \u{3010}1-source\u{3011}")
        #expect(output.chips == [1, 2])
        #expect(!String(output.text.characters).contains("9"))
    }

    @Test("inline code steps down one text style (about 0.9 em)")
    func codeSize() {
        #expect(MarkdownFontSpec.body.codeFont == Font.system(.callout).monospaced())
        #expect(MarkdownFontSpec(style: .subheadline).codeFont == Font.system(.footnote).monospaced())
        #expect(
            MarkdownFontSpec(style: .headline).codeFont == Font.system(.callout).weight(.semibold).monospaced())
    }

    @Test("consecutive chips are separated by an unfilled space")
    func adjacentChips() {
        let output = styled("x \u{3010}1-source\u{3011}\u{3010}2-source\u{3011} y")
        #expect(String(output.text.characters) == "x \u{202F}swift.org\u{202F} \u{202F}Docs\u{202F} y")
        let gap = output.text.runs.first { String(output.text[$0.range].characters) == " " && $0.link == nil }
        #expect(gap != nil)
        #expect(gap?.backgroundColor == nil)
    }

    @Test("punctuation after a chip is not stranded behind its padding")
    func chipThenPunctuation() {
        #expect(String(styled("a \u{3010}2-source\u{3011}: b").text.characters) == "a \u{202F}Docs: b")
        #expect(String(styled("a \u{3010}2-source\u{3011} b").text.characters) == "a \u{202F}Docs\u{202F} b")
    }

    @Test("no citations strips every marker")
    func noCitations() {
        let output = MarkdownInlineStyler.style(
            paragraph("a \u{3010}1-source\u{3011} b"), spec: .body, citations: [:])
        #expect(String(output.text.characters) == "a b")
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
