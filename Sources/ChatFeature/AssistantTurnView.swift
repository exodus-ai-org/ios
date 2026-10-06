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
    /// Whether a compared answer may be picked now (not while a turn is in flight).
    var canChoose = false
    /// Keeps one answer of a comparison (its run id).
    var choose: (_ runId: String) -> Void = { _ in }
    /// Opens a folded answer (its run id) read-only.
    var showOtherVersion: (_ runId: String) -> Void = { _ in }

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
    /// The transcript as a whole, for scrolling to its end.
    static let endID = "transcript"
    /// Between the last row and the composer, once scrolled to the end.
    static let endRoom: CGFloat = 56

    var body: some View {
        let liveErrorTurnId = TranscriptRules.liveErrorTurnId(segments: segments, live: liveError)
        ForEach(segments) { segment in
            Group {
                switch segment {
                case .user(let message):
                    UserBubble(text: message.answerText, messageId: message.id, images: UserImages.dataURLs(of: message))
                case .assistantTurn(let turn):
                    let isStreaming = turn.id == streamingTurnId
                    let canRegenerate = turn.id == actions.regenerableTurnId
                    let error = TranscriptRules.runError(for: turn, live: turn.id == liveErrorTurnId ? liveError : nil)
                    let bar = TurnActions.bar(for: turn, isStreaming: isStreaming, canRegenerate: canRegenerate)
                    AssistantTurnView(
                        turn: turn, isStreaming: isStreaming, error: error, actionBar: bar,
                        offersRetry: TurnActions.showsRetryOnError(
                            hasError: error != nil, bar: bar, canRegenerate: canRegenerate),
                        canChoose: actions.canChoose,
                        regenerate: actions.regenerate, showSources: actions.showSources, choose: actions.choose,
                        showOtherVersion: actions.showOtherVersion
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
    /// Only a compared answer's Use this one reads it.
    nonisolated var canChoose = false
    var regenerate: () -> Void = {}
    var showSources: (_ turnId: String, _ marker: Int?) -> Void = { _, _ in }
    var choose: (_ runId: String) -> Void = { _ in }
    var showOtherVersion: (_ runId: String) -> Void = { _ in }
    @Environment(\.searchMediaLoader) private var searchMediaLoader

    nonisolated static func == (lhs: AssistantTurnView, rhs: AssistantTurnView) -> Bool {
        lhs.turn == rhs.turn && lhs.isStreaming == rhs.isStreaming && lhs.error == rhs.error
            && lhs.actionBar == rhs.actionBar && lhs.offersRetry == rhs.offersRetry
            && lhs.choiceEnabled == rhs.choiceEnabled
    }

    /// `canChoose` counts only for a compared answer, so an ordinary turn does not redraw when a turn starts or ends.
    nonisolated var choiceEnabled: Bool {
        if case .comparing? = turn.attempt { canChoose } else { false }
    }

    /// What a citation chip does: open the Sources sheet for this turn at the chip's source.
    static func citationTap(
        turnId: String, showSources: @escaping (_ turnId: String, _ marker: Int?) -> Void
    ) -> (Int) -> Void {
        { marker in showSources(turnId, marker) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: TurnFootMetrics.blockGap) {
                if case .comparing(let position)? = turn.attempt {
                    CompareHeader(position: position, canChoose: choiceEnabled && !isStreaming) { choose(turn.runId) }
                }
                if TranscriptRules.showsTimeline(turn, isStreaming: isStreaming) {
                    ThinkingTimeline(turn: turn, isLive: TranscriptRules.timelineIsLive(turn, isStreaming: isStreaming)) {
                        showSources(turn.id, nil)
                    }
                }
                answer
                if TranscriptRules.showsSearchMedia(turn, error: error) {
                    RunFootView(foot: turn.foot, section: .media)
                }
                if let error {
                    RunErrorLine(text: error, onRetry: offersRetry ? regenerate : nil)
                }
            }
            // The foot is set close under the answer: what is drawn is a line or two of small print and a row of
            // glyphs, and each keeps a full touch target by reaching into the gaps around it (`TurnFootMetrics`).
            ForEach(TurnFoot.rows(for: turn, bar: actionBar), id: \.self) { row in
                switch row {
                case .approvals:
                    // A call waiting for an answer, then how it ended. Read from the store, not from this view's
                    // inputs, as the memory rows are.
                    RunApprovalsView(runId: turn.runId, runIsActive: isStreaming)
                case .usedMemories:
                    RunFootView(foot: turn.foot, section: .usedMemories, runId: turn.runId, isStreaming: isStreaming)
                case .memoryChanges:
                    RunFootView(foot: turn.foot, section: .memoryChanges, runId: turn.runId, isStreaming: isStreaming)
                case .actionBar:
                    if let actionBar {
                        TurnActionBarView(bar: actionBar, onRegenerate: regenerate) { showSources(turn.id, nil) }
                            .equatable()
                            .padding(.top, TurnFootMetrics.barTop)
                            // Over the rows around it, so where the targets meet the bar's buttons are the ones
                            // pressed.
                            .zIndex(1)
                    }
                case .otherVersions:
                    if case .chosen(let others, _)? = turn.attempt, let other = others.last {
                        OtherVersionLink(count: others.count) { showOtherVersion(other) }
                            .padding(.top, TurnFootMetrics.afterBar)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Citation chips draw their sites' icons through the loader the search images use.
        .environment(\.markdownCitationIcons, .searchMedia(searchMediaLoader))
    }
}

/// What stands under an answer, top to bottom. The action row closes the turn: what the run asked for, read and
/// changed is said over it, so the row a thumb reaches for is always the last thing of a turn.
enum TurnFootRow: Hashable {
    /// Calls waiting for an answer, and how the settled ones ended.
    case approvals
    /// "Used N memories".
    case usedMemories
    /// What `update_memory` changed.
    case memoryChanges
    case actionBar
    /// "N other versions", under a chosen answer.
    case otherVersions
}

enum TurnFoot {
    /// The rows of a turn's foot in order. Approvals and the memories a run read are known to their stores, not to
    /// the turn: they are always named, and draw nothing when there is nothing to say.
    /// "N other versions" under a chosen answer. Hidden for now (owner, 2026-09-30); the regenerate groups, the
    /// choice and the other-version sheet all still work — this only decides whether the link is drawn.
    static let showsOtherVersions = false

    static func rows(
        for turn: AssistantTurn, bar: TurnActionBar?, showsOtherVersions: Bool = TurnFoot.showsOtherVersions
    ) -> [TurnFootRow] {
        var rows: [TurnFootRow] = [.approvals, .usedMemories]
        if RunMemoryChanges(turn.foot.memoryUpdates) != nil { rows.append(.memoryChanges) }
        if bar != nil { rows.append(.actionBar) }
        if showsOtherVersions, case .chosen(let others, _)? = turn.attempt, !others.isEmpty {
            rows.append(.otherVersions)
        }
        return rows
    }
}

/// The distances of a turn's foot, between the frames of what is drawn. A row's frame is its glyphs or its line of
/// text and no more; its touch target is that frame and `reach` beyond it, above and below. Measured between the ink
/// of one thing and the ink of the next, they come to 7–9 pt: a line of small print, a row of glyphs, close under
/// the answer they belong to.
enum TurnFootMetrics {
    /// Between the blocks of a turn: the answer's parts, a card, a strip.
    static let blockGap: CGFloat = 12
    /// Over the action row, whatever stands over it: the answer's last line or a row of the foot.
    static let barTop: CGFloat = 12
    /// Over a row of small print — a settled approval, the used-memories line.
    static let rowTop: CGFloat = 10
    /// Under such a row: a line of small print has less room under its letters than a line of the answer has, and
    /// what follows stands the same distance under either.
    static let rowBottom: CGFloat = 2
    /// Under a card of the foot (an approval that waits, the memory strip), so the row after it keeps a block's
    /// distance.
    static let cardBottom: CGFloat = 9
    /// Over the row that follows the action row (the other-version link).
    static let afterBar: CGFloat = 10
    /// How far a text row's target reaches beyond its line: 18 pt of footnote and 13 either side are 44.
    static let reach: CGFloat = 13
}

extension View {
    /// A touch target that reaches `TurnFootMetrics.reach` above and below the view without taking the room.
    func footRowTarget() -> some View {
        padding(.vertical, TurnFootMetrics.reach)
            .contentShape(.rect)
            .padding(.vertical, -TurnFootMetrics.reach)
    }
}

extension AssistantTurnView {
    /// The answer in the run's own order, as on the desktop: text, the card of a tool where the model called it,
    /// text (a command's or a file's card opens from its step in the timeline instead). Every text block reads the
    /// turn's one list of citations, and only the last block can be the one that streams.
    @ViewBuilder
    fileprivate var answer: some View {
        let blocks = TranscriptRules.blocks(turn, isStreaming: isStreaming)
        let citations = TranscriptRules.markdownCitations(turn)
        let streaming = TranscriptRules.streamingBlockId(blocks, isStreaming: isStreaming)
        ForEach(blocks) { block in
            switch block {
            case .text(let text):
                // A long press on the answer's text selects a word of it, as in any text; the whole answer is
                // the action row's Copy.
                MarkdownView(
                    text: text.text, citations: citations, isStreaming: text.id == streaming,
                    onCitationTap: Self.citationTap(turnId: turn.id, showSources: showSources)
                )
            case .card(let card):
                ToolCardView(card: card)
            }
        }
        .environment(\.editDiffsStartOpen, FileCardRules.editsStartOpen(editCount: FileCardRules.editCount(in: turn)))
        .environment(\.toolCardsAreLive, isStreaming)
    }
}

struct UserBubble: View {
    let text: String
    var messageId = ""
    /// The pictures the question was asked with, drawn above the bubble.
    var images: [String] = []
    @Environment(\.colorTone) private var tone

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !images.isEmpty {
                UserImageStrip(messageId: messageId, dataURLs: images)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            // A picture sent alone has no empty bubble under it.
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                bubble
            }
        }
    }

    private var bubble: some View {
        HStack {
            Spacer(minLength: 40)
            // A message asked about a selection opens with it as a quote (`QuotedText`): drawn as one, small and
            // beside a rule, over the question. A word of either can be selected, as in an answer. One asked from Health
            // opens with the day's numbers before that (`HealthContext`): a card of chips.
            let health = HealthContext.split(text)
            let parts = QuotedText.split(health.body)
            VStack(alignment: .leading, spacing: 6) {
                if let json = health.json {
                    HealthContextCard(json: json)
                }
                if let quote = parts.quote {
                    Text(verbatim: quote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Capsule().fill(.tint.opacity(0.5)).frame(width: 2)
                        }
                        .accessibilityLabel(Text("ios:chat.ask.quoted"))
                        .accessibilityValue(Text(verbatim: quote))
                }
                if !parts.body.isEmpty {
                    SelectableBodyText(parts.body, lineSpacing: MarkdownTypography.bodyLineSpacing * 0.6)
                }
            }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                // A grey with the tone in it, the desktop's bubble: not the accent thinned to a pastel.
                .background(tone.surfaceColor, in: CardStyle.shape)
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
