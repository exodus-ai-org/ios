import SwiftUI

/// A reply's questionnaire (`exodus-ask`) as a card in the answer: its title, the questions numbered, each choice a
/// 44 pt row, "Other…" opening a line to type on, the closing note and Submit. Submit sends the answers as the user's
/// next message (`InteractiveAnswer`); once the transcript holds that message the card is frozen with its picks.
struct QuestionnaireBlockView: View {
    typealias Question = InteractiveBlock.Ask.Question

    let block: InteractiveBlock.Ask
    let runId: String
    let answered: InteractiveAnswered?
    let canAnswer: Bool
    /// False in a compared answer: drawn, held still, never sent.
    var isAnswerable = true
    let sendAnswer: @MainActor @Sendable (String) -> Void

    @State private var responses: [String: InteractiveAnswer.Response] = [:]
    @State private var note = ""
    @State private var selections = 0
    @State private var sent = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOpen: Bool { answered == nil && isAnswerable }

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
            if answered != nil {
                InteractiveAnsweredLine()
            } else {
                InteractiveNoteField(label: block.note, text: $note)
                    .disabled(!isAnswerable)
                Button(action: submit) {
                    submitLabel
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAnswer || !isAnswerable)
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
            ForEach(question.options, id: \.self) { option in
                InteractiveOptionRow(
                    title: option, isMulti: question.type == .multi,
                    isOn: frozen.map { $0.options.contains(option) } ?? isPicked(question, option),
                    isEnabled: isOpen
                ) { pick(question, option) }
            }
            if question.other {
                InteractiveOptionRow(
                    title: InteractiveText.other, isMulti: question.type == .multi,
                    isOn: frozen?.other ?? (responses[question.id]?.other != nil), isEnabled: isOpen
                ) { pickOther(question) }
                if isOpen, responses[question.id]?.other != nil {
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

    private func isPicked(_ question: Question, _ option: String) -> Bool {
        responses[question.id]?.options.contains(option) ?? false
    }

    private func pick(_ question: Question, _ option: String) {
        guard isOpen else { return }
        var response = responses[question.id] ?? .init()
        if question.type == .single {
            response = .init(options: [option], other: nil)
        } else if let index = response.options.firstIndex(of: option) {
            response.options.remove(at: index)
        } else {
            response.options.append(option)
        }
        responses[question.id] = response
        selections += 1
    }

    private func pickOther(_ question: Question) {
        guard isOpen else { return }
        var response = responses[question.id] ?? .init()
        if question.type == .single {
            response = .init(options: [], other: response.other ?? "")
        } else {
            response.other = response.other == nil ? "" : nil
        }
        responses[question.id] = response
        selections += 1
    }

    private func otherText(_ question: Question) -> Binding<String> {
        Binding(
            get: { responses[question.id]?.other ?? "" },
            set: { responses[question.id, default: .init(options: [], other: "")].other = $0 })
    }

    private func submit() {
        guard canAnswer, isOpen else { return }
        sendAnswer(InteractiveAnswer.composeAsk(block, ref: runId, responses: responses, note: note, labels: .current))
        sent += 1
        AccessibilityNotification.Announcement(InteractiveText.sent).post()
    }
}
