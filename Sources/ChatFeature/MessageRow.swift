import Models
import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    /// True for the LAST message while a turn is in flight. An empty assistant bubble is then the
    /// "waiting for the first token" indicator; an assistant message that is empty for any other
    /// reason (a turn that was only tool calls) renders nothing.
    var showsTypingIndicator = false

    /// Inline Markdown only (bold, italic, code, links) with every newline kept. Measured: the
    /// default full-syntax parse collapses paragraphs and list items into one run-on line because
    /// `Text` ignores block structure. No syntax highlighting, Mermaid or math, per the spec.
    private static let markdownOptions = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace)

    private static func renderedText(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: markdownOptions)) ?? AttributedString(text)
    }

    var body: some View {
        switch message.role {
        case "user":
            HStack {
                Spacer(minLength: 40)
                Text(Self.renderedText(message.displayText))
                    .padding(10)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case "assistant":
            if !message.displayText.isEmpty {
                assistantBubble(Self.renderedText(message.displayText))
            } else if showsTypingIndicator {
                assistantBubble(AttributedString("…"))
            }
        case "toolResult":
            HStack(spacing: 6) {
                Image(systemName: message.isError ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(message.isError ? .red : .secondary)
                Text("Used: \(message.toolName ?? "tool")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        default:
            EmptyView()
        }
    }

    private func assistantBubble(_ text: AttributedString) -> some View {
        HStack {
            Text(text)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 40)
        }
    }
}
