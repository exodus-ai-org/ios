import SwiftUI

/// A reply's questionnaire (`exodus-ask`) as a card in the answer: its title, the questions numbered, each choice a
/// 44 pt row, "Other…" opening a line to type on, the closing note and Submit. Submit sends the answers as the user's
/// next message (`InteractiveAnswer`); once the transcript holds that message the card is frozen with its picks.
struct QuestionnaireBlockView: View {
    typealias Question = InteractiveBlock.Ask.Question

    let block: InteractiveBlock.Ask
    let runId: String
    let answered: InteractiveAnswered?
    let mode: InteractiveMode
    /// The picks, the Other texts and the note, kept by the transcript while the block is open.
    let drafts: InteractiveDrafts
    let sendAnswer: @MainActor @Sendable (String) -> Bool

    @State private var selections = 0
    @State private var sent = 0
    @Environment(\.accentGlyph) private var accentGlyph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var draft: InteractiveDraft {
        get { drafts[runId] }
        nonmutating set { drafts[runId] = newValue }
    }

    var body: some View {
        let frozen = answered.map { InteractiveAnswer.picks(block, body: $0.body) }
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: block.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(block.questions.enumerated()), id: \.element.id) { index, question in
                questionView(question, number: index + 1, frozen: frozen?[question.id])
            }
            if mode == .frozen {
                InteractiveAnsweredLine()
            } else if mode.showsActions {
                InteractiveNoteField(label: block.note, text: Binding(get: { draft.note }, set: { draft.note = $0 }))
                Button(action: submit) {
                    submitLabel
                        .font(.body.weight(.semibold))
                        .foregroundStyle(accentGlyph)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .toneFill()
                .disabled(!mode.canSend)
            }
        }
        .padding(CardStyle.inset)
        .modifier(CardSurface())
        .animation(reduceMotion ? nil : .smooth, value: answered != nil)
        .sensoryFeedback(.selection, trigger: selections)
        .sensoryFeedback(.success, trigger: sent)
    }

    private func questionView(_ question: Question, number: Int, frozen: InteractiveAnswer.Picks?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "\(number). \(question.text)")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            // By place, not by text: two canonically equal options are still two choices.
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                InteractiveOptionRow(
                    title: option, isMulti: question.type == .multi,
                    isOn: frozen.map { picks in picks.options.contains { JSText.equal($0, option) } }
                        ?? draft.isPicked(question, index),
                    isEnabled: mode.isOpen
                ) { pick(question, index) }
            }
            if question.other {
                InteractiveOptionRow(
                    title: InteractiveText.other, isMulti: question.type == .multi,
                    isOn: frozen?.other ?? draft.isOtherPicked(question), isEnabled: mode.isOpen
                ) { pickOther(question) }
                if mode.isOpen, draft.isOtherPicked(question) {
                    TextField(text: otherText(question), prompt: Text("ios:chat.block.otherPlaceholder")) {
                        Text("ios:chat.block.otherPlaceholder")
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.fill.tertiary, in: CardStyle.innerShape)
                }
            }
        }
    }

    @ViewBuilder
    private var submitLabel: some View {
        if let label = block.submit, !label.isEmpty {
            Text(verbatim: label)
        } else {
            Text("ios:chat.block.submit")
        }
    }

    private func pick(_ question: Question, _ index: Int) {
        guard mode.isOpen else { return }
        draft.pick(question, index)
        selections += 1
    }

    private func pickOther(_ question: Question) {
        guard mode.isOpen else { return }
        draft.pickOther(question)
        selections += 1
    }

    private func otherText(_ question: Question) -> Binding<String> {
        Binding(
            get: { draft.others[question.id] ?? "" },
            set: { draft.others[question.id] = $0 })
    }

    private func submit() {
        guard mode.canSend else { return }
        let text = InteractiveAnswer.composeAsk(
            block, ref: runId, responses: draft.responses(block), note: draft.note, labels: .current)
        // The haptic and the announcement say it was sent, so only when it was.
        guard sendAnswer(text) else { return }
        sent += 1
        AccessibilityNotification.Announcement(InteractiveText.sent).post()
    }
}
