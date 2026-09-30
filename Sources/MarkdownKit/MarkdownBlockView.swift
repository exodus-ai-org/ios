import SwiftUI

struct MarkdownBlockView: View, Equatable {
    let block: MarkdownBlock
    let citations: [Int: MarkdownCitation]
    let context: MarkdownRenderContext

    var body: some View {
        switch block.kind {
        case .paragraph(let content):
            MarkdownInlineText(content: content, spec: .body, citations: citations, isArriving: context.isArriving)
        case .heading(let level, let content):
            MarkdownInlineText(
                content: content, spec: MarkdownLayoutRules.headingFont(level: level), citations: citations,
                isArriving: context.isArriving, isSecondary: level >= 6
            )
            .accessibilityAddTraits(.isHeader)
            .accessibilityHeading(Self.headingLevel(level))
        case .list(let list):
            MarkdownListView(
                list: list, citations: citations, depth: context.listDepth, isArriving: context.isArriving)
        case .blockquote(let blocks):
            MarkdownQuoteView(blocks: blocks, citations: citations, context: context)
        case .codeBlock(let language, let code):
            MarkdownCodeBlockView(language: language, code: code)
        case .table(let table):
            MarkdownTableView(table: table, citations: citations, isArriving: context.isArriving)
        case .thematicBreak:
            Divider()
        case .image(let image):
            MarkdownImageView(image: image)
        case .html(let html):
            if context.isArriving {
                Text(verbatim: html)
                    .font(MarkdownFontSpec.body.font)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SelectableBodyText(html, lineSpacing: 0, isSecondary: true)
            }
        }
    }

    private static func headingLevel(_ level: Int) -> AccessibilityHeadingLevel {
        switch level {
        case 1: .h1
        case 2: .h2
        case 3: .h3
        case 4: .h4
        case 5: .h5
        default: .h6
        }
    }
}

struct MarkdownInlineText: View {
    let content: AttributedString
    let spec: MarkdownFontSpec
    let citations: [Int: MarkdownCitation]
    /// Still being written: drawn by `Text`. Settled, it stands in a text view.
    var isArriving = false
    var isSecondary = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.markdownUnderlinesLinks) private var underlinesLinks

    var body: some View {
        // The read is the point: the fonts below are the system's at this text size.
        _ = dynamicTypeSize
        let styled = MarkdownInlineStyler.style(
            content, spec: spec, citations: citations, underlinesLinks: underlinesLinks)
        return text(styled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityActions {
                ForEach(styled.chips, id: \.self) { number in
                    if let citation = citations[number] {
                        let label = citation.chipLabel
                        Button {
                            openURL(MarkdownCitation.citeURL(number))
                        } label: {
                            Text(
                                String(
                                    localized: "ios:chat.markdown.openSource", defaultValue: "Open citation: \(label)",
                                    comment: "VoiceOver action on a citation chip in an answer. %@ is the site or title."))
                        }
                    }
                }
            }
    }
}

extension MarkdownInlineText {
    @ViewBuilder
    fileprivate func text(_ styled: MarkdownInlineStyler.Output) -> some View {
        if isArriving {
            MarkdownStyledText(styled: styled, spec: spec)
                .lineSpacing(spec.pointSize * MarkdownLayoutRules.lineGap(for: spec))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isSecondary ? .secondary : .primary)
        } else {
            MarkdownSelectableText(styled: styled, spec: spec, isSecondary: isSecondary)
        }
    }
}

struct MarkdownListView: View {
    let list: MarkdownList
    let citations: [Int: MarkdownCitation]
    let depth: Int
    var isArriving = false

    @ScaledMetric(relativeTo: .body) private var em: CGFloat = MarkdownFontSpec.bodySize

    var body: some View {
        let widest = MarkdownLayoutRules.widestMarker(list, depth: depth)
        VStack(alignment: .leading, spacing: em * MarkdownLayoutRules.listGap) {
            ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: em * 0.4) {
                    marker(for: item, number: list.startIndex + index, widest: widest)
                    MarkdownBlockStack(
                        blocks: item.blocks, citations: citations,
                        context: MarkdownRenderContext(listDepth: depth + 1, inList: true, isArriving: isArriving))
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, number: Int, widest: String) -> some View {
        switch item.checkbox {
        case .checked:
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(.tint)
                .accessibilityLabel("ios:chat.markdown.taskChecked")
        case .unchecked:
            Image(systemName: "square")
                .foregroundStyle(.secondary)
                .accessibilityLabel("ios:chat.markdown.taskUnchecked")
        case nil:
            ZStack(alignment: .trailing) {
                Text(verbatim: widest).hidden()
                Text(verbatim: MarkdownLayoutRules.listMarker(isOrdered: list.isOrdered, number: number, depth: depth))
                    .foregroundStyle(.secondary)
            }
            .font(list.isOrdered ? MarkdownFontSpec.body.font.monospacedDigit() : MarkdownFontSpec.body.font.weight(.semibold))
            .accessibilityHidden(!list.isOrdered)
        }
    }
}

struct MarkdownQuoteView: View {
    let blocks: [MarkdownBlock]
    let citations: [Int: MarkdownCitation]
    let context: MarkdownRenderContext

    @ScaledMetric(relativeTo: .body) private var em: CGFloat = MarkdownFontSpec.bodySize

    var body: some View {
        HStack(alignment: .top, spacing: em * 0.75) {
            Capsule()
                .fill(.tint.opacity(0.55))
                .frame(width: 3)
                .padding(.vertical, 2)
            MarkdownBlockStack(blocks: blocks, citations: citations, context: context)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
