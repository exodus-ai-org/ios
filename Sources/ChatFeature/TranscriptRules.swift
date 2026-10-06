import Foundation
import MarkdownKit
import Models

/// A stream failure reported live for the run in flight, before (or instead of) any row that carries it.
public struct LiveRunError: Equatable, Sendable {
    public let runId: String
    public let message: String

    public init(runId: String, message: String) {
        self.runId = runId
        self.message = message
    }
}

/// What the transcript shows, decided from segments and the turn's state; the views only read these.
enum TranscriptRules {
    /// The desktop's `isLoading && isLastSegment`: only the last turn streams, and only while a turn is in flight.
    static func streamingTurnId(segments: [Segment], isTurnInFlight: Bool) -> String? {
        guard isTurnInFlight, case .assistantTurn(let turn)? = segments.last else { return nil }
        return turn.id
    }

    /// The three dots. Before any assistant activity (the desktop's rule), and again when an answered turn's timeline is
    /// settled but the run goes on: after a tool result, or while the newest assistant message has no text yet.
    static func showsTypingIndicator(segments: [Segment], lastMessage: ChatMessage?, isTurnInFlight: Bool) -> Bool {
        guard isTurnInFlight else { return false }
        guard case .assistantTurn(let turn)? = segments.last else { return true }
        guard turn.hasBody, turn.pendingToolCalls.isEmpty else { return false }
        guard let lastMessage, lastMessage.role == "assistant" else { return true }
        return !lastMessage.contentBlocks.contains {
            if case .text(let text) = $0 { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } else { false }
        }
    }

    /// The header follows the latest step until the answer starts, as on the desktop, and again while a tool runs.
    static func timelineIsLive(_ turn: AssistantTurn, isStreaming: Bool) -> Bool {
        isStreaming && (!turn.hasBody || !turn.pendingToolCalls.isEmpty)
    }

    static func showsTimeline(_ turn: AssistantTurn, isStreaming: Bool) -> Bool {
        !turn.steps.isEmpty || timelineIsLive(turn, isStreaming: isStreaming)
    }

    /// The tools whose cards open from their step in the timeline instead of standing in the answer: the model's own
    /// working — a command, a file read or written — which the timeline already lists, one step each.
    static let foldedTools: Set<String> = ["terminal", "read_file", "write_file", "edit_file"]

    /// What a turn draws, in the order the model produced it. An image still forming is shown only while its run
    /// streams: in a stopped run it never will, so it shows nothing, as on the desktop — and the text it stood
    /// between is one block again. (A stopped computer_use keeps its card, reading "stopped".) The cards of
    /// `foldedTools` are left out the same way: they are in the timeline, under their steps (`foldedCard`).
    static func blocks(_ turn: AssistantTurn, isStreaming: Bool) -> [AssistantTurn.Block] {
        func dropped(_ block: AssistantTurn.Block) -> Bool {
            guard case .card(let card) = block else { return false }
            return foldedTools.contains(card.toolName) || (!isStreaming && neverComes(card))
        }
        guard turn.blocks.contains(where: dropped) else { return turn.blocks }
        return AssistantTurn.Block.numbered(turn.blocks.filter { !dropped($0) })
    }

    /// The cards among `blocks`.
    static func toolCards(_ turn: AssistantTurn, isStreaming: Bool) -> [ToolCard] {
        blocks(turn, isStreaming: isStreaming).compactMap { if case .card(let card) = $0 { card } else { nil } }
    }

    /// The card a timeline step opens to: a folded tool's, found by its call. A call still running has none yet, and
    /// neither has a failed command (its step shows the error).
    static func foldedCard(for call: AssistantTurn.ToolCallStep, in turn: AssistantTurn) -> ToolCard? {
        guard foldedTools.contains(call.name), !call.isPending else { return nil }
        return turn.toolCards.first { $0.toolCallId == call.id }
    }

    private static func neverComes(_ card: ToolCard) -> Bool {
        card.isPending && card.toolName == "image_generation"
    }

    /// The block that grows while the run streams: the last one, when it is text. Text above a card is finished.
    static func streamingBlockId(_ blocks: [AssistantTurn.Block], isStreaming: Bool) -> String? {
        guard isStreaming, case .text(let text)? = blocks.last else { return nil }
        return text.id
    }

    /// The search media belong to the answer's section, as on the desktop: a run with no answer and no error shows none.
    static func showsSearchMedia(_ turn: AssistantTurn, error: String?) -> Bool {
        turn.hasBody || error != nil
    }

    /// Changes whenever the bottom of the transcript grows, so the view can follow it.
    static func scrollKey(segments: [Segment], showsTypingIndicator: Bool, liveError: LiveRunError?) -> ScrollKey {
        var key = ScrollKey(segmentId: segments.last?.id, showsTypingIndicator: showsTypingIndicator)
        key.hasLiveError = liveError != nil
        if case .assistantTurn(let turn)? = segments.last {
            key.bodyLength = turn.body.utf8.count
            key.stepCount = turn.steps.count
            key.settledStepCount = turn.steps.count - turn.pendingToolCalls.count
            key.cardCount = turn.toolCards.count
            if case .thinking(let thinking)? = turn.steps.last { key.lastStepLength = thinking.text.utf8.count }
            key.hasError = turn.error != nil
        }
        return key
    }

    struct ScrollKey: Equatable {
        var segmentId: String?
        var showsTypingIndicator: Bool
        var bodyLength = 0
        var stepCount = 0
        var settledStepCount = 0
        var cardCount = 0
        var lastStepLength = 0
        var hasError = false
        var hasLiveError = false
    }

    /// One error per run: the live failure while this client saw it happen, else the one the rows carry.
    static func runError(for turn: AssistantTurn, live: LiveRunError?) -> String? {
        if let live, live.runId == turn.runId { return errorText(live.message) }
        return turn.error.map(errorText)
    }

    /// A run split by another run's rows is several turns; its live error belongs on the last of them only.
    static func liveErrorTurnId(segments: [Segment], live: LiveRunError?) -> String? {
        guard let live else { return nil }
        for segment in segments.reversed() {
            if case .assistantTurn(let turn) = segment, turn.runId == live.runId { return turn.id }
        }
        return nil
    }

    /// A live failure whose run has no turn yet (it failed before any step) shows under the prompt instead.
    static func orphanRunError(segments: [Segment], live: LiveRunError?) -> String? {
        guard let live else { return nil }
        let hasTurn = segments.contains { if case .assistantTurn(let turn) = $0 { turn.runId == live.runId } else { false } }
        return hasTurn ? nil : errorText(live.message)
    }

    static func errorText(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(
                localized: "ios:chat.message.error.generic", defaultValue: "The response failed.",
                comment: "Foot of a reply whose run ended in an error that carried no message.")
        }
        return String(
            localized: "chat:run.error", defaultValue: "This reply stopped with an error: \(trimmed)",
            comment: "Foot of a reply whose run ended in an error. %@ is the provider's error message.")
    }

    /// Citation chips for a turn: the desktop's rank map, where a later source with the same rank wins.
    static func markdownCitations(_ turn: AssistantTurn) -> [MarkdownCitation] {
        var byRank: [Int: CitationSource] = [:]
        var order: [Int] = []
        for source in turn.citations {
            if byRank[source.rank] == nil { order.append(source.rank) }
            byRank[source.rank] = source
        }
        return order.compactMap { rank in
            byRank[rank].map {
                MarkdownCitation(
                    number: rank, title: $0.title, host: ToolPresentation.host(of: $0), iconURL: SourceIcon.url(for: $0),
                    iconFallbackURL: SourceIcon.fallback(for: $0))
            }
        }
    }
}
