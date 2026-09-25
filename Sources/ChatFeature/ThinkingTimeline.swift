import MarkdownKit
import SwiftUI

extension EnvironmentValues {
    @Entry var timelineStartsExpanded = false
}

struct ThinkingTimeline: View {
    let turn: AssistantTurn
    let isLive: Bool
    @State private var isExpanded: Bool?
    @Environment(\.timelineStartsExpanded) private var startsExpanded
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { isExpanded ?? startsExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { isExpanded = !expanded }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? Text("ios:chat.message.timeline.expanded") : Text("ios:chat.message.timeline.collapsed"))
            if expanded {
                steps.transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if isLive {
                ProgressView().controlSize(.small)
            } else if ToolPresentation.hasFailedTool(turn) {
                Image(systemName: "xmark.circle")
                    .imageScale(.small)
                    .foregroundStyle(.red)
            } else {
                Image(systemName: turn.hasThinking ? "brain" : "checkmark")  // l10n:ignore: SF Symbol names
                    .imageScale(.small)
            }
            Text(verbatim: ToolPresentation.headerText(ToolPresentation.header(for: turn, isLive: isLive)))
                .fontWeight(.medium)
                .lineLimit(1)
                .contentTransition(.opacity)
            Image(systemName: "chevron.down")
                .imageScale(.small)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .contentShape(.rect)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(turn.steps.enumerated()), id: \.offset) { index, step in
                TimelineStepRow(
                    step: step, isActive: isLive && index == turn.steps.count - 1,
                    isLast: index == turn.steps.count - 1 && isLive)
            }
            if !isLive {
                TimelineNode(isLast: true) {
                    Image(systemName: "checkmark.circle")
                } content: {
                    Text("ios:chat.message.timeline.done")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TimelineStepRow: View {
    let step: AssistantTurn.Step
    let isActive: Bool
    let isLast: Bool

    var body: some View {
        TimelineNode(isLast: isLast) {
            icon
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                switch step {
                case .thinking(let thinking):
                    Text(Self.inlineMarkdown(thinking.text))
                        .font(.subheadline)
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .textSelection(.enabled)
                case .toolCall(let call):
                    toolCall(call)
                }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch step {
        case .thinking:
            Image(systemName: "brain")
        case .toolCall(let call) where call.isPending:
            ProgressView().controlSize(.mini)
        case .toolCall(let call) where call.isError:
            Image(systemName: "xmark.circle").foregroundStyle(.red)
        case .toolCall(let call):
            Image(systemName: ToolPresentation.systemImage(for: call.name))
        }
    }

    @ViewBuilder
    private func toolCall(_ call: AssistantTurn.ToolCallStep) -> some View {
        Text(verbatim: ToolPresentation.callText(call))
            .font(.subheadline)
            .foregroundStyle(isActive ? .primary : .secondary)
            .textSelection(.enabled)
        if let code = call.codeArgument {
            Text(verbatim: code)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(12)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
        }
        if call.isError {
            Text(verbatim: call.errorText ?? ToolPresentation.failedText(call.name))
                .font(.subheadline)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
        if !call.results.isEmpty {
            Text(verbatim: ToolPresentation.resultCountText(call.resultCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(Array(call.results.enumerated()), id: \.offset) { _, result in
                    SourcePill(source: result)
                }
            }
        }
    }

    /// Inline emphasis only, every newline kept: a reasoning step is prose, and its `**title**` should read bold.
    static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct SourcePill: View {
    let source: CitationSource
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            // The Sources sheet's allowlist, so a pill and the sheet open exactly the same links.
            if let url = ExternalLinkPolicy.openableURL(source.link) { openURL(url) }
        } label: {
            Text(verbatim: ToolPresentation.host(of: source) ?? source.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text(verbatim: source.title.isEmpty ? source.link : source.title))
    }
}

/// An icon on a vertical rail: the rail joins it to the next step.
private struct TimelineNode<Icon: View, Content: View>: View {
    let isLast: Bool
    @ViewBuilder let icon: Icon
    @ViewBuilder let content: Content
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                icon
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: iconWidth, height: iconWidth)
                if !isLast {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, isLast ? 0 : 12)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Wraps its children onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
