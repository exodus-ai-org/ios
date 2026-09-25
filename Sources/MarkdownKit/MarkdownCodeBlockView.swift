import SwiftUI
import UIKit

struct MarkdownCodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language {
                    Text(verbatim: language)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: copy) {
                    if copied {
                        Label("ios:chat.markdown.codeCopied", systemImage: "checkmark")
                    } else {
                        Label("ios:chat.markdown.copyCode", systemImage: "doc.on.doc")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
                .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollView(.horizontal) {
                Text(verbatim: code)
                    .font(.callout.monospaced())
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .markdownTrailingFade()
        }
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        }
    }

    private func copy() {
        UIPasteboard.general.string = code
        copied = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
