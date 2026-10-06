import CoreGraphics
import Testing

@testable import ChatFeature

/// The user's bubble: drawn as Markdown that keeps the person's line breaks, and cut short past ten lines.
@Suite("UserBubbleRules")
struct UserBubbleRulesTests {
    private let line: CGFloat = 20
    private var cap: CGFloat { UserBubbleRules.cap(lineHeight: line, lineSpacing: 4) }

    @Test("a message that opens with an answer fence is the answer, whatever follows; any other is plain")
    func kind() {
        let fence = #"```exodus-answer\#n{"block":"ask","ref":"r1","title":"T"}\#n```"#
        let head = InteractiveAnswer.Head(block: .ask, ref: "r1", title: "T")
        #expect(UserBubbleRules.kind(of: fence + "\n\n**Q a** x") == .answer(head, body: "**Q a** x"))
        let health = "```exodus-health\n{\"day\":\"2026-10-06\"}\n```\n\nHow did I sleep?"
        #expect(UserBubbleRules.kind(of: fence + "\n\n" + health) == .answer(head, body: health))
        let quoted = "> a line\n\nWhat does it mean?"
        #expect(UserBubbleRules.kind(of: fence + "\n\n" + quoted) == .answer(head, body: quoted))
        #expect(UserBubbleRules.kind(of: "How did I sleep?") == .plain)
        #expect(UserBubbleRules.kind(of: health) == .plain)
        #expect(UserBubbleRules.kind(of: "Look:\n" + fence) == .plain)
    }

    @Test("the cap is ten lines and the nine gaps between them")
    func capHeight() {
        let expected: CGFloat = 10 * 20 + 9 * 4
        #expect(cap == expected)
    }

    @Test("a message up to the cap and its slack is shown whole; past it, cut short")
    func clipping() {
        #expect(!UserBubbleRules.isClipped(height: cap - 1, cap: cap, lineHeight: line, isExpanded: false))
        #expect(!UserBubbleRules.isClipped(height: cap + 2 * line, cap: cap, lineHeight: line, isExpanded: false))
        #expect(UserBubbleRules.isClipped(height: cap + 2 * line + 1, cap: cap, lineHeight: line, isExpanded: false))
    }

    @Test("one opened with Show more stays whole")
    func expanded() {
        #expect(!UserBubbleRules.isClipped(height: cap * 5, cap: cap, lineHeight: line, isExpanded: true))
    }

    @Test("not yet measured, nothing is cut")
    func unmeasured() {
        #expect(!UserBubbleRules.isClipped(height: 0, cap: cap, lineHeight: line, isExpanded: false))
    }

    @Test("a single newline becomes a hard break; a blank line, a fenced block's lines and the last line do not")
    func lineBreaks() {
        let text = "one\ntwo\n\nthree\n```\na\nb\n```\nfour"
        #expect(UserBubbleRules.markdown(text) == "one  \ntwo\n\nthree  \n```\na\nb\n```\nfour")
    }

    @Test("paragraphs are prose; a heading, a list or code are not")
    func prose() {
        #expect(UserBubbleRules.isProse("Hello\nthere, **you**."))
        #expect(!UserBubbleRules.isProse("# Title\n\ntext"))
        #expect(!UserBubbleRules.isProse("- a\n- b"))
        #expect(!UserBubbleRules.isProse("```\ncode\n```"))
    }
}
