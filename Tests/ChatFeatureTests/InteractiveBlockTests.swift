import Foundation
import Testing

@testable import ChatFeature

// The same vectors as the desktop's tests/unit/shared/types/interactive.test.ts — keep them in step.
private let askSource =
    #"{"title":"我想先确认一下你的具体情况","questions":[{"id":"where","text":"哪里最痒？","type":"single","options":["小腿","手臂","全身到处都痒"],"other":true},{"id":"when","text":"什么时候最痒？","type":"multi","options":["洗澡后","晚上","全天"]}],"note":"还有什么想补充的？","submit":"提交，帮我判断"}"#
private let confirmSource =
    #"{"title":"要我把这份行程写进日历吗？","details":"10 月 21–25 日，五天，17 个地点；日历「旅行」。","approve":"写进去","reject":"先不要","note":"有要改的地方可以写在这里"}"#

private func q(_ id: String, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["id": id, "text": "Q", "type": "single", "options": ["x", "y"]].merging(extra) { $1 }
}
private func json(_ object: Any) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self)
}
private func ask(_ extra: [String: Any] = [:]) -> String { json(["title": "T", "questions": [q("a")]].merging(extra) { $1 }) }
private func confirm(_ extra: [String: Any] = [:]) -> String { json(["title": "T"].merging(extra) { $1 }) }
private func repeated(_ s: String, _ n: Int) -> String { String(repeating: s, count: n) }

private let askCases: [(String, String, Bool)] = [
    ("the spec's example", askSource, true),
    ("eight questions", ask(["questions": (0..<8).map { q("q\($0)") }]), true),
    ("nine questions", ask(["questions": (0..<9).map { q("q\($0)") }]), false),
    ("no questions", ask(["questions": [Any]()]), false),
    ("an 80-character option", ask(["questions": [q("a", ["options": [repeated("x", 80), "y"]])]]), true),
    ("an 81-character option", ask(["questions": [q("a", ["options": [repeated("x", 81), "y"]])]]), false),
    ("40 emoji (80 UTF-16 units)", ask(["questions": [q("a", ["options": [repeated("😀", 40), "y"]])]]), true),
    ("41 emoji (82 UTF-16 units)", ask(["questions": [q("a", ["options": [repeated("😀", 41), "y"]])]]), false),
    ("one option", ask(["questions": [q("a", ["options": ["x"]])]]), false),
    ("nine options", ask(["questions": [q("a", ["options": (0..<9).map { String($0) }])]]), false),
    ("the same option twice", ask(["questions": [q("a", ["options": ["x", "x"]])]]), false),
    ("two questions with one id", ask(["questions": [q("a"), q("a")]]), false),
    ("an id with a capital", ask(["questions": [q("Where")]]), false),
    ("a 33-character id", ask(["questions": [q(repeated("a", 33))]]), false),
    ("a type that is neither single nor multi", ask(["questions": [q("a", ["type": "text"])]]), false),
    ("an empty title", ask(["title": ""]), false),
    ("a 201-character question", ask(["questions": [q("a", ["text": repeated("q", 201)])]]), false),
    ("a 121-character note", ask(["note": repeated("n", 121)]), false),
    ("a 41-character submit", ask(["submit": repeated("s", 41)]), false),
    ("nulls for what is optional", ask(["note": NSNull(), "submit": NSNull(), "questions": [q("a", ["other": NSNull()])]]), true),
    ("keys it does not know", ask(["colour": "red"]), true),
    ("not JSON", #"{"title":"#, false),
    ("an array", "[]", false),
]

private let confirmCases: [(String, String, Bool)] = [
    ("the spec's example", confirmSource, true),
    ("a title alone", confirm(), true),
    ("no title", json(["details": "d"]), false),
    ("a 201-character title", confirm(["title": repeated("t", 201)]), false),
    ("1000 characters of details", confirm(["details": repeated("d", 1000)]), true),
    ("1001 characters of details", confirm(["details": repeated("d", 1001)]), false),
    ("a 41-character approve", confirm(["approve": repeated("a", 41)]), false),
    ("a 41-character reject", confirm(["reject": repeated("r", 41)]), false),
    ("a 121-character note", confirm(["note": repeated("n", 121)]), false),
]

private let findCases: [(String, String, InteractiveBlock.Kind?)] = [
    ("a questionnaire after a paragraph", "Intro\n\n```exodus-ask\n\(askSource)\n```\n\nAfter", .ask),
    ("a fence still open (a reply streaming)", "Intro\n\n```exodus-ask\n\(askSource)", nil),
    ("two blocks: only the first counts", "```exodus-confirm\n\(confirmSource)\n```\n\n```exodus-ask\n\(askSource)\n```", .confirm),
    ("a first block that does not validate: none", "```exodus-ask\n{oops}\n```\n\n```exodus-confirm\n\(confirmSource)\n```", nil),
    ("inside a longer backtick fence", "````md\n```exodus-ask\n\(askSource)\n```\n````", nil),
    ("inside a tilde fence", "~~~\n```exodus-ask\n\(askSource)\n```\n~~~", nil),
    ("indented under a list item", "- item\n\n  ```exodus-ask\n  \(askSource)\n  ```", nil),
    ("after an ordinary code block", "```js\nlet a = 1\n```\n\n```exodus-confirm\n\(confirmSource)\n```", .confirm),
    ("trailing spaces after the name", "```exodus-confirm  \n\(confirmSource)\n```", .confirm),
    ("another name", "```exodus-answer\n{\"block\":\"ask\",\"ref\":\"r\"}\n```", nil),
]

@Suite("InteractiveBlock: the blocks' limits, as the desktop's zod schemas")
struct InteractiveBlockTests {
    @Test("exodus-ask", arguments: askCases)
    func askLimits(_ name: String, _ source: String, _ valid: Bool) {
        #expect((InteractiveBlock.parse(.ask, source: source) != nil) == valid, "\(name)")
    }

    @Test("exodus-confirm", arguments: confirmCases)
    func confirmLimits(_ name: String, _ source: String, _ valid: Bool) {
        #expect((InteractiveBlock.parse(.confirm, source: source) != nil) == valid, "\(name)")
    }

    @Test("a missing \"other\" is no Other; the fence's names map to kinds")
    func reading() throws {
        guard case .ask(let block)? = InteractiveBlock.parse(.ask, source: askSource) else {
            Issue.record("expected a questionnaire")
            return
        }
        #expect(block.questions.map(\.other) == [true, false])
        #expect(block.questions.map(\.type) == [.single, .multi])
        #expect(InteractiveBlock.Kind(language: "exodus-ask") == .ask)
        #expect(InteractiveBlock.Kind(language: "exodus-confirm") == .confirm)
        #expect(InteractiveBlock.Kind(language: "exodus-answer") == nil)
        #expect(InteractiveBlock.Kind.confirm.language == "exodus-confirm")
    }
}

@Suite("InteractiveFence: which fence of a reply is its block")
struct InteractiveFenceTests {
    @Test("find", arguments: findCases)
    func find(_ name: String, _ markdown: String, _ kind: InteractiveBlock.Kind?) {
        #expect(InteractiveFence.first(in: markdown)?.kind == kind, "\(name)")
    }

    @Test("the fence's text is how its code block is known")
    func matches() throws {
        let fence = try #require(InteractiveFence.first(in: "Intro\n\n```exodus-ask\n\(askSource)\n```\n"))
        #expect(fence.source == askSource)
        #expect(fence.matches(language: "exodus-ask", code: askSource))
        #expect(fence.matches(language: "exodus-ask", code: askSource + "\n"))
        #expect(!fence.matches(language: "exodus-confirm", code: askSource))
        #expect(!fence.matches(language: nil, code: askSource))
        #expect(!fence.matches(language: "exodus-ask", code: "{}"))
    }
}
