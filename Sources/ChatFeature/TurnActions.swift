import Foundation
import Models

/// What the action bar under a finished answer offers; the view only draws this.
struct TurnActionBar: Equatable {
    /// The turn's markdown source, as the desktop's copy button puts it on the pasteboard.
    let copyText: String
    let showsRegenerate: Bool
    let sourceCount: Int
    let timestampMs: Double?

    var showsSources: Bool { sourceCount > 0 }
}

/// Which actions a turn gets, and which turn may be asked again; decided from the transcript, drawn by the views.
enum TurnActions {
    /// No bar while the turn streams or when there is no answer text to act on (a run of tool cards, or one that failed
    /// before saying anything), like the desktop's `turn.body.length > 0`.
    static func bar(for turn: AssistantTurn, isStreaming: Bool, canRegenerate: Bool) -> TurnActionBar? {
        guard !isStreaming, turn.body.contains(where: { !$0.isWhitespace }) else { return nil }
        return TurnActionBar(
            copyText: turn.body, showsRegenerate: canRegenerate, sourceCount: turn.sources.count,
            timestampMs: turn.timestampMs)
    }

    /// The last turn, once nothing is in flight and there is a question to ask again. The desktop puts Regenerate on
    /// every answer but re-sends the last question whichever one was pressed; here only the answer it belongs to
    /// carries it.
    static func regenerableTurnId(segments: [Segment], hasLoadedHistory: Bool, isTurnInFlight: Bool) -> String? {
        guard hasLoadedHistory, !isTurnInFlight, case .assistantTurn(let turn)? = segments.last,
            resendableUserMessage(in: segments) != nil
        else { return nil }
        return turn.id
    }

    /// A live failure with no turn to sit on (it failed before any step): its error line may ask the question again.
    static func canRetryOrphan(
        segments: [Segment], liveError: LiveRunError?, hasLoadedHistory: Bool, isTurnInFlight: Bool
    ) -> Bool {
        guard hasLoadedHistory, !isTurnInFlight, case .user? = segments.last,
            TranscriptRules.orphanRunError(segments: segments, live: liveError) != nil
        else { return false }
        return resendableUserMessage(in: segments) != nil
    }

    /// The error line carries Regenerate only where no action bar does: a run that failed before writing an answer.
    static func showsRetryOnError(hasError: Bool, bar: TurnActionBar?, canRegenerate: Bool) -> Bool {
        hasError && bar == nil && canRegenerate
    }

    /// The question Regenerate asks again: the transcript's last user message, when it has text or an image to send.
    static func resendableUserMessage(in segments: [Segment]) -> ChatMessage? {
        for segment in segments.reversed() {
            guard case .user(let message) = segment else { continue }
            return isResendable(message) ? message : nil
        }
        return nil
    }

    private static func isResendable(_ message: ChatMessage) -> Bool {
        message.contentBlocks.contains { block in
            switch block {
            case .text(let text): !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .image: true
            case .thinking, .toolCall, .unknown: false
            }
        }
    }

    /// The time at the end of the bar: today's time, a weekday for the last days, else a date, as the Recents list shows it.
    static func timeText(
        _ timestampMs: Double?, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> String? {
        guard let timestampMs, timestampMs.isFinite, timestampMs > 0 else { return nil }
        return RecentTimestamp.format(
            Date(timeIntervalSince1970: timestampMs / 1000), now: now, calendar: calendar, locale: locale)
    }
}
