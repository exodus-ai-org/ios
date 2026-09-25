import SwiftUI

/// Draws a document parsed beforehand (`MarkdownParser.parse`, e.g. off the main actor), so a long settled text is
/// never parsed while a view draws. Links, citations and images behave exactly as in `MarkdownView`.
public struct MarkdownDocumentView: View {
    private let parsed: MarkdownParseResult
    private let citations: [MarkdownCitation]
    private let onCitationTap: ((Int) -> Void)?

    @State private var router = MarkdownLinkRouter()
    @State private var reported = false
    @Environment(\.openURL) private var openURL
    @Environment(\.renderDiagnostics) private var diagnostics

    public init(parsed: MarkdownParseResult, citations: [MarkdownCitation] = [], onCitationTap: ((Int) -> Void)? = nil) {
        self.parsed = parsed
        self.citations = citations
        self.onCitationTap = onCitationTap
    }

    public var body: some View {
        router.onCitationTap = onCitationTap
        router.openURL = { [openURL] in openURL($0) }
        return MarkdownBlockStack(
            blocks: parsed.blocks,
            citations: Dictionary(citations.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first }),
            context: MarkdownRenderContext()
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, router.action)
        .onAppear {
            guard !reported else { return }
            reported = true
            for kind in Set(parsed.unhandledKinds).sorted() {
                diagnostics.report("markdown", "Markup rendered as plain text", ["markup": kind])
            }
        }
    }
}
