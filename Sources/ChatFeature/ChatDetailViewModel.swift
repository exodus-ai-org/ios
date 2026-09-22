import Foundation
import Models
import NetworkingKit
import Observation

@MainActor
@Observable
public final class ChatDetailViewModel {
    public let chatId: String
    public private(set) var messages: [ChatMessage] = []
    public private(set) var status: ChatStatus = .idle
    public var composerText: String = ""
    public private(set) var chatTitle: String?
    public var errorMessage: String?
    /// True once the transcript is known: history loaded, or re-attached to an in-flight turn.
    /// Nothing is sent before that — the prior turns of a POST are the LLM context when the
    /// server's LCM feature is off, and the desktop does not render a chat before its history.
    public private(set) var hasLoadedHistory = false
    /// Whether this chat already had messages when it was first opened. A chat that was empty then
    /// is a new chat and keeps "New chat" in the title bar until the server sends a generated
    /// title; without this the title changed twice in one turn — to "Chat" the instant the first
    /// message was sent, and to the generated title a few seconds later.
    ///
    /// Only the first `loadHistory` sets this. A view model that re-attached to a turn already in
    /// flight never loaded a history, so it leaves this `false` and would call an old chat new —
    /// which only shows when that chat has no title at all, and a chat opened from the sidebar
    /// carries its title into `init`, so the re-attach path does not normally reach this fallback.
    private var openedWithMessages = false

    /// Bumped exactly once each time the user's own tap starts a turn — a plain counter so a
    /// `sensoryFeedback` trigger changes on every send, including a second send in the same chat.
    /// Never bumped by `loadHistory` or by `onAppear`'s re-attach to a turn already running (that
    /// sets `status` directly, not through here), and never by a tap `canSend` rejects.
    public private(set) var sendCount = 0
    /// Bumped exactly once when `stop()` actually cancelled a live turn — that is, when
    /// `ChatStreamManager.cancel(_:)` itself reports it found and stopped something. Not bumped
    /// merely because this view model *thought* a turn was in flight: `isTurnInFlight` mirrors the
    /// manager's state only up to the last update this view model has drained, and a turn can
    /// finish or fail on the manager side (removing its entry) before that drain catches up, since
    /// the manager's own update is only buffered until the `for await` loop in `consume` gets to
    /// it. Trusting the local flag alone here would occasionally mislabel a turn that had already
    /// finished normally as "stopped" — see `ChatStreamManagerTests` for `cancel`'s own coverage of
    /// this. Waiting for the manager's answer, rather than deciding synchronously on the tap, is
    /// the price of that correctness.
    public private(set) var stopCount = 0
    /// Bumped exactly once when a turn's stream ends with the server's own `.finished` and the user
    /// did not press Stop for it — a normal completion. Not bumped for a stopped turn, a failed
    /// turn, or a re-attach whose `consume` never receives a `.finished` at all.
    public private(set) var completedTurnCount = 0
    /// True while the turn in flight was ended by `stop()`, so `consume`'s `.finished` (the manager
    /// sends one for a stop too, see `ChatStreamManager.cancel`) is not counted as a normal
    /// completion. Reset at the start of every new send.
    private var turnWasStopped = false

    private let apiClient: APIClient
    private let streamManager: ChatStreamManager
    private let serverConfig: ServerConfigStore

    public init(
        chatId: String, title: String? = nil, apiClient: APIClient, streamManager: ChatStreamManager,
        serverConfig: ServerConfigStore
    ) {
        self.chatId = chatId
        self.chatTitle = Self.oneLine(title)
        self.apiClient = apiClient
        self.streamManager = streamManager
        self.serverConfig = serverConfig
    }

    public var isTurnInFlight: Bool { status == .submitted || status == .streaming }

    /// True while a turn is in flight and nothing the assistant said is at the end of the
    /// transcript yet: from tapping send until the server's first assistant message, and again
    /// after a tool result. The view shows a "…" bubble so the screen is not dead in the meantime.
    public var showsPendingRow: Bool { isTurnInFlight && messages.last?.role != "assistant" }

    public var canSend: Bool {
        hasLoadedHistory && !isTurnInFlight
            && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True for a loaded, empty chat with nothing in flight: the view shows its greeting. Never true
    /// before the history is known, so opening a chat does not flash the greeting.
    public var showsEmptyState: Bool { hasLoadedHistory && messages.isEmpty && !isTurnInFlight }

    /// What the title bar shows: the chat's own title, cut to a length a title bar can carry, else
    /// "New chat" for a chat that was empty when it was opened and "Chat" for one that was opened
    /// with messages and has no title yet.
    public var displayTitle: String {
        guard let chatTitle else {
            return openedWithMessages ? String(localized: "Chat") : String(localized: "New chat")
        }
        return Self.shortened(chatTitle)
    }

    public func onAppear() async {
        if await streamManager.isStreaming(chatId), let updates = await streamManager.attach(chatId) {
            hasLoadedHistory = true
            status = .streaming
            await consume(updates)
        } else {
            await loadHistory()
        }
    }

    public func loadHistory() async {
        guard !isTurnInFlight else { return }  // a reload would replace the reply that is being streamed
        do {
            let rows: [ChatMessage] = try await apiClient.get("/api/v1/chat/\(chatId)")
            messages = ChatHistoryRows.uiMessages(from: rows)
            // Only the first load says what this chat was; a later pull-to-refresh sees the turns
            // that have happened since and must not turn a new chat into an old one.
            if !hasLoadedHistory { openedWithMessages = !messages.isEmpty }
            hasLoadedHistory = true
        } catch {
            // SwiftUI cancels a view's `.task` when the view goes away; that is not a failure.
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func sendMessage() async {
        guard canSend else { return }
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        composerText = ""

        let userMessage = ChatMessage.userMessage(
            id: UUID().uuidString.lowercased(), text: text, timestampMs: Date().timeIntervalSince1970 * 1000)
        messages.append(userMessage)
        turnWasStopped = false
        sendCount += 1
        status = .submitted  // disable the composer now, before the first stream update arrives

        let updates = await streamManager.send(chatId: chatId, messages: messages, serverConfig: serverConfig)
        await consume(updates)
    }

    /// Ends the turn in flight (the Stop button): the partial reply stays, and no error is shown.
    /// `consume` receives the manager's `.status(.idle)` and `.finished` and ends by itself.
    /// Does nothing when this view model has no turn in flight, so an idle view model can never
    /// cancel a turn that belongs to someone else.
    ///
    /// `isTurnInFlight` is only a locally cached mirror of the manager's state, so it can still
    /// read `true` for a moment after the turn has already finished or failed on the manager side
    /// (that update is sitting in the stream, not drained by `consume` yet). `cancel(_:)`'s own
    /// `Bool` is the one atomic answer for whether this call actually stopped anything; only then
    /// is this counted as a stop, so a turn that in truth already ended normally cannot be
    /// mislabeled here and have its real `.finished` wrongly excluded from `completedTurnCount`.
    public func stop() async {
        guard isTurnInFlight else { return }
        guard await streamManager.cancel(chatId) else { return }
        turnWasStopped = true
        stopCount += 1
    }

    private func consume(_ updates: AsyncStream<ChatStreamUpdate>) async {
        for await update in updates {
            switch update {
            case .messages(let messages):
                self.messages = messages
            case .status(let status):
                self.status = status
            case .title(let title):
                chatTitle = Self.oneLine(title) ?? chatTitle
            case .finished(let messages):
                self.messages = messages
                status = .idle
                if !turnWasStopped { completedTurnCount += 1 }
            case .failed(let message):
                errorMessage = message
                status = .error
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// A chat title on one line; nil when there is nothing to show. Real titles can be long and multi-line.
    private static func oneLine(_ title: String?) -> String? {
        guard let collapsed = title?.collapsedWhitespace, !collapsed.isEmpty else { return nil }
        return collapsed
    }

    /// Generated titles are not bounded — the owner's history holds one of 1211 characters — while a
    /// title bar shows about thirty. Handed the whole string, the bar stops centring the title and
    /// stretches it across the toolbar buttons, so the displayed text is cut here. `chatTitle` keeps
    /// the server's text as it came.
    private static let displayTitleLimit = 80

    private static func shortened(_ title: String) -> String {
        guard title.count > displayTitleLimit else { return title }
        return title.prefix(displayTitleLimit).trimmingCharacters(in: .whitespaces) + "…"
    }
}
