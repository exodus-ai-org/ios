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
    @Environment(\.markdownDrawsAsArriving) private var drawsAsArriving

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
        let blocks = model.blocks(for: text, isStreaming: isStreaming)
        return MarkdownBlockStack(
            blocks: blocks,
            citations: Dictionary(citations.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first }),
            context: MarkdownRenderContext(isArriving: drawsAsArriving),
            arriving: MarkdownRenderContext.arrivingBlock(of: blocks, isStreaming: isStreaming)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, router.action)
    }
}

extension EnvironmentValues {
    /// Every block is drawn as one still being written, by `Text`: what a settled block's text view is held
    /// against, to see that the text stands where it stood. For a gallery; a chat never sets it.
    @Entry public var markdownDrawsAsArriving = false
    /// What the room between two lines of settled text is multiplied by: a user's message in its bubble sets its
    /// lines closer than an answer's.
    @Entry public var markdownLineSpacingScale: CGFloat = 1
}

struct MarkdownRenderContext: Equatable {
    var listDepth = 0
    var inList = false
    /// The block is still being written: its text is drawn by `Text`, which a frame changes in place. A settled
    /// block's text stands in a text view, where a word of it can be selected — and which a frame must not
    /// make again.
    var isArriving = false

    /// The one block a frame can change: the last, while the text streams.
    static func arrivingBlock(of blocks: [MarkdownBlock], isStreaming: Bool) -> MarkdownBlock.ID? {
        isStreaming ? blocks.last?.id : nil
    }
}

/// Consecutive blocks with the desktop's rhythm between them. Each block view is `Equatable`, so a
/// streaming frame re-evaluates only the block(s) whose value changed — and a run of settled text, only when a
/// block joins it.
struct MarkdownBlockStack: View {
    let blocks: [MarkdownBlock]
    let citations: [Int: MarkdownCitation]
    let context: MarkdownRenderContext
    /// The block of these that is still being written, if one is.
    var arriving: MarkdownBlock.ID?

    @ScaledMetric(relativeTo: .body) private var em: CGFloat = MarkdownFontSpec.bodySize

    var body: some View {
        // Settled text blocks side by side share one text view, so a selection runs across them; not inside a
        // list, whose items stand beside their markers, nor where every block is drawn as still being written.
        let segments =
            context.inList || context.isArriving
            ? blocks.map(MarkdownTextRuns.Segment.block) : MarkdownTextRuns.segments(blocks, arriving: arriving)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                Group {
                    switch segment {
                    case .run(let blocks):
                        MarkdownRunView(blocks: blocks, citations: citations).equatable()
                    case .block(let block):
                        MarkdownBlockView(block: block, citations: citations, context: context(for: block))
                            .equatable()
                    }
                }
                .padding(
                    .top,
                    em * MarkdownLayoutRules.gap(
                        after: index > 0 ? segments[index - 1].lastKind : nil, before: segment.firstKind,
                        inList: context.inList)
                )
            }
        }
    }

    private func context(for block: MarkdownBlock) -> MarkdownRenderContext {
        guard block.id == arriving else { return context }
        var arriving = context
        arriving.isArriving = true
        return arriving
    }
}
