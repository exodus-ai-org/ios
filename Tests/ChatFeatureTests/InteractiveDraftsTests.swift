import Testing

@testable import ChatFeature

private func question(_ type: InteractiveBlock.Ask.Question.Kind, options: [String], other: Bool = true) throws
    -> InteractiveBlock.Ask
{
    let quoted = options.map { "\"\($0)\"" }.joined(separator: ",")
    let source =
        #"{"title":"T","questions":[{"id":"a","text":"Q a","type":""# + type.rawValue + #"","options":["#
        + quoted + #"],"other":"# + (other ? "true" : "false") + "}]}"
    guard case .ask(let block)? = InteractiveBlock.parse(.ask, source: source) else {
        throw CancellationError()
    }
    return block
}

@MainActor
@Suite("InteractiveDrafts: an answer being made outlives its view")
struct InteractiveDraftsTests {
    @Test("a draft is kept by run, read back, and cleared when its block freezes")
    func store() throws {
        let block = try question(.multi, options: ["x", "y"])
        let drafts = InteractiveDrafts()
        #expect(drafts["r1"] == InteractiveDraft())
        drafts["r1"].pick(block.questions[0], 1)
        drafts["r1"].note = "soon"
        // A view drawn again (the lazy transcript let the first one go) reads the same draft.
        #expect(drafts["r1"].isPicked(block.questions[0], 1))
        #expect(drafts["r1"].note == "soon")
        #expect(drafts["r2"] == InteractiveDraft())
        drafts.clear("r1")
        #expect(drafts["r1"] == InteractiveDraft())
    }

    @Test("picks are kept by place: two canonically equal options are two choices")
    func byPlace() throws {
        let block = try question(.single, options: ["Caf\u{E9}", "Cafe\u{301}"], other: false)
        let q = block.questions[0]
        var draft = InteractiveDraft()
        draft.pick(q, 1)
        #expect(!draft.isPicked(q, 0))
        #expect(draft.isPicked(q, 1))
        let responses = draft.responses(block)
        #expect(responses["a"]?.options.map { Array($0.utf16) } == [Array("Cafe\u{301}".utf16)])
    }

    @Test("one answer: a pick replaces the last, Other included; several: each toggles")
    func picking() throws {
        let single = try question(.single, options: ["x", "y"]).questions[0]
        var draft = InteractiveDraft()
        draft.pick(single, 0)
        draft.pickOther(single)
        #expect(!draft.isPicked(single, 0) && draft.isOtherPicked(single))
        draft.pick(single, 1)
        #expect(draft.isPicked(single, 1) && !draft.isOtherPicked(single))

        let multi = try question(.multi, options: ["x", "y"]).questions[0]
        draft = InteractiveDraft()
        draft.pick(multi, 0)
        draft.pick(multi, 1)
        draft.pick(multi, 0)
        draft.pickOther(multi)
        #expect(draft.picks["a"] == [1] && draft.isOtherPicked(multi))
        draft.pickOther(multi)
        #expect(!draft.isOtherPicked(multi))
    }
}
