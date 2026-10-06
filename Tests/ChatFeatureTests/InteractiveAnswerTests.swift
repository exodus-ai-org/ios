import Foundation
import Testing

@testable import ChatFeature

// The same vectors as the desktop's tests/unit/shared/utils/interactive-answer.test.ts — keep them in step.
private let askSource =
    #"{"title":"我想先确认一下你的具体情况","questions":[{"id":"where","text":"哪里最痒？","type":"single","options":["小腿","手臂","全身到处都痒"],"other":true},{"id":"when","text":"什么时候最痒？","type":"multi","options":["洗澡后","晚上","全天"]}],"note":"还有什么想补充的？","submit":"提交，帮我判断"}"#
private let confirmSource =
    #"{"title":"要我把这份行程写进日历吗？","details":"10 月 21–25 日，五天，17 个地点；日历「旅行」。","approve":"写进去","reject":"先不要","note":"有要改的地方可以写在这里"}"#
private let sizesSource =
    #"{"title":"Pick a plan","questions":[{"id":"size","text":"Which sizes?","type":"multi","options":["Small, cheap","Medium","Large, roomy"],"other":true}]}"#
private let quotedSource = #"{"title":"Send \"Q3/Q4\" report?"}"#

private let zh = InteractiveAnswer.Labels(other: "其他", addition: "补充", note: "备注", approved: "同意", rejected: "拒绝")
private let en = InteractiveAnswer.Labels(
    other: "Other", addition: "Also", note: "Note", approved: "Approved", rejected: "Rejected")

private let answerCJK =
    #"```exodus-answer\#n{"block":"ask","ref":"a9f2","title":"我想先确认一下你的具体情况"}\#n```\#n\#n"#
    + #"**哪里最痒？** 小腿\#n**什么时候最痒？** 洗澡后, 晚上\#n**补充:** 用的是丝塔芙润肤乳"#
private let answerOther =
    #"```exodus-answer\#n{"block":"ask","ref":"a9f2","title":"我想先确认一下你的具体情况"}\#n```\#n\#n"#
    + #"**哪里最痒？** 其他: 脚踝 和脚背\#n**什么时候最痒？** —"#
private let answerCommas =
    #"```exodus-answer\#n{"block":"ask","ref":"r-2","title":"Pick a plan"}\#n```\#n\#n"#
    + #"**Which sizes?** Small, cheap, Large, roomy, Other"#
private let answerApprove =
    #"```exodus-answer\#n{"block":"confirm","decision":"approve","ref":"c1","title":"要我把这份行程写进日历吗？"}\#n```\#n\#n"#
    + #"**要我把这份行程写进日历吗？** 同意\#n**备注:** 第三天换成京都"#
private let answerReject =
    #"```exodus-answer\#n{"block":"confirm","decision":"reject","ref":"c2","title":"Send \"Q3/Q4\" report?"}\#n```\#n\#n"#
    + #"**Send "Q3/Q4" report?** Rejected"#

private struct NotABlock: Error {}
private func ask(_ source: String) throws -> InteractiveBlock.Ask {
    guard case .ask(let block)? = InteractiveBlock.parse(.ask, source: source) else { throw NotABlock() }
    return block
}
private func confirm(_ source: String) throws -> InteractiveBlock.Confirm {
    guard case .confirm(let block)? = InteractiveBlock.parse(.confirm, source: source) else { throw NotABlock() }
    return block
}

@Suite("InteractiveAnswer: a block's answer as the user's next message, as the desktop writes it")
struct InteractiveAnswerTests {
    @Test("a line a question, the picks in the options' order, then the closing note")
    func askAnswer() throws {
        let text = InteractiveAnswer.composeAsk(
            try ask(askSource), ref: "a9f2",
            responses: ["where": .init(options: ["小腿"]), "when": .init(options: ["晚上", "洗澡后"])],
            note: "用的是丝塔芙润肤乳", labels: zh)
        #expect(text == answerCJK)
    }

    @Test("Other with its text on one line, a blank as —, no note line when none was typed")
    func otherAndBlank() throws {
        let text = InteractiveAnswer.composeAsk(
            try ask(askSource), ref: "a9f2", responses: ["where": .init(options: [], other: "脚踝\n和脚背")],
            note: "  ", labels: zh)
        #expect(text == answerOther)
    }

    @Test("an option's commas kept, Other picked with nothing typed as the word alone")
    func commas() throws {
        let text = InteractiveAnswer.composeAsk(
            try ask(sizesSource), ref: "r-2",
            responses: ["size": .init(options: ["Large, roomy", "Small, cheap"], other: "")], note: "", labels: en)
        #expect(text == answerCommas)
    }

    @Test("a confirmation: the title and the decision, then the note")
    func confirmAnswer() throws {
        #expect(
            InteractiveAnswer.composeConfirm(
                try confirm(confirmSource), ref: "c1", approved: true, note: "第三天换成京都", labels: zh) == answerApprove)
        #expect(
            InteractiveAnswer.composeConfirm(try confirm(quotedSource), ref: "c2", approved: false, note: "\n", labels: en)
                == answerReject)
    }

    @Test("split reads the fence and the lines after it")
    func split() {
        let cjk = InteractiveAnswer.split(answerCJK)
        #expect(cjk.head == .init(block: .ask, decision: nil, ref: "a9f2", title: "我想先确认一下你的具体情况"))
        #expect(cjk.body == "**哪里最痒？** 小腿\n**什么时候最痒？** 洗澡后, 晚上\n**补充:** 用的是丝塔芙润肤乳")
        #expect(
            InteractiveAnswer.split(answerReject).head
                == .init(block: .confirm, decision: .reject, ref: "c2", title: #"Send "Q3/Q4" report?"#))
        let alone = InteractiveAnswer.split("```exodus-answer\n{\"block\":\"confirm\",\"ref\":\"r\"}\n```")
        #expect(alone.head == .init(block: .confirm, decision: nil, ref: "r", title: nil))
        #expect(alone.body == "")
    }

    @Test(
        "what is not an answer is returned whole",
        arguments: [
            "hello",
            "```exodus-answer\n{oops}\n```\n\nhi",
            "```exodus-answer\n{\"block\":\"poll\",\"ref\":\"r\"}\n```\n\nhi",
            "```exodus-answer\n{\"block\":\"ask\"}\n```\n\nhi",
            "```exodus-answer\n{\"block\":\"ask\",\"ref\":\"r\"}",
        ])
    func notAnAnswer(_ text: String) {
        let split = InteractiveAnswer.split(text)
        #expect(split.head == nil)
        #expect(split.body == text)
    }

    @Test("picks read each question back from its line")
    func picks() throws {
        let block = try ask(askSource)
        #expect(
            InteractiveAnswer.picks(block, body: InteractiveAnswer.split(answerCJK).body) == [
                "where": .init(options: ["小腿"], other: false), "when": .init(options: ["洗澡后", "晚上"], other: false),
            ])
        #expect(
            InteractiveAnswer.picks(block, body: InteractiveAnswer.split(answerOther).body) == [
                "where": .init(options: [], other: true), "when": .init(options: [], other: false),
            ])
        #expect(
            InteractiveAnswer.picks(try ask(sizesSource), body: InteractiveAnswer.split(answerCommas).body) == [
                "size": .init(options: ["Small, cheap", "Large, roomy"], other: true)
            ])
        #expect(InteractiveAnswer.picks(try ask(sizesSource), body: "") == ["size": .init(options: [], other: false)])
    }

    @Test("picks are read back without knowing the language they were written in")
    func picksWithoutLabels() throws {
        let block = try ask(sizesSource)
        let japanese = InteractiveAnswer.composeAsk(
            block, ref: "r", responses: ["size": .init(options: ["Medium"], other: "特大")], note: "メモ",
            labels: .init(other: "その他", addition: "補足", note: "メモ", approved: "承認済み", rejected: "却下済み"))
        #expect(
            InteractiveAnswer.picks(block, body: InteractiveAnswer.split(japanese).body) == [
                "size": .init(options: ["Medium"], other: true)
            ])
    }

    // Computed with the desktop's own `composeConfirmAnswer` (JSON.stringify): `"` and `\` escaped, `/` not,
    // \n \t as short escapes, other controls as \u00XX, DEL, U+2028 and non-ASCII as they are. The note's line
    // breaks (\n, \r\n, \r) and the JS whitespace around them (U+2028, NBSP) fold to one space; NEL is not a break.
    @Test("the fence's JSON byte for byte as the desktop's, and the note on one line as JS folds it")
    func escapes() {
        let block = InteractiveBlock.Confirm(
            title: "Say \"hi\" a/b c\\d\ne\t\u{1}\u{7f}\u{2028}\u{e9}", details: nil, approve: nil, reject: nil, note: nil)
        let text = InteractiveAnswer.composeConfirm(
            block, ref: "x/1", approved: true, note: " a \u{2028}\r\n\u{a0} b\r c\u{85}d ", labels: en)
        #expect(
            text
                == "```exodus-answer\n{\"block\":\"confirm\",\"decision\":\"approve\",\"ref\":\"x/1\","
                + "\"title\":\"Say \\\"hi\\\" a/b c\\\\d\\ne\\t\\u0001\u{7f}\u{2028}\u{e9}\"}\n```\n\n"
                + "**Say \"hi\" a/b c\\d\ne\t\u{1}\u{7f}\u{2028}\u{e9}** Approved\n**Note:** a b c\u{85}d")
        #expect(InteractiveAnswer.split(text).head?.title == block.title)
    }

    @Test(
        "oneLine breaks only at \\n, \\r\\n and \\r, as JS does",
        arguments: [
            ("a\nb", "a b"), ("a\r\nb", "a b"), ("a\rb", "a b"), ("  a \n\n  b  ", "a b"), ("a  b", "a  b"),
            ("a\u{2028}b", "a\u{2028}b"), ("a\u{85}b", "a\u{85}b"), ("a\u{0B}b", "a\u{0B}b"), ("\u{FEFF}a\u{3000}", "a"),
        ])
    func oneLine(_ input: String, _ output: String) {
        #expect(InteractiveAnswer.oneLine(input) == output)
    }

    @Test("options are told apart by their code units, as JS compares them")
    func codeUnits() throws {
        let decomposed = "e\u{301}"
        let block = try #require(
            InteractiveBlock.parse(
                .ask,
                source: #"{"title":"T","questions":[{"id":"a","text":"Q","type":"multi","options":["\#(decomposed)","\#u{e9}"]}]}"#
            ))
        guard case .ask(let ask) = block else { return }
        let text = InteractiveAnswer.composeAsk(
            ask, ref: "r", responses: ["a": .init(options: [decomposed])], note: "", labels: en)
        #expect(text.hasSuffix("**Q** \(decomposed)"))
        #expect(InteractiveAnswer.picks(ask, body: InteractiveAnswer.split(text).body)["a"]?.options == [decomposed])
    }
}
