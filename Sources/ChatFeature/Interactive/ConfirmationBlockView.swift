import MarkdownKit
import SwiftUI

/// A reply's confirmation (`exodus-confirm`): what will happen (Markdown), a note, Reject (bordered) and Approve
/// (prominent, the tone's accent) — side by side, one over the other at accessibility sizes. Once the transcript holds
/// the answer it shows the decision instead.
struct ConfirmationBlockView: View {
    let block: InteractiveBlock.Confirm
    let runId: String
    let answered: InteractiveAnswered?
    let mode: InteractiveMode
    /// The note, kept by the transcript while the block is open.
    let drafts: InteractiveDrafts
    let sendAnswer: @MainActor @Sendable (String) -> Bool

    @State private var sent = 0
    @Environment(\.accentGlyph) private var accentGlyph
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: block.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let details = block.details, !details.isEmpty {
                MarkdownView(text: details, isStreaming: false)
                    // Its own fences are code, whatever the reply around it draws.
                    .environment(\.markdownFencedBlocks, nil)
            }
            if let answered {
                decision(answered.head.decision)
            } else if mode.showsActions {
                InteractiveNoteField(
                    label: block.note,
                    text: Binding(get: { drafts[runId].note }, set: { drafts[runId].note = $0 }))
                buttons
            }
        }
        .padding(CardStyle.inset)
        .modifier(CardSurface())
        .animation(reduceMotion ? nil : .smooth, value: answered != nil)
        .sensoryFeedback(.success, trigger: sent)
    }

    private var buttons: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button {
                send(approved: false)
            } label: {
                rejectLabel.frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Button {
                send(approved: true)
            } label: {
                approveLabel.font(.body.weight(.semibold)).foregroundStyle(accentGlyph)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .toneFill()
        }
        .disabled(!mode.canSend)
    }

    @ViewBuilder
    private var approveLabel: some View {
        if let label = block.approve, !label.isEmpty {
            Text(verbatim: label)
        } else {
            Text("ios:chat.block.approve")
        }
    }

    @ViewBuilder
    private var rejectLabel: some View {
        if let label = block.reject, !label.isEmpty {
            Text(verbatim: label)
        } else {
            Text("ios:chat.block.reject")
        }
    }

    @ViewBuilder
    private func decision(_ decision: InteractiveAnswer.Head.Decision?) -> some View {
        switch decision {
        case .approve?:
            Label {
                Text("ios:chat.block.approved")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
        case .reject?:
            Label {
                Text("ios:chat.block.rejected")
            } icon: {
                Image(systemName: "xmark.circle.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        case nil:
            InteractiveAnsweredLine()
        }
    }

    private func send(approved: Bool) {
        guard mode.canSend else { return }
        let text = InteractiveAnswer.composeConfirm(
            block, ref: runId, approved: approved, note: drafts[runId].note, labels: .current)
        // The haptic and the announcement say it was sent, so only when it was.
        guard sendAnswer(text) else { return }
        sent += 1
        AccessibilityNotification.Announcement(InteractiveText.sent).post()
    }
}
