import SwiftUI

/// Renders an assistant answer's markdown. One `MarkdownStreamModel` per view instance: while
/// `isStreaming`, each new `text` re-parses only the changed tail and every settled block keeps its
/// identity, so its memoised view is not re-evaluated.
///
/// `citations` resolves `【N-source】` markers to chips (tapping one calls `onCitationTap(N)`); a marker
/// whose number is not in it is stripped, like the desktop does. Only http(s) and mailto links open, through the
/// parent's `openURL`; any other scheme in model-written text is dropped (`MarkdownLinkPolicy`).
public struct MarkdownView: View {
    private let text: String
    private let citations: [MarkdownCitation]
    private let isStreaming: Bool
    private let onCitationTap: ((Int) -> Void)?

    @State private var model = MarkdownStreamModel()
    @State private var router = MarkdownLinkRouter()
    @Environment(\.openURL) private var openURL
    @Environment(\.renderDiagnostics) private var diagnostics

    public init(
        text: String, citations: [MarkdownCitation] = [], isStreaming: Bool, onCitationTap: ((Int) -> Void)? = nil
    ) {
        self.text = text
        self.citations = citations
        self.isStreaming = isStreaming
        self.onCitationTap = onCitationTap
    }

    public var body: some View {
        // Closures cannot be compared, so the router's handlers are refreshed here; its action stays the same.
        router.onCitationTap = onCitationTap
        router.openURL = { [openURL] in openURL($0) }
        model.diagnostics = diagnostics
        return MarkdownBlockStack(
            blocks: model.blocks(for: text, isStreaming: isStreaming),
            citations: Dictionary(citations.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first }),
            context: MarkdownRenderContext()
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, router.action)
    }
}

struct MarkdownRenderContext: Equatable {
    var listDepth = 0
    var inList = false
}

/// Consecutive blocks with the desktop's rhythm between them. Each block view is `Equatable`, so a
/// streaming frame re-evaluates only the block(s) whose value changed.
struct MarkdownBlockStack: View {
    let blocks: [MarkdownBlock]
    let citations: [Int: MarkdownCitation]
    let context: MarkdownRenderContext

    @ScaledMetric(relativeTo: .body) private var em: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                MarkdownBlockView(block: block, citations: citations, context: context)
                    .equatable()
                    .padding(
                        .top,
                        em * MarkdownLayoutRules.gap(
                            after: index > 0 ? blocks[index - 1].kind : nil, before: block.kind, inList: context.inList)
                    )
            }
        }
    }
}
