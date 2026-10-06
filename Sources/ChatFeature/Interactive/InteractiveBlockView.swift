import MarkdownKit
import Models
import SwiftUI

/// A block's answer as the transcript holds it: the fence's head and the lines after it.
struct InteractiveAnswered: Equatable, Sendable {
    let head: InteractiveAnswer.Head
    let body: String
}

enum InteractiveRendering {
    /// Every block answered so far, by the run whose reply holds it — read off the transcript's user messages, so a
    /// chat opened again finds its blocks frozen with nothing stored. Only a message after the run's reply answers it.
    static func answers(in segments: [Segment]) -> [String: InteractiveAnswered] {
        var answers: [String: InteractiveAnswered] = [:]
        var runs: Set<String> = []
        for segment in segments {
            switch segment {
            case .assistantTurn(let turn):
                runs.insert(turn.runId)
            case .user(let message):
                let split = InteractiveAnswer.split(message.answerText)
                if let head = split.head, runs.contains(head.ref) {
                    answers[head.ref] = InteractiveAnswered(head: head, body: split.body)
                }
            }
        }
        return answers
    }

    /// A compared answer (one column of a regenerate comparison) is not the conversation's reply yet: its block is
    /// drawn, never answered.
    static func isAnswerable(_ turn: AssistantTurn) -> Bool {
        if case .comparing? = turn.attempt { false } else { true }
    }

    /// Whether the turn's block may be sent now: the chat allows an answer and the turn is answerable at all.
    static func canAnswer(_ turn: AssistantTurn, canAnswer: Bool) -> Bool {
        canAnswer && isAnswerable(turn)
    }

    /// The language the host gives its block's fence in the text it hands MarkdownKit: the fence's own name and a
    /// private-use character no reply writes, so no other code block — a second copy, a `~~~` fence, one in a list or
    /// a quote — carries it.
    static func drawnLanguage(_ kind: InteractiveBlock.Kind) -> String { kind.language + "\u{E000}" }

    /// A turn's block and where it stands: the text block (of the answer's texts, in order) whose Markdown holds it,
    /// and that text with the block's fence marked (`drawnLanguage`) and `\n` line ends.
    struct Placed: Equatable {
        let fence: InteractiveFence
        let index: Int
        let text: String
    }

    /// The block of an answer whose text blocks are `texts`: the first top-level closed fence of their whole text
    /// (`InteractiveFence.first`, as the desktop finds it in the joined body), placed in the text block it opens in.
    /// Nil when the answer holds no block.
    static func placed(in texts: [String]) -> Placed? {
        guard texts.contains(where: { $0.contains("```exodus-") }) else { return nil }
        let lines = texts.map { JSText.unixLines($0).split(separator: JSText.lf, omittingEmptySubsequences: false) }
        let joined = JSText.string(Array(lines.map { Array($0.joined(separator: [JSText.lf])) }
            .joined(separator: [JSText.lf, JSText.lf])))
        guard let fence = InteractiveFence.first(in: joined) else { return nil }
        // The texts are joined by a blank line, so each starts one line past the end of the one before.
        var start = 0
        for (index, text) in lines.enumerated() {
            defer { start += text.count + 1 }
            guard fence.line < start + text.count else { continue }
            var marked = text.map(Array.init)
            let opening = Array(("```" + fence.kind.language).utf16)  // l10n:ignore: markdown syntax
            let local = fence.line - start
            guard marked[local].starts(with: opening) else { return nil }
            marked[local].replaceSubrange(0..<opening.count, with: Array(("```" + drawnLanguage(fence.kind)).utf16))  // l10n:ignore: markdown syntax
            return Placed(
                fence: fence, index: index, text: JSText.string(Array(marked.joined(separator: [JSText.lf]))))
        }
        return nil
    }

    /// What a turn's Markdown draws for its fenced blocks: its own block (`fence`, at the place `placed` marked) as
    /// the control, every other fence as code. Nil when the turn holds no block.
    static func fencedBlocks(
        fence: InteractiveFence?, runId: String, answered: InteractiveAnswered?, canAnswer: Bool,
        isAnswerable: Bool = true, sendAnswer: @escaping @MainActor @Sendable (String) -> Void
    ) -> MarkdownFencedBlocks? {
        guard let fence else { return nil }
        let language = drawnLanguage(fence.kind)
        let send: @MainActor @Sendable (String) -> Void
        if isAnswerable { send = sendAnswer } else { send = { @MainActor @Sendable _ in } }
        return MarkdownFencedBlocks(languages: [language]) { drawn, code in
            guard drawn == language, fence.matches(code: code) else { return nil }
            return AnyView(
                InteractiveBlockView(
                    fence: fence, runId: runId, answered: answered, canAnswer: canAnswer && isAnswerable,
                    isAnswerable: isAnswerable, sendAnswer: send))
        }
    }
}

/// A reply's block, drawn by its kind.
struct InteractiveBlockView: View {
    let fence: InteractiveFence
    let runId: String
    let answered: InteractiveAnswered?
    /// Whether an answer may be sent now (not while a turn is in flight).
    let canAnswer: Bool
    /// Whether the block may be answered at all (not in a compared answer): when not, it is drawn but held still.
    var isAnswerable = true
    let sendAnswer: @MainActor @Sendable (String) -> Void

    var body: some View {
        switch fence.block {
        case .ask(let block):
            QuestionnaireBlockView(
                block: block, runId: runId, answered: answered, canAnswer: canAnswer, isAnswerable: isAnswerable,
                sendAnswer: sendAnswer)
        case .confirm(let block):
            ConfirmationBlockView(
                block: block, runId: runId, answered: answered, canAnswer: canAnswer, isAnswerable: isAnswerable,
                sendAnswer: sendAnswer)
        }
    }
}

/// One choice of a question: a 44 pt row in the tone's accent — a radio for one answer, a checkbox for several.
struct InteractiveOptionRow: View {
    let title: String
    let isMulti: Bool
    let isOn: Bool
    let isEnabled: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol)
                    .imageScale(.large)
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                isOn ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.fill.quaternary), in: CardStyle.innerShape)
            .contentShape(CardStyle.innerShape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
    }

    private var symbol: String {
        switch (isMulti, isOn) {
        case (true, true): "checkmark.square.fill"
        case (true, false): "square"
        case (false, true): "largecircle.fill.circle"
        case (false, false): "circle"
        }
    }
}

/// The closing free-text field of a block: the model's label, or "Anything else?".
struct InteractiveNoteField: View {
    let label: String?
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            TextField(text: $text, prompt: Text("ios:chat.block.notePlaceholder"), axis: .vertical) { title }
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(.fill.tertiary, in: CardStyle.innerShape)
        }
    }

    @ViewBuilder
    private var title: some View {
        if let label, !label.isEmpty {
            Text(verbatim: label)
        } else {
            Text("ios:chat.block.noteDefault")
        }
    }
}

/// "Answered", under a frozen block.
struct InteractiveAnsweredLine: View {
    var body: some View {
        Label {
            Text("ios:chat.block.answered")
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
