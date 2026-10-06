import SwiftUI

/// Fenced blocks a host draws itself — a chat answer's questionnaire, say — instead of as code. MarkdownKit knows
/// nothing of them: a code block whose language the host names is offered to `draw`, and `nil` draws it as code.
public struct MarkdownFencedBlocks: Sendable {
    public let languages: Set<String>
    private let draw: @MainActor @Sendable (_ language: String, _ code: String) -> AnyView?

    public init(languages: Set<String>, draw: @escaping @MainActor @Sendable (String, String) -> AnyView?) {
        self.languages = languages
        self.draw = draw
    }

    @MainActor
    public func view(language: String?, code: String) -> AnyView? {
        guard let language, languages.contains(language) else { return nil }
        return draw(language, code)
    }
}

extension EnvironmentValues {
    /// Set by a host around the Markdown whose fenced blocks it draws; read only by code blocks.
    @Entry public var markdownFencedBlocks: MarkdownFencedBlocks?
}

/// A code block, or what the host draws for it. Its own view, so only code blocks read the host's hook.
struct MarkdownFencedCode: View {
    let language: String?
    let code: String
    @Environment(\.markdownFencedBlocks) private var fenced

    var body: some View {
        if let drawn = fenced?.view(language: language, code: code) {
            drawn
        } else {
            MarkdownCodeBlockView(language: language, code: code)
        }
    }
}
