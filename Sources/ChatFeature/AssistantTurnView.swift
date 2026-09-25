import MarkdownKit
import Models
import SwiftUI

/// What the rows can ask of their owner: the chat screen answers with its view model, the gallery with stand-ins.
struct TranscriptActions {
    /// The one turn that carries Regenerate.
    var regenerableTurnId: String?
    /// A run that failed before any step: its error line under the prompt offers Regenerate.
    var canRetryOrphan = false
    var regenerate: () -> Void
    /// Opens the Sources sheet for a turn, at the source a tapped citation chip names when there is one.
    var showSources: (_ turnId: String, _ marker: Int?) -> Void

    static var none: TranscriptActions { TranscriptActions(regenerableTurnId: nil, regenerate: {}, showSources: { _, _ in }) }
}

/// The transcript's rows, shared by the chat screen and the DEBUG gallery.
struct TranscriptRows: View {
    let segments: [Segment]
    let streamingTurnId: String?
    let showsTypingIndicator: Bool
    let liveError: LiveRunError?
    var actions: TranscriptActions = .none

    static let typingIndicatorID = "typing"
    static let orphanErrorID = "orphan-error"

    var body: some View {
        let liveErrorTurnId = TranscriptRules.liveErrorTurnId(segments: segments, live: liveError)
        ForEach(segments) { segment in
            Group {
                switch segment {
                case .user(let message):
                    UserBubble(text: message.answerText)
                case .assistantTurn(let turn):
                    let isStreaming = turn.id == streamingTurnId
                    let canRegenerate = turn.id == actions.regenerableTurnId
                    let error = TranscriptRules.runError(for: turn, live: turn.id == liveErrorTurnId ? liveError : nil)
                    let bar = TurnActions.bar(for: turn, isStreaming: isStreaming, canRegenerate: canRegenerate)
                    AssistantTurnView(
                        turn: turn, isStreaming: isStreaming, error: error, actionBar: bar,
                        offersRetry: TurnActions.showsRetryOnError(
                            hasError: error != nil, bar: bar, canRegenerate: canRegenerate),
                        regenerate: actions.regenerate, showSources: actions.showSources
                    )
                    .equatable()
                }
            }
            .id(segment.id)
        }
        if let orphan = TranscriptRules.orphanRunError(segments: segments, live: liveError) {
            RunErrorLine(text: orphan, onRetry: actions.canRetryOrphan ? actions.regenerate : nil)
                .id(Self.orphanErrorID)
        }
        if showsTypingIndicator {
            TypingIndicator().id(Self.typingIndicatorID)
        }
    }
}

/// Equatable on what it draws: the closures never change a turn's look, so a settled turn is not evaluated again while
/// a later reply streams or a notice comes and goes.
struct AssistantTurnView: View, Equatable {
    nonisolated let turn: AssistantTurn
    nonisolated let isStreaming: Bool
    nonisolated let error: String?
    nonisolated var actionBar: TurnActionBar?
    nonisolated var offersRetry = false
    var regenerate: () -> Void = {}
    var showSources: (_ turnId: String, _ marker: Int?) -> Void = { _, _ in }

    nonisolated static func == (lhs: AssistantTurnView, rhs: AssistantTurnView) -> Bool {
        lhs.turn == rhs.turn && lhs.isStreaming == rhs.isStreaming && lhs.error == rhs.error
            && lhs.actionBar == rhs.actionBar && lhs.offersRetry == rhs.offersRetry
    }

    /// What a citation chip does: open the Sources sheet for this turn at the chip's source.
    static func citationTap(
        turnId: String, showSources: @escaping (_ turnId: String, _ marker: Int?) -> Void
    ) -> (Int) -> Void {
        { marker in showSources(turnId, marker) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if TranscriptRules.showsTimeline(turn, isStreaming: isStreaming) {
                ThinkingTimeline(turn: turn, isLive: TranscriptRules.timelineIsLive(turn, isStreaming: isStreaming))
            }
            // Cards sit above the answer, as on the desktop: the answer is what the tools led to.
            ForEach(TranscriptRules.toolCards(turn, isStreaming: isStreaming), id: \.renderKey) { card in
                ToolCardView(card: card)
            }
            .environment(\.editDiffsStartOpen, FileCardRules.editsStartOpen(editCount: FileCardRules.editCount(in: turn)))
            .environment(\.toolCardsAreLive, isStreaming)
            if turn.hasBody {
                MarkdownView(
                    text: turn.body, citations: TranscriptRules.markdownCitations(turn), isStreaming: isStreaming,
                    onCitationTap: Self.citationTap(turnId: turn.id, showSources: showSources))
            }
            if TranscriptRules.showsSearchMedia(turn, error: error) {
                RunFootView(foot: turn.foot, section: .media)
            }
            if let error {
                RunErrorLine(text: error, onRetry: offersRetry ? regenerate : nil)
            }
            if let actionBar {
                TurnActionBarView(bar: actionBar, onRegenerate: regenerate) { showSources(turn.id, nil) }
                    .equatable()
            }
            // The desktop's foot order: a call waiting for an answer, then which memories the run read, then what it
            // changed. The line and the strip read their own run's state from the store, not from this view's inputs.
            RunApprovalsView(runId: turn.runId, runIsActive: isStreaming)
            RunFootView(foot: turn.foot, section: .memory, runId: turn.runId, isStreaming: isStreaming)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(verbatim: text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(.rect(cornerRadius: 16))
        }
    }
}

struct RunErrorLine: View {
    let text: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(verbatim: text).textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.subheadline)
            .foregroundStyle(.red)
            .accessibilityAddTraits(.isStaticText)
            if let onRetry {
                Button(action: onRetry) {
                    // The capsule stays compact; the 44 pt tap target is the invisible frame around it.
                    Label("chat:messageAction.regenerate", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.fill.tertiary, in: .capsule)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Three dots breathing in turn while the reply has not started.
struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.primary.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .opacity(reduceMotion ? 1 : Self.pulse(time, index))
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .accessibilityElement()
        .accessibilityLabel(Text("ios:chat.message.typing"))
    }

    private static func pulse(_ time: TimeInterval, _ index: Int) -> Double {
        let phase = (time / 1.2 - Double(index) / 3).truncatingRemainder(dividingBy: 1)
        return 0.35 + 0.65 * (0.5 + 0.5 * cos(phase * 2 * .pi))
    }
}
