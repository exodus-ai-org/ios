import Foundation
import MarkdownKit
import Models

/// What the action bar under a finished answer offers; the view only draws this.
struct TurnActionBar: Equatable {
    /// The turn the bar stands under: what read-aloud knows its answer by.
    let turnId: String
    /// What Copy puts on the pasteboard, as the desktop's does: the turn's markdown, with references where it
    /// cited (`CopiedAnswer`).
    let copyText: String
    /// The answer as prose, for read-aloud; empty when there is nothing to say.
    let speechText: String
    let showsRegenerate: Bool
    let sourceCount: Int
    /// The sites the Sources button shows, as the desktop's does: the first three, each once.
    let sourceIcons: [SourceAvatar]
    /// When the answer was written, shown at the end of the bar as the desktop's is; nil for rows without a time.
    let generatedAt: Date?

    /// `speechText` is the answer as prose; left out, it is taken from `copyText`.
    init(
        turnId: String = "", copyText: String, speechText: String? = nil, showsRegenerate: Bool, sourceCount: Int,
        sourceIcons: [SourceAvatar] = [], generatedAt: Date? = nil
    ) {
        self.turnId = turnId
        self.copyText = copyText
        self.speechText = speechText ?? SpeechText.prose(copyText)
        self.showsRegenerate = showsRegenerate
        self.sourceCount = sourceCount
        self.sourceIcons = sourceIcons
        self.generatedAt = generatedAt
    }

    var showsSources: Bool { sourceCount > 0 }
    var showsReadAloud: Bool { !speechText.isEmpty }
}

/// One site of the Sources button: its origin, and Google's icon for it (the desktop's `faviconUrl(origin)`). The
/// default glyph is drawn until the icon comes, and when it does not.
struct SourceAvatar: Equatable, Identifiable {
    let id: String
    let iconURL: URL?
}

/// Which actions a turn gets, and which turn may be asked again; decided from the transcript, drawn by the views.
enum TurnActions {
    /// No bar while the turn streams or when there is no answer text to act on (a run of tool cards, or one that failed
    /// before saying anything), like the desktop's `turn.body.length > 0`.
    static func bar(for turn: AssistantTurn, isStreaming: Bool, canRegenerate: Bool) -> TurnActionBar? {
        guard !isStreaming, turn.body.contains(where: { !$0.isWhitespace }) else { return nil }
        // What the answer cites and what else it found: a turn that cites an earlier turn's search has sources too.
        let sources = TurnSources(turn: turn).all
        return TurnActionBar(
            turnId: turn.id, copyText: CopiedAnswer.text(of: turn), speechText: SpeechText.prose(turn.body),
            showsRegenerate: canRegenerate, sourceCount: sources.count, sourceIcons: sourceIcons(sources),
            generatedAt: turn.timestampMs.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil })
    }

    static let sourceIconLimit = 3

    /// The icons of the Sources button, as the desktop's `SourcesButton` has them: the first three sites among the
    /// sources, each once, in the sources' order — a site being an origin — each with Google's icon for it. Sources
    /// that name no site leave one default glyph, so the button still has its mark.
    static func sourceIcons(_ sources: [CitationSource]) -> [SourceAvatar] {
        guard !sources.isEmpty else { return [] }
        var seen = Set<String>()
        var avatars: [SourceAvatar] = []
        for source in sources {
            guard let site = site(of: source.link), seen.insert(site.origin).inserted else { continue }
            avatars.append(SourceAvatar(id: site.origin, iconURL: SourceIcon.google(host: site.host)))
            if avatars.count == sourceIconLimit { break }
        }
        return avatars.isEmpty ? [SourceAvatar(id: "", iconURL: nil)] : avatars
    }

    /// `https://host[:port]` of a link the app would open, and its host; nil for anything else.
    private static func site(of link: String) -> (origin: String, host: String)? {
        guard let url = ExternalLinkPolicy.openableURL(link), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", let host = url.host()?.lowercased(), !host.isEmpty
        else { return nil }
        return (url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)", host)
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
}
