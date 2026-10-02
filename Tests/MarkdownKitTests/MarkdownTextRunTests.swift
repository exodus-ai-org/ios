import Foundation
import Testing
import UIKit

@testable import MarkdownKit

/// Settled text blocks side by side share one text view, so a selection can be drawn across them: which blocks
/// join a run, and that the run's text stands as the blocks stood one under another.
@Suite("MarkdownTextRuns: settled text blocks in one text view")
@MainActor
struct MarkdownTextRunTests {
    private let em = MarkdownFontSpec.body.pointSize
    private let width: CGFloat = 320

    private func blocks(_ markdown: String) -> [MarkdownBlock] { MarkdownParser.parse(markdown) }

    private func run(_ markdown: String) -> MarkdownRunText {
        var builder = MarkdownRunBuilder(
            style: MarkdownTextStyle(spec: .body), citations: [:], underlinesLinks: false, em: em)
        return builder.build(blocks(markdown))
    }

    private func shape(_ segments: [MarkdownTextRuns.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .run(let blocks): "run(\(blocks.count))"
            case .block(let block): "\(block.kind)".prefix { $0 != "(" }.description
            }
        }.joined(separator: " ")
    }

    private func lines(_ run: MarkdownRunText) -> [MarkdownTextMeasure.Line] {
        MarkdownTextMeasure.lines(of: run.text, width: width)
    }

    private func line(containing needle: String, in run: MarkdownRunText) -> MarkdownTextMeasure.Line? {
        let range = (run.text.string as NSString).range(of: needle)
        let found = lines(run).first { NSLocationInRange(range.location, $0.range) }
        if found == nil { Issue.record("no line holds \(needle.debugDescription)") }
        return found
    }

    /// The room between the last line of the block holding `above` and the first of the block holding `below`.
    private func gap(between above: String, and below: String, in run: MarkdownRunText) -> CGFloat? {
        guard let upper = line(containing: above, in: run), let lower = line(containing: below, in: run) else {
            return nil
        }
        return lower.top - upper.bottom
    }

    @Test("paragraphs, headings, plain lists and quotes join; code, tables, rules, images and task lists stand alone")
    func grouping() {
        let parsed = blocks(
            """
            One

            ## Two

            - three
            - four

            > five

            ```
            code
            ```

            Six

            | a | b |
            |---|---|
            | 1 | 2 |

            Seven

            ---

            - [ ] task

            Eight
            """)
        #expect(
            shape(MarkdownTextRuns.segments(parsed, arriving: nil))
                == "run(4) codeBlock run(1) table run(1) thematicBreak list run(1)")
    }

    @Test("the block still being written stands alone, and the run before it holds the rest")
    func arriving() {
        let parsed = blocks("One\n\nTwo\n\nThree")
        #expect(shape(MarkdownTextRuns.segments(parsed, arriving: parsed.last?.id)) == "run(2) paragraph")
    }

    @Test("a list or quote that holds a code block stands alone")
    func nestedCode() {
        let parsed = blocks("- item\n\n  ```\n  code\n  ```\n\n> quote\n>\n> ```\n> code\n> ```")
        #expect(shape(MarkdownTextRuns.segments(parsed, arriving: nil)) == "list blockquote")
    }

    @Test("blocks stand the stack's gaps apart: a full gap between paragraphs, the heading's lead-in and after")
    func gaps() throws {
        let run = run("First paragraph.\n\nSecond paragraph.\n\n## A heading\n\nThird paragraph.")
        let tolerance: CGFloat = 0.01
        #expect(try abs(#require(gap(between: "First", and: "Second", in: run)) - em * MarkdownLayoutRules.blockGap) < tolerance)
        let lead = MarkdownLayoutRules.gap(after: .paragraph(""), before: .heading(level: 2, content: ""), inList: false)
        #expect(try abs(#require(gap(between: "Second", and: "heading", in: run)) - em * lead) < tolerance)
        #expect(
            try abs(#require(gap(between: "heading", and: "Third", in: run)) - em * MarkdownLayoutRules.afterHeadingGap(level: 2))
                < tolerance)
    }

    @Test("list items stand the list gap apart, and the paragraph after the list a full gap")
    func listGaps() throws {
        let run = run("Intro.\n\n- one\n- two\n\nAfter.")
        let tolerance: CGFloat = 0.01
        #expect(try abs(#require(gap(between: "Intro", and: "one", in: run)) - em * MarkdownLayoutRules.blockGap) < tolerance)
        #expect(try abs(#require(gap(between: "one", and: "two", in: run)) - em * MarkdownLayoutRules.listGap) < tolerance)
        #expect(try abs(#require(gap(between: "two", and: "After", in: run)) - em * MarkdownLayoutRules.blockGap) < tolerance)
    }

    @Test("an item's text starts past the widest marker of its list; a nested list starts where its item's text does")
    func indents() throws {
        let long = String(repeating: "word ", count: 30)
        let run = run("1. \(long)\n10. ten\n    - \(long)nested")
        let bullet = MarkdownFontSpec.body.font.monospacedDigit().resolve(in: MarkdownTextStyle(spec: .body).fonts).ctFont as UIFont
        // Items 1 and 2: the widest marker is one digit and a point.
        let start = ("0." as NSString).size(withAttributes: [.font: bullet]).width + em * 0.4
        let wrapped = lines(run).filter { line in
            let text = (run.text.string as NSString).substring(with: line.range)
            return !text.contains("\t")
        }
        // The first item's second line, under its text.
        #expect(try abs(#require(wrapped.first).x - start) < 0.5)
        // The nested item's last line, under the nested text, past its own bullet.
        let nested = try #require(line(containing: "nested", in: run))
        #expect(nested.x > start + em * 0.4)
    }

    @Test("a quote's rule stands beside all its text, and its text is set in past the rule")
    func quote() throws {
        let run = run("Before.\n\n> First line\n>\n> Second line\n\nAfter.")
        let rule = try #require(run.quotes.first)
        let quoted = (run.text.string as NSString).substring(with: rule.range)
        #expect(quoted.contains("First line") && quoted.contains("Second line") && !quoted.contains("After"))
        // Not the line break before it, which ends the line above.
        #expect(quoted.hasPrefix("First"))
        #expect(rule.x == 0)
        let inner = try #require(line(containing: "Second", in: run))
        #expect(abs(inner.x - (MarkdownQuoteRule.width + em * 0.75)) < 0.5)
    }

    @Test("Copy and Select All take every block: one line each, list markers as themselves")
    func copy() {
        let run = run("First **bold**.\n\n## Heading\n\n- one\n- two\n\n3. three\n\n> quoted")
        let all = MarkdownAttributedText.copied(from: run.text, in: NSRange(location: 0, length: run.text.length))
        #expect(all == "First bold.\nHeading\n• one\n• two\n3. three\nquoted")
    }

    @Test("a heading tells VoiceOver its level; the first block has no room before it")
    func headings() throws {
        let run = run("# Title\n\nBody")
        #expect(run.text.attribute(.accessibilityTextHeadingLevel, at: 0, effectiveRange: nil) as? Int == 1)
        let first = try #require(run.text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(first.paragraphSpacingBefore == 0)
    }

    @Test("a run's text view is set by TextKit 2, and draws its quotes' rules whatever its tint")
    func textView() {
        let view = MarkdownTextView()
        #expect(view.textLayoutManager != nil)
        let run = run("> quoted\n\nAfter.")
        view.attributedText = run.text
        view.quoteRules = run.quotes
        view.frame = CGRect(x: 0, y: 0, width: width, height: 200)
        view.tintColor = .systemRed
        view.layoutIfNeeded()
        let rules = view.subviews.filter { $0.backgroundColor == UIColor.systemRed.withAlphaComponent(0.55) }
        #expect(rules.count == 1)
        #expect(rules.first.map { $0.frame.height > 0 } == true)
    }

    @Test("snapped at a width, each block's first baseline is on the pixel it had standing alone in the stack")
    func snapped() throws {
        let run = run(
            "A paragraph long enough to wrap onto a second line at this width, or a third.\n\n### Heading\n\n- one\n- two\n\nAfter.")
        let scale: CGFloat = 3
        func up(_ value: CGFloat) -> CGFloat { MarkdownTextMeasure.pixels(value, scale: scale, .up) }
        func nearest(_ value: CGFloat) -> CGFloat { MarkdownTextMeasure.pixels(value, scale: scale, .toNearestOrAwayFromZero) }
        func blocks(_ text: NSAttributedString) -> [(top: CGFloat, bottom: CGFloat, baseline: CGFloat)] {
            let lines = MarkdownTextMeasure.lines(of: text, width: width)
            return text.string.components(separatedBy: "\n").reduce(into: (location: 0, found: [(top: CGFloat, bottom: CGFloat, baseline: CGFloat)]())) { state, piece in
                let range = NSRange(location: state.location, length: (piece as NSString).length)
                let own = lines.filter { NSIntersectionRange($0.range, range).length > 0 }
                if let first = own.first, let bottom = own.map(\.bottom).max() {
                    state.found.append((first.top, bottom, first.baseline))
                }
                state.location += range.length + 1
            }.found
        }
        let natural = blocks(run.text)
        let snapped = blocks(MarkdownRunSnap.snapped(run.text, width: width, scale: scale))
        try #require(natural.count == 5 && snapped.count == 5)
        // Standing alone: each block as tall as its text up to a pixel, on the pixel nearest its place, its first
        // baseline on the pixel nearest it; the text view's are all raised by the first one's lift.
        let lift = up(natural[0].baseline) - nearest(natural[0].baseline)
        var stack: CGFloat = 0
        for index in 1..<natural.count {
            let (previous, block) = (natural[index - 1], natural[index])
            stack = nearest(stack) + up(previous.bottom - previous.top) + (block.top - previous.bottom)
            let wanted = nearest(stack) + nearest(block.baseline - block.top) + lift
            #expect(abs(snapped[index].baseline - wanted) < 0.01, "block \(index)")
        }
    }

    @Test("a list that opens an item stands on the item's line, after the item's own marker")
    func listOpensItem() {
        let run = run("Before.\n\n- - inner\n  - second\n- outer")
        let all = MarkdownAttributedText.copied(from: run.text, in: NSRange(location: 0, length: run.text.length))
        #expect(all == "Before.\n• ◦ inner\n◦ second\n• outer")
    }
}
