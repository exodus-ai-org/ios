import SwiftUI

/// A user message that answers a questionnaire or a confirmation (`InteractiveAnswer`), drawn as what it is: the
/// block's title, then the answers, quieter — not the fence and the bold Markdown it travels as.
struct InteractiveAnswerCard: View {
    struct Line: Equatable {
        let label: String?
        let value: String
    }

    let head: InteractiveAnswer.Head
    let text: String

    /// An answer's lines as the card draws them: the bold lead (a question, "Also:") and what follows it.
    nonisolated static func lines(_ text: String) -> [Line] {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                let afterLead = line.index(line.startIndex, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
                guard line.hasPrefix("**"), let close = line.range(of: "** ", range: afterLead..<line.endIndex) else {
                    return Line(label: nil, value: line)
                }
                return Line(label: String(line[afterLead..<close.lowerBound]), value: String(line[close.upperBound...]))
            }
    }

    nonisolated static func symbol(for head: InteractiveAnswer.Head) -> String {
        switch (head.block, head.decision) {
        case (.ask, _): "checklist"
        case (.confirm, .reject?): "xmark.circle"
        case (.confirm, _): "checkmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                title
            } icon: {
                Image(systemName: Self.symbol(for: head)).foregroundStyle(.tint)
            }
            .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(Self.lines(text).enumerated()), id: \.offset) { _, line in
                    lineText(line).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var title: some View {
        if let title = head.title, !title.isEmpty {
            Text(verbatim: title)
        } else {
            Text("ios:chat.block.answer.title")
        }
    }

    private func lineText(_ line: Line) -> Text {
        guard let label = line.label else { return Text(verbatim: line.value) }
        var lead = AttributedString(label)
        lead.inlinePresentationIntent = .stronglyEmphasized
        return Text(lead + AttributedString(" " + line.value))
    }
}
