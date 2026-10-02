import SwiftUI
import UIKit

/// The shape of a block that is set apart from the text around it — code, a table, an image's frame: a quiet
/// fill, no edge, the transcript cards' continuous corner a step smaller.
enum MarkdownBlockShape {
    static let radius: CGFloat = 14
    static let inset: CGFloat = 14
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
}

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
            .padding(.horizontal, MarkdownBlockShape.inset)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView(.horizontal) {
                // 0.875 em, as code sits beside body text on GitHub and the web: monospaced at body size reads large.
                Text(verbatim: code)
                    .font(.system(size: MarkdownFontSpec(style: .subheadline).pointSize, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, MarkdownBlockShape.inset)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .markdownTrailingFade()
        }
        .background(Color(uiColor: .secondarySystemBackground), in: MarkdownBlockShape.shape)
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
