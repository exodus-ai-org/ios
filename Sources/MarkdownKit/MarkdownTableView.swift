import SwiftUI
import UIKit

struct MarkdownTableView: View {
    let table: MarkdownTable
    let citations: [Int: MarkdownCitation]

    @ScaledMetric(relativeTo: .subheadline) private var maxCellWidth: CGFloat = 260

    private var columnCount: Int {
        max(table.header.count, table.rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        cell(table.header[safe: column], column: column, isHeader: true)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            cell(row[safe: column], column: column, isHeader: false)
                        }
                    }
                }
            }
            .fixedSize()
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
            }
            .clipShape(.rect(cornerRadius: 8))
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .markdownTrailingFade()
    }

    private func cell(_ content: AttributedString?, column: Int, isHeader: Bool) -> some View {
        let alignment = table.alignments[safe: column] ?? nil
        let styled = MarkdownInlineStyler.style(
            content ?? AttributedString(),
            spec: MarkdownFontSpec(style: .subheadline, weight: isHeader ? .semibold : nil),
            citations: citations)
        return MarkdownWidthCap(maxWidth: maxCellWidth) {
            Text(styled.text)
                .multilineTextAlignment(Self.textAlignment(alignment))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.frameAlignment(alignment))
        .background(isHeader ? Color(uiColor: .secondarySystemBackground) : .clear)
        .gridColumnAlignment(Self.horizontalAlignment(alignment))
    }

    private static func textAlignment(_ alignment: MarkdownTable.Alignment?) -> TextAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    private static func horizontalAlignment(_ alignment: MarkdownTable.Alignment?) -> HorizontalAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    private static func frameAlignment(_ alignment: MarkdownTable.Alignment?) -> Alignment {
        switch alignment {
        case .center: .top
        case .trailing: .topTrailing
        default: .topLeading
        }
    }
}

/// A cell's width is its natural width capped at `maxWidth`, whatever the grid proposes: inside the
/// horizontal scroll view a cell must wrap at the cap, never be squeezed to fit the screen.
struct MarkdownWidthCap: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = min(subview.sizeThatFits(.unspecified).width, maxWidth)
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
