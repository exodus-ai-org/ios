import MarkdownKit
import SwiftUI

/// What the user's bubble draws its message as, and when a long one is cut short.
enum UserBubbleRules {
    /// How many lines of body text a message shows before it is cut short, as on the desktop.
    static let collapsedLines: CGFloat = 10
    /// How far past the cap a message may run and still be shown whole: a tap that shows one more line is not
    /// worth a button.
    static let slackLines: CGFloat = 2

    /// The height a long message is cut to: `collapsedLines` lines and the room between them.
    static func cap(lineHeight: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        collapsedLines * lineHeight + (collapsedLines - 1) * lineSpacing
    }

    /// Whether a message measured at `height` is cut short at `cap`. One opened with Show more stays open.
    static func isClipped(height: CGFloat, cap: CGFloat, lineHeight: CGFloat, isExpanded: Bool) -> Bool {
        !isExpanded && height > cap + slackLines * lineHeight
    }

    /// The message as Markdown that keeps its line breaks: a person's single newline is a new line, not the soft
    /// break Markdown makes a space of. Two trailing spaces make it a hard break; a fenced block keeps its lines.
    static func markdown(_ text: String) -> String {
        var fence: String?
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                continue
            }
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            if !trimmed.isEmpty, !next.trimmingCharacters(in: .whitespaces).isEmpty {
                lines[index] += "  "
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A message of paragraphs only hugs its longest line, as the plain bubble did; one with a heading, a list,
    /// code or a table is as wide as the bubble may be.
    static func isProse(_ markdown: String) -> Bool {
        MarkdownParser.parse(markdown).allSatisfy {
            if case .paragraph = $0.kind { true } else { false }
        }
    }
}

/// Lays its second subview out as wide as its first, a hidden probe, wants to be at the offered width: the text
/// view Markdown is drawn in fills what it is offered, and a bubble of prose should hug its longest line instead.
struct HugWidthLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(for: proposal, subviews: subviews)
        let height = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: 0))
        subviews[1].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }

    private func width(for proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        let probe = subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).width
        // A point over the probe: the text view must not break a line the probe kept whole.
        let wanted = ceil(probe) + 1
        guard let offered = proposal.width, offered.isFinite else { return wanted }
        return min(offered, wanted)
    }
}
