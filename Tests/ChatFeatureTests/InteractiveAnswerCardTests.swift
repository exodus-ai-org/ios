import Testing

@testable import ChatFeature

@Suite("InteractiveAnswerCard: an answer drawn as what it is")
struct InteractiveAnswerCardTests {
    @Test("each line's bold lead and what follows it; a line without one, and blank lines")
    func lines() {
        let lines = InteractiveAnswerCard.lines("**Where?** Legs, Arms\n\n**Also:** unscented lotion\nplain words\n")
        #expect(
            lines == [
                .init(label: "Where?", value: "Legs, Arms"), .init(label: "Also:", value: "unscented lotion"),
                .init(label: nil, value: "plain words"),
            ])
    }

    @Test("a line that is a bold lead alone is a lead with nothing after it, not asterisks")
    func leadAlone() {
        #expect(
            InteractiveAnswerCard.lines("**Where?**\n**Also:** soon")
                == [.init(label: "Where?", value: ""), .init(label: "Also:", value: "soon")])
        #expect(InteractiveAnswerCard.lines("****") == [.init(label: nil, value: "****")])
    }

    @Test("the card's symbol says what was answered and how")
    func symbol() {
        #expect(InteractiveAnswerCard.symbol(for: .init(block: .ask, ref: "r", title: "T")) == "checklist")
        #expect(
            InteractiveAnswerCard.symbol(for: .init(block: .confirm, decision: .approve, ref: "r", title: "T"))
                == "checkmark.circle")
        #expect(
            InteractiveAnswerCard.symbol(for: .init(block: .confirm, decision: .reject, ref: "r", title: "T"))
                == "xmark.circle")
    }
}
